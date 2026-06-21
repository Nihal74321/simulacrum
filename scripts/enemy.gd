extends CharacterBody2D

const SPEED: float = 60.0
const DETECTION_RANGE: float = 120.0
const ATTACK_RANGE: float = 18.0
const ATTACK_DAMAGE: int = 2
const ATTACK_COOLDOWN: float = 1.0
const PLAYER_ATTACK_DAMAGE: int = 5
# Weapon attack ranges (px from player centre to enemy centre)
const SWORD_RANGE: float = 40.0   # ~2.5 tiles
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
		match weapon:
			"Great Axe":
				attack_range = SWORD_RANGE
				damage = PLAYER_ATTACK_DAMAGE
			_:
				GameManager.feedback_requested.emit("I can't attack with that.")
				return
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p == null:
			return
		if global_position.distance_to(p.global_position) > attack_range:
			GameManager.feedback_requested.emit("Too far away.")
			return
		take_damage(damage)

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
	if player.has_method("take_damage"):
		player.take_damage(ATTACK_DAMAGE)

func take_damage(amount: int) -> void:
	var final_amount: int = amount * 999 if GameManager.godmode else amount
	health -= final_amount
	if health <= 0:
		_die()

func _die() -> void:
	var kf_amount: int = 500 if is_in_group("bosses") else (100 if is_in_group("minibosses") else 50)
	Inventory.add_item({
		"name": "Knowledge Fragment",
		"description": "Crystallised memory from a slain simulacrum.",
		"quantity": kf_amount,
	})
	GameManager.item_picked_up.emit("Knowledge Fragment", kf_amount)
	queue_free()
