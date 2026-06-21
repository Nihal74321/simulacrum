extends CharacterBody2D

const BASE_SPEED: float = 97.75
const ARRIVAL_THRESHOLD: float = 4.0
const SPRINT_MULTIPLIER: float = 1.47
const SPRINT_MAX: float = 3.0
const SPRINT_DRAIN: float = 1.0
const SPRINT_RECHARGE: float = 5.0 / 3.0
const INTERACTABLE_STOP_RADIUS: float = 48.0
const HOLD_THRESHOLD: float = 0.2

const ROLL_DISTANCE: float = 48.0
const ROLL_DISTANCE_WATER: float = 32.0
const ROLL_DURATION: float = 0.18
const ROLL_COOLDOWN: float = 0.5
const WATER_TILE: Vector2i = Vector2i(0, 1)
const WATER_SPEED_MULT: float = 0.85

# 16 directional angles available in the warrior asset (degrees from East, CW)
const WARRIOR_ANGLES: Array[int] = [0, 22, 45, 67, 90, 112, 135, 157, 180, 202, 225, 247, 270, 292, 315, 337]
const WARRIOR_BASE: String = "res://asset-holder/Warrior/x256p_Spritesheets/"
# Walk  1024×1024 → 4×4 = 16 frames
const WALK_HFRAMES: int = 4
const WALK_VFRAMES: int = 4
const WALK_FRAMES: int = 16
# Run   1536×1024 → 6×4 = 24 frames
const RUN_HFRAMES: int = 6
const RUN_VFRAMES: int = 4
const RUN_FRAMES: int = 24
# Idle  1536×1024 → 6×4 = 24 frames
const IDLE_HFRAMES: int = 6
const IDLE_VFRAMES: int = 4
const IDLE_FRAMES: int = 24

const RUN_FPS: float = 18.0
const WALK_FPS: float = 14.0
const IDLE_FPS: float = 8.0
const SPRITE_SCALE: float = 0.325  # 256px → ~84px world units
# Offset to align spritesheet angles to Godot's vel.angle() convention.
const DIR_OFFSET: float = 90.0

var max_health: int = 100
var health: int = 100
var move_target: Vector2 = Vector2(INF, INF)
var _mouse_held: bool = false
var _mouse_press_time: float = 0.0
var sprint_energy: float = SPRINT_MAX
var is_sprinting: bool = false
var _sprint_depleted: bool = false
var _dying: bool = false

var _rolling: bool = false
var _roll_timer: float = 0.0
var _roll_cooldown: float = 0.0
var _roll_velocity: Vector2 = Vector2.ZERO
var _on_water: bool = false

# Sprite state
var _sprite: Sprite2D
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _cur_angle: int = 180
var _is_walking: bool = false
var _tex_cache: Dictionary = {}
# Smoothed velocity for direction snapping — prevents jerk when raw velocity
# fluctuates near an angle-zone boundary between frames.
var _smooth_vel: Vector2 = Vector2.ZERO
var _roll_ghosts: Array[Sprite2D] = []

func _ready() -> void:
	add_to_group("player")
	GameManager.health_changed.emit(health, max_health)
	_build_sprite()

func _build_sprite() -> void:
	var body := get_node_or_null("Body")
	if body:
		body.visible = false

	# Preload all directional textures now so mid-game loads never stall the
	# renderer and cause a one-frame transparent blink.
	for state in ["Idle", "Walk", "Run"]:
		for angle in WARRIOR_ANGLES:
			_get_tex(state, angle)

	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.position = Vector2(0, -16)
	_sprite.z_index = 5
	add_child(_sprite)
	_set_anim("Idle", _cur_angle)

func _tex_key(state: String, angle: int) -> String:
	return "%s_%03d" % [state, angle]

func _get_tex(state: String, angle: int) -> Texture2D:
	var key := _tex_key(state, angle)
	if not _tex_cache.has(key):
		var path := WARRIOR_BASE + state + "/" + state + "_Body_%03d.png" % angle
		_tex_cache[key] = load(path) as Texture2D
	return _tex_cache[key]

func _set_anim(state: String, angle: int) -> void:
	var tex := _get_tex(state, angle)
	if tex != null:
		_sprite.texture = tex
	# Grid dimensions differ per state — must be set before assigning frame.
	match state:
		"Walk":
			_sprite.hframes = WALK_HFRAMES
			_sprite.vframes = WALK_VFRAMES
		"Run":
			_sprite.hframes = RUN_HFRAMES
			_sprite.vframes = RUN_VFRAMES
		_:
			_sprite.hframes = IDLE_HFRAMES
			_sprite.vframes = IDLE_VFRAMES
	_anim_frame = 0
	_anim_timer = 0.0
	_sprite.frame = 0

