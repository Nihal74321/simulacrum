extends CharacterBody2D

const SPEED: float = 60.0
const DETECTION_RANGE: float = 120.0
const ATTACK_RANGE: float = 18.0
const ATTACK_COOLDOWN: float = 1.0
const PLAYER_ATTACK_DAMAGE: int = 5

# Instance-level stats (override via set() for minibosses)
var attack_damage: int = 2
var miss_chance: float = 0.25
# Weapon attack ranges (px from player centre to enemy centre)
const SWORD_RANGE: float = 48.0      # Great Axe: 3-tile radius
const BROADAXE_RANGE: float = 32.0   # Broadaxe: 2-tile radius
const CROSSBOW_RANGE: float = 560.0  # Crossbow: 35-tile radius
const HUNTER_RANGE_BONUS: float = 16.0  # Boon of the Hunter: +1 tile
const HOVER_RADIUS: float = 13.0
# Body bounds: (-6.4,-9.6) to (6.4,9.6) — 20% smaller than original
const OUTLINE_RECT: Rect2 = Rect2(-7, -10, 14, 20)
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const OUTLINE_WIDTH: float = 1.0

@export var max_health: int = 20
@export var body_color: Color = Color(0.9, 0.15, 0.15, 1)

const HP_BAR_WIDTH: float = 14.0
const HP_BAR_HEIGHT: float = 2.5
const HP_BAR_Y: float = -14.0
# 4 iso tiles ≈ 4 × 16px tile half-width converted to world distance
const HP_FADE_RANGE: float = 80.0
const HP_FADE_SPEED: float = 3.0

var health: int = 0
var player: Node2D = null
var attack_timer: float = 0.0
var _hovered: bool = false
var _hp_alpha: float = 0.0

@onready var body: Polygon2D = $Body
@onready var mouse_area: Area2D = $MouseArea

func _ready() -> void:
	z_index = 10
	health = max_health
	body.color = body_color
	add_to_group("enemies")
	# Put enemies on layer 2 so the player (layer 1) passes through them
	collision_layer = 2
	collision_mask  = 1  # still bump into walls
	player = get_tree().get_first_node_in_group("player")
	mouse_area.input_event.connect(_on_mouse_input)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()

	var in_range := player != null and global_position.distance_to(player.global_position) <= HP_FADE_RANGE
	var target_alpha := 1.0 if in_range else 0.0
	_hp_alpha = move_toward(_hp_alpha, target_alpha, HP_FADE_SPEED * delta)
	queue_redraw()

func _draw() -> void:
	if _hovered:
		draw_rect(OUTLINE_RECT, OUTLINE_COLOR, false, OUTLINE_WIDTH)
	if _hp_alpha > 0.01:
		var bar_x := -HP_BAR_WIDTH * 0.5
		# Background
		draw_rect(Rect2(bar_x, HP_BAR_Y, HP_BAR_WIDTH, HP_BAR_HEIGHT),
			Color(0.15, 0.15, 0.15, _hp_alpha))
		# Fill
		var fill_w := HP_BAR_WIDTH * (float(health) / float(max_health))
		if fill_w > 0.0:
			draw_rect(Rect2(bar_x, HP_BAR_Y, fill_w, HP_BAR_HEIGHT),
				Color(0.9, 0.15, 0.15, _hp_alpha))

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _v is Viewport:
			(_v as Viewport).set_input_as_handled()
		var weapon := GameManager.equipped_weapon
		if weapon.is_empty():
			GameManager.feedback_requested.emit("I have nothing to fight with.")
			return
		var attack_range: float
		var damage: int
		var cooldown: float = -1.0  # -1 = use player default (1s)
		match weapon:
			"Great Axe":
				attack_range = SWORD_RANGE
				damage = 14
			"Broadaxe":
				attack_range = BROADAXE_RANGE
				damage = 10
			"Crossbow":
				attack_range = CROSSBOW_RANGE
				damage = 4
				cooldown = 2.0
			_:
				GameManager.feedback_requested.emit("I can't attack with that.")
				return
		# Boon of the Hunter: +1 tile melee range (not crossbow)
		if weapon != "Crossbow" and GameManager.has_boon("Boon of the Hunter"):
			attack_range += HUNTER_RANGE_BONUS
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p == null:
			return
		if global_position.distance_to(p.global_position) > attack_range:
			GameManager.feedback_requested.emit("Too far away.")
			return
		# Request attack — enforces the cooldown and turns the player to face us.
		if p.has_method("request_attack"):
			if not p.request_attack(self, cooldown):
				return
		var final_dmg := damage
		if GameManager.has_boon("Iron Gauntlet"):
			final_dmg = int(final_dmg * 1.50)
		# Crossbow: projectile visual, 10% miss chance; damage applied on arrival
		if weapon == "Crossbow":
			var missed := randf() < 0.10
			_fire_crossbow_projectile(p.global_position, missed, final_dmg)
			if missed:
				_show_miss_text()
			return
		take_damage(final_dmg)

