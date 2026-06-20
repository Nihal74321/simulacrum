extends Node2D

const HOVER_RADIUS: float = 18.0
const INTERACTION_RANGE: float = 80.0
const ROCKS_PER_HIT: int = 10
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

var big: bool = false       # set before add_child
var _hits_remaining: int = 1
var _hovered: bool = false
var _label: Label
var _label_alpha: float = 0.0

func _ready() -> void:
	z_index = 7
	_hits_remaining = randi_range(1, 5)
	_build_visual()

	_label = Label.new()
	_label.text = "Big Stone" if big else "Stone"
	_label.position = Vector2(-18, -30) if big else Vector2(-12, -24)
	_label.add_theme_font_size_override("font_size", 7)
	_label.modulate.a = 0.0
	_label.z_index = 20
	add_child(_label)

	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HOVER_RADIUS
	cs.shape = circle
	cs.position = Vector2(0, -8) if big else Vector2(0, -6)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _build_visual() -> void:
	var scale_f: float = 1.7 if big else 1.0
	var base_color := Color(0.48, 0.47, 0.50, 1)
	var highlight := Color(0.62, 0.61, 0.63, 1)
	var shadow   := Color(0.36, 0.35, 0.38, 1)

	# Main body
	var body := Polygon2D.new()
	var bw: float = 12.0 * scale_f
	var bh: float = 10.0 * scale_f
	body.polygon = PackedVector2Array([
		Vector2(-bw * 0.5, 0),   Vector2(-bw * 0.8, -bh * 0.4),
		Vector2(-bw * 0.3, -bh), Vector2(bw * 0.4, -bh),
		Vector2(bw, -bh * 0.5),  Vector2(bw * 0.7, 0),
	])
	body.color = base_color
	add_child(body)

	# Highlight chip
	var chip := Polygon2D.new()
	chip.polygon = PackedVector2Array([
		Vector2(-bw * 0.1, -bh * 0.55), Vector2(bw * 0.3, -bh * 0.85),
		Vector2(bw * 0.5, -bh * 0.6),   Vector2(bw * 0.1, -bh * 0.35),
	])
	chip.color = highlight
	add_child(chip)

	# Shadow base
	var shad := Polygon2D.new()
	shad.polygon = PackedVector2Array([
		Vector2(-bw * 0.5, 0), Vector2(bw * 0.7, 0),
		Vector2(bw * 0.55, bh * 0.3), Vector2(-bw * 0.35, bh * 0.3),
	])
	shad.color = shadow
	add_child(shad)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered:
		var r: float = (HOVER_RADIUS + 2.0)
		draw_arc(Vector2(0, -8 if big else -6), r, 0, TAU, 20, OUTLINE_COLOR, 1.0)

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	if _v is Viewport:
		(_v as Viewport).set_input_as_handled()

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to((player as Node2D).global_position) > INTERACTION_RANGE:
		GameManager.feedback_requested.emit("Too far away.")
		return
	if big and GameManager.hotbar[GameManager.hotbar_selected] != "Pickaxe":
		var msgs := ["I can't do that.", "Not now.", "I need a tool."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])
		return

	Inventory.add_item({"name": "Rock", "description": "A chunk of stone.", "quantity": ROCKS_PER_HIT})
	GameManager.item_picked_up.emit("Rock", ROCKS_PER_HIT)
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		queue_free()
