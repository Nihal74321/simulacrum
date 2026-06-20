extends CharacterBody2D

const BASE_SPEED: float = 97.75         # 15% slower than original 115
const ARRIVAL_THRESHOLD: float = 4.0
const SPRINT_MULTIPLIER: float = 1.47   # keeps sprint at ~144 px/s (same as before)
const SPRINT_MAX: float = 3.0           # 3 seconds max
const SPRINT_DRAIN: float = 1.0         # depletes in 3 s
const SPRINT_RECHARGE: float = 5.0 / 3.0
const INTERACTABLE_STOP_RADIUS: float = 48.0
const HOLD_THRESHOLD: float = 0.2

# Roll: 3 iso-tiles (3 × 16 px) in mouse direction
const ROLL_DISTANCE: float = 48.0
const ROLL_DISTANCE_WATER: float = 32.0  # 2 tiles in water
const ROLL_DURATION: float = 0.18
const ROLL_COOLDOWN: float = 0.5
const WATER_TILE: Vector2i = Vector2i(0, 1)
const WATER_SPEED_MULT: float = 0.85

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

func _ready() -> void:
	add_to_group("player")
	GameManager.health_changed.emit(health, max_health)

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

func _physics_process(delta: float) -> void:
	# Water tile detection — check once per frame before any movement
	var was_on_water := _on_water
	_on_water = _is_on_water()
	if _on_water and not was_on_water:
		var msgs := ["Cold.", "That's wet."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])

	# Block all movement when a GUI overlay is open or a text field has focus
	var focus_owner := get_viewport().gui_get_focus_owner()
	var text_focused := focus_owner != null and focus_owner is LineEdit
	if GameManager.block_input or text_focused:
		move_target = Vector2(INF, INF)
		_mouse_held = false
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Roll
	if _rolling:
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			_rolling = false
			_roll_cooldown = ROLL_COOLDOWN
			velocity = Vector2.ZERO
		else:
			velocity = _roll_velocity
		move_and_slide()
		return

	if _roll_cooldown > 0.0:
		_roll_cooldown -= delta

	# Sprint — only drain when the player is actually moving
	var shift_held := Input.is_action_pressed("sprint") and not text_focused
	var is_moving := velocity.length_squared() > 1.0  # previous frame velocity

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

	# Movement — continuously clamp target when holding
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
			# Divide by time_scale so gamespeed (Engine.time_scale) doesn't affect movement
			velocity = to_target.normalized() * BASE_SPEED * speed_mult / Engine.time_scale
	else:
		velocity = Vector2.ZERO

	move_and_slide()

func _clamped_target(raw: Vector2) -> Vector2:
	for group_name: String in ["machines", "enemies", "pois"]:
		for obj in get_tree().get_nodes_in_group(group_name):
			var node := obj as Node2D
			if node == null:
				continue
			var to_raw := raw - node.global_position
			if to_raw.length() < INTERACTABLE_STOP_RADIUS:
				# Already close enough — don't reposition the player
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