func _snap_angle(vel: Vector2) -> int:
	var deg := fmod(rad_to_deg(vel.angle()) + DIR_OFFSET + 720.0, 360.0)
	var best := WARRIOR_ANGLES[0]
	var best_diff := 360.0
	for a in WARRIOR_ANGLES:
		var diff := absf(fmod(deg - a + 540.0, 360.0) - 180.0)
		if diff < best_diff:
			best_diff = diff
			best = a
	return best

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_held = true
			_mouse_press_time = 0.0
			move_target = _clamped_target(get_global_mouse_position())
		else:
			_mouse_held = false
			if _mouse_press_time >= HOLD_THRESHOLD:
				move_target = Vector2(INF, INF)

	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_SPACE:
		_try_roll()

func _is_on_water() -> bool:
	var tm := get_tree().get_first_node_in_group("tilemap") as TileMapLayer
	if tm == null:
		return false
	var cell := tm.local_to_map(tm.to_local(global_position))
	return tm.get_cell_atlas_coords(cell) == WATER_TILE

func _try_roll() -> void:
	if _rolling or _roll_cooldown > 0.0:
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var dir := (get_global_mouse_position() - global_position)
	if dir.length_squared() < 1.0:
		return
	var dist := ROLL_DISTANCE_WATER if _on_water else ROLL_DISTANCE
	_roll_velocity = dir.normalized() * (dist / ROLL_DURATION)
	_roll_timer = ROLL_DURATION
	_rolling = true
	move_target = Vector2(INF, INF)
	_spawn_roll_ghosts()

func _spawn_roll_ghosts() -> void:
	_clear_roll_ghosts()
	var scene_root: Node = get_parent().get_parent()
	# Snapshot the sprite's current state for both ghosts.
	var base_pos: Vector2 = global_position + Vector2(0, -16)
	var roll_dir: Vector2 = _roll_velocity.normalized()
	# Ghost 0 is closer (75% opacity), ghost 1 is further back (50% opacity).
	var offsets: Array[Vector2] = [
		-roll_dir * 6.0,
		-roll_dir * 14.0,
	]
	var alphas: Array[float] = [0.75, 0.5]
	for i in 2:
		var ghost := Sprite2D.new()
		ghost.texture  = _sprite.texture
		ghost.hframes  = _sprite.hframes
		ghost.vframes  = _sprite.vframes
		ghost.frame    = _sprite.frame
		ghost.scale    = _sprite.scale
		ghost.modulate = Color(0.3, 0.6, 1.0, alphas[i])
		ghost.z_index  = 3
		ghost.global_position = base_pos + offsets[i]
		scene_root.add_child(ghost)
		_roll_ghosts.append(ghost)

func _update_roll_ghosts() -> void:
	# Fade ghosts out as roll progresses (t goes 0→1 over roll duration).
	var t := 1.0 - (_roll_timer / ROLL_DURATION)
	var alphas: Array[float] = [0.75, 0.5]
	for i in mini(_roll_ghosts.size(), 2):
		if is_instance_valid(_roll_ghosts[i]):
			_roll_ghosts[i].modulate.a = alphas[i] * (1.0 - t)

func _clear_roll_ghosts() -> void:
	for g in _roll_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_roll_ghosts.clear()

