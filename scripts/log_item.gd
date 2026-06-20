extends Node2D

const HOVER_RADIUS: float = 10.0
const INTERACTION_RANGE: float = 64.0
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

var _hovered: bool = false
var _label: Label
var _label_alpha: float = 0.0

func _ready() -> void:
	z_index = 5

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-8, -2), Vector2(8, -2), Vector2(8, 2), Vector2(-8, 2)
	])
	body.color = Color(0.44, 0.27, 0.11, 1)
	add_child(body)

	# End caps
	var cap_l := Polygon2D.new()
	cap_l.polygon = PackedVector2Array([Vector2(-9, -2), Vector2(-8, -2), Vector2(-8, 2), Vector2(-9, 2)])
	cap_l.color = Color(0.34, 0.20, 0.09, 1)
	add_child(cap_l)

	_label = Label.new()
	_label.text = "Log"
	_label.position = Vector2(-8, -14)
	_label.add_theme_font_size_override("font_size", 7)
	_label.modulate.a = 0.0
	_label.z_index = 20
	add_child(_label)

	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 8)
	cs.shape = rect
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered:
		draw_rect(Rect2(-9, -3, 18, 6), OUTLINE_COLOR, false, 1.0)

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

	Inventory.add_item({"name": "Log", "description": "A piece of wood.", "quantity": 1})
	GameManager.item_picked_up.emit("Log", 1)
	queue_free()