func _fire_crossbow_projectile(from_pos: Vector2, missed: bool, dmg: int = 4) -> void:
	var proj := Node2D.new()
	proj.z_index = 20
	var to_pos := global_position  # enemy position = target
	var dir := (to_pos - from_pos).normalized()
	# Miss: fly 80px past the target
	var end_pos := (to_pos + dir * 80.0) if missed else to_pos

	var elapsed := 0.0
	var travel_time := from_pos.distance_to(end_pos) / 480.0  # 480 px/s
	var dmg_applied := false
	var enemy_ref := self

	var scr := GDScript.new()
	scr.source_code = """
extends Node2D
var from_pos: Vector2
var end_pos: Vector2
var elapsed: float = 0.0
var travel_time: float = 1.0
var missed: bool = false
var dmg: int = 4
var enemy_ref: Node = null
var dmg_applied: bool = false

func _process(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / travel_time, 0.0, 1.0)
	global_position = from_pos.lerp(end_pos, t)
	queue_redraw()
	if not missed and not dmg_applied and t >= 1.0:
		dmg_applied = true
		if is_instance_valid(enemy_ref) and enemy_ref.has_method("take_damage"):
			enemy_ref.take_damage(dmg)
	if t >= 1.0:
		queue_free()

func _draw() -> void:
	var dir := Vector2(1, 0)
	draw_rect(Rect2(-5, -1, 10, 2), Color(0.95, 0.85, 0.4, 0.9))
"""
	proj.set_script(scr)
	proj.global_position = from_pos
	var dir_angle := dir.angle()
	proj.rotation = dir_angle
	proj.set("from_pos", from_pos)
	proj.set("end_pos", end_pos)
	proj.set("travel_time", travel_time)
	proj.set("missed", missed)
	proj.set("dmg", dmg)
	proj.set("enemy_ref", enemy_ref)
	get_tree().current_scene.add_child(proj)

func _show_miss_text() -> void:
	var lbl := Label.new()
	lbl.text = "Miss!"
	lbl.position = Vector2(-14, -22)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	lbl.z_index = 25
	add_child(lbl)
	var tw := create_tween()
	tw.parallel().tween_property(lbl, "position:y", lbl.position.y - 20.0, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	attack_timer = max(attack_timer - delta, 0.0)
	var dist: float = global_position.distance_to(player.global_position)

	if dist <= ATTACK_RANGE:
		velocity = Vector2.ZERO
		if attack_timer == 0.0:
			_attack()
	elif dist <= DETECTION_RANGE:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		velocity = Vector2(dir.x, dir.y * 0.5) * SPEED
		move_and_slide()
	else:
		velocity = Vector2.ZERO

func _attack() -> void:
	attack_timer = ATTACK_COOLDOWN
	# Rolling always dodges an incoming hit
	if player.has_method("is_dodging") and player.is_dodging():
		return
	if randf() < miss_chance:
		return
	if player.has_method("take_damage"):
		player.take_damage(attack_damage)

func take_damage(amount: int) -> void:
	var final_amount: int = amount * 999 if GameManager.godmode else amount
	health -= final_amount
	if health <= 0:
		_die()

func _die() -> void:
	var kf_amount: int = 250 if is_in_group("bosses") else (randi_range(75, 150) if is_in_group("minibosses") else randi_range(50, 150))
	Inventory.add_item({
		"name": "Knowledge Fragment",
		"description": "Crystallised memory from a slain simulacrum.",
		"quantity": kf_amount,
	})
	GameManager.item_picked_up.emit("Knowledge Fragment", kf_amount)
	queue_free()