func _physics_process(delta: float) -> void:
	var was_on_water := _on_water
	_on_water = _is_on_water()
	if _on_water and not was_on_water:
		var msgs := ["Cold.", "That's wet."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])

	var focus_owner := get_viewport().gui_get_focus_owner()
	var text_focused := focus_owner != null and focus_owner is LineEdit
	if GameManager.block_input or text_focused:
		move_target = Vector2(INF, INF)
		_mouse_held = false
		velocity = Vector2.ZERO
		move_and_slide()
		_tick_sprite(delta, false)
		return

	if _rolling:
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			_rolling = false
			_roll_cooldown = ROLL_COOLDOWN
			velocity = Vector2.ZERO
			_clear_roll_ghosts()
		else:
			velocity = _roll_velocity
			_update_roll_ghosts()
		move_and_slide()
		_tick_sprite(delta, _rolling)
		return

	if _roll_cooldown > 0.0:
		_roll_cooldown -= delta

	var shift_held := Input.is_action_pressed("sprint") and not text_focused
	var is_moving := velocity.length_squared() > 1.0

	if shift_held and sprint_energy > 0.0 and not _sprint_depleted and is_moving:
		is_sprinting = true
		sprint_energy = max(sprint_energy - SPRINT_DRAIN * delta, 0.0)
		if sprint_energy == 0.0:
			_sprint_depleted = true
	else:
		is_sprinting = false
		sprint_energy = min(sprint_energy + SPRINT_RECHARGE * delta, SPRINT_MAX)
		if sprint_energy >= SPRINT_MAX:
			_sprint_depleted = false

	GameManager.sprint_energy = sprint_energy
	GameManager.sprint_active = is_sprinting

	if _mouse_held:
		_mouse_press_time += delta
		move_target = _clamped_target(get_global_mouse_position())

	if move_target.x < INF:
		var to_target := move_target - global_position
		if to_target.length() < ARRIVAL_THRESHOLD:
			move_target = Vector2(INF, INF)
			velocity = Vector2.ZERO
		else:
			var speed_mult := GameManager.get_speed_multiplier()
			if is_sprinting:
				speed_mult *= SPRINT_MULTIPLIER
			if _on_water:
				speed_mult *= WATER_SPEED_MULT
			velocity = to_target.normalized() * BASE_SPEED * speed_mult / Engine.time_scale
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	# Use move_target intent (not physics velocity) to decide walk vs idle —
	# velocity jitters to 0 on collision frames and causes blink.
	_tick_sprite(delta, move_target.x < INF)

func _tick_sprite(delta: float, intended_walk: bool) -> void:
	var state: String
	if not intended_walk:
		state = "Idle"
	elif is_sprinting:
		state = "Run"
	else:
		state = "Walk"

	# Smooth velocity to prevent direction jitter near angle zone boundaries.
	_smooth_vel = _smooth_vel.lerp(velocity, 0.15)
	if intended_walk and _smooth_vel.length_squared() > 16.0:
		var new_angle := _snap_angle(_smooth_vel)
		if new_angle != _cur_angle:
			_cur_angle = new_angle
			# Swap texture + correct grid without resetting frame.
			var tex := _get_tex(state, _cur_angle)
			if tex != null:
				match state:
					"Walk":
						_sprite.hframes = WALK_HFRAMES
						_sprite.vframes = WALK_VFRAMES
					"Run":
						_sprite.hframes = RUN_HFRAMES
						_sprite.vframes = RUN_VFRAMES
				_sprite.texture = tex

	# Reset frame only when animation state actually changes.
	if state != _cur_state():
		_set_anim(state, _cur_angle)
		_is_walking = intended_walk

	var fps: float
	var total: int
	match state:
		"Walk": fps = WALK_FPS; total = WALK_FRAMES
		"Run":  fps = RUN_FPS;  total = RUN_FRAMES
		_:      fps = IDLE_FPS; total = IDLE_FRAMES

	_anim_timer += delta
	if _anim_timer >= 1.0 / fps:
		_anim_timer = fmod(_anim_timer, 1.0 / fps)
		_anim_frame = (_anim_frame + 1) % total
		_sprite.frame = _anim_frame

func _cur_state() -> String:
	if not _is_walking:
		return "Idle"
	return "Run" if is_sprinting else "Walk"

func _clamped_target(raw: Vector2) -> Vector2:
	for group_name: String in ["machines", "enemies", "pois"]:
		for obj in get_tree().get_nodes_in_group(group_name):
			var node := obj as Node2D
			if node == null:
				continue
			var to_raw := raw - node.global_position
			if to_raw.length() < INTERACTABLE_STOP_RADIUS:
				if global_position.distance_to(node.global_position) < INTERACTABLE_STOP_RADIUS:
					return global_position
				var dir := to_raw.normalized() if to_raw.length() > 0.01 else \
					(global_position - node.global_position).normalized()
				if dir.length() < 0.01:
					dir = Vector2(0, -1)
				return node.global_position + dir * INTERACTABLE_STOP_RADIUS
	return raw

func take_damage(amount: int) -> void:
	if GameManager.godmode:
		return
	health = max(health - amount, 0)
	GameManager.health_changed.emit(health, max_health)
	if health == 0:
		_die()

func heal(amount: int) -> void:
	health = min(health + amount, max_health)
	GameManager.health_changed.emit(health, max_health)

func _die() -> void:
	if _dying:
		return
	_dying = true
	health = max_health
	GameManager.health_changed.emit(health, max_health)
	velocity = Vector2.ZERO
	move_target = Vector2(INF, INF)
	if GameManager.dungeon_active:
		GameManager.dungeon_active = false
		GameManager.player_died.emit()
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	_dying = false
