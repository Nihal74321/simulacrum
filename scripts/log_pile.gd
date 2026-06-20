extends Node2D

const HOVER_RADIUS: float = 14.0
const INTERACTION_RANGE: float = 72.0
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

var _hovered: bool = false
var _label: Label
var _label_alpha: float = 0.0

func _ready() -> void:
	z_index = 5
	_build_visual()

	_label = Label.new()
	_label.text = "Log Pile"
	_label.position = Vector2(-16, -24)
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
	rect.size = Vector2(28, 14)
	cs.shape = rect
	cs.position = Vector2(0, -4)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _build_visual() -> void:
	var log_color := Color(0.44, 0.27, 0.11, 1)
	var bark_color := Color(0.34, 0.20, 0.09, 1)
	# Bottom row: 3 logs
	for i in 3:
		var ox: float = (i - 1) * 10.0
		_add_log(Vector2(ox, 0.0), log_color, bark_color, 9.0, 3.0)
	# Top row: 2 logs (offset)
	for i in 2:
		var ox: float = (i - 0.5) * 10.0
		_add_log(Vector2(ox, -5.0), log_color.lightened(0.05), bark_color, 9.0, 3.0)

func _add_log(offset: Vector2, fill: Color, end_color: Color, hw: float, hh: float) -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(offset.x - hw, offset.y - hh),
		Vector2(offset.x + hw, offset.y - hh),
		Vector2(offset.x + hw, offset.y + hh),
		Vector2(offset.x - hw, offset.y + hh),
	])
	body.color = fill
	add_child(body)
	# End cap (darker)
	var cap := Polygon2D.new()
	cap.polygon = PackedVector2Array([
		Vector2(offset.x + hw - 2, offset.y - hh),
		Vector2(offset.x + hw, offset.y - hh),
		Vector2(offset.x + hw, offset.y + hh),
		Vector2(offset.x + hw - 2, offset.y + hh),
	])
	cap.color = end_color
	add_child(cap)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha
	# Fade when player walks in front (tree/shrub style)
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		var dist := global_position.distance_to(player.global_position)
		var in_front := player.global_position.y > global_position.y - 6.0
		modulate.a = 0.35 if (dist < 40.0 and in_front) else 1.0

func _draw() -> void:
	if _hovered:
		draw_rect(Rect2(-15, -12, 30, 16), OUTLINE_COLOR, false, 1.0)

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

	var logs := randi_range(2, 5)
	Inventory.add_item({"name": "Log", "description": "From a log pile.", "quantity": logs})
	GameManager.item_picked_up.emit("Log", logs)
	queue_free()
