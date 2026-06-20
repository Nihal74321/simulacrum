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
	_label.text = "Rock Pile"
	_label.position = Vector2(-16, -22)
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
	rect.size = Vector2(24, 14)
	cs.shape = rect
	cs.position = Vector2(0, -4)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _build_visual() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rock_colors: Array[Color] = [
		Color(0.52, 0.52, 0.54, 1),
		Color(0.45, 0.44, 0.46, 1),
		Color(0.60, 0.59, 0.60, 1),
	]
	var offsets: Array[Vector2] = [
		Vector2(-7, -2), Vector2(0, -5), Vector2(7, -2),
		Vector2(-4, 1),  Vector2(5, 0),
	]
	for i in offsets.size():
		var rock := Polygon2D.new()
		var w: float = rng.randf_range(3.5, 5.5)
		var h: float = rng.randf_range(2.5, 4.5)
		var ox := offsets[i].x + rng.randf_range(-1.5, 1.5)
		var oy := offsets[i].y + rng.randf_range(-1.0, 1.0)
		rock.polygon = PackedVector2Array([
			Vector2(ox - w, oy),     Vector2(ox - w * 0.4, oy - h),
			Vector2(ox + w * 0.4, oy - h), Vector2(ox + w, oy),
			Vector2(ox + w * 0.5, oy + h * 0.5), Vector2(ox - w * 0.5, oy + h * 0.5),
		])
		rock.color = rock_colors[i % rock_colors.size()]
		add_child(rock)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered:
		draw_rect(Rect2(-13, -10, 26, 14), OUTLINE_COLOR, false, 1.0)

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

	var rocks := randi_range(1, 5)
	Inventory.add_item({"name": "Rock", "description": "A small rock.", "quantity": rocks})
	GameManager.item_picked_up.emit("Rock", rocks)
	queue_free()
