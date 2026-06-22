extends Node2D

const HOVER_RADIUS: float = 18.0
const INTERACTION_RANGE: float = 80.0
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

# Set before add_child. One of: "Chalice", "Coin Pile", "Barrel"
var kind: String = "Barrel"

var _hovered: bool = false
var _label: Label
var _label_alpha: float = 0.0
var _broken: bool = false

func _ready() -> void:
	z_index = 7
	_build_visual()

	_label = Label.new()
	_label.text = kind
	_label.position = Vector2(-16, -30)
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
	cs.position = Vector2(0, -8)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)
	add_to_group("breakables")

func _build_visual() -> void:
	match kind:
		"Chalice":
			var cup := Polygon2D.new()
			cup.polygon = PackedVector2Array([
				Vector2(-6, -16), Vector2(6, -16), Vector2(4, -8), Vector2(-4, -8),
			])
			cup.color = Color(0.85, 0.72, 0.25, 1)
			add_child(cup)
			var stem := Polygon2D.new()
			stem.polygon = PackedVector2Array([
				Vector2(-1.5, -8), Vector2(1.5, -8), Vector2(1.5, -2), Vector2(-1.5, -2),
			])
			stem.color = Color(0.78, 0.65, 0.2, 1)
			add_child(stem)
			var base := Polygon2D.new()
			base.polygon = PackedVector2Array([
				Vector2(-5, -2), Vector2(5, -2), Vector2(6, 1), Vector2(-6, 1),
			])
			base.color = Color(0.7, 0.58, 0.18, 1)
			add_child(base)
		"Coin Pile":
			for i in 7:
				var coin := Polygon2D.new()
				var r := 2.5
				var pts := PackedVector2Array()
				for s in 8:
					var a := TAU * float(s) / 8.0
					pts.append(Vector2(cos(a) * r, sin(a) * r * 0.6))
				coin.polygon = pts
				coin.position = Vector2(randf_range(-7, 7), randf_range(-4, 0))
				coin.color = Color(0.9, 0.78, 0.25, 1)
				add_child(coin)
		_:  # Barrel
			var body := Polygon2D.new()
			body.polygon = PackedVector2Array([
				Vector2(-7, -16), Vector2(7, -16), Vector2(8, -3), Vector2(-8, -3),
			])
			body.color = Color(0.45, 0.30, 0.16, 1)
			add_child(body)
			var band := Polygon2D.new()
			band.polygon = PackedVector2Array([
				Vector2(-8, -11), Vector2(8, -11), Vector2(8, -9), Vector2(-8, -9),
			])
			band.color = Color(0.30, 0.20, 0.10, 1)
			add_child(band)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered and not _broken:
		draw_arc(Vector2(0, -8), HOVER_RADIUS + 2.0, 0, TAU, 20, OUTLINE_COLOR, 1.0)

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if _broken:
		return
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
	_broken = true
	var kf := randi_range(10, 40)
	Inventory.add_item({"name": "Knowledge Fragment", "description": "Crystallised memory.", "quantity": kf})
	GameManager.item_picked_up.emit("Knowledge Fragment", kf)
	# Barrels: uncommon chance to drop String (2-4)
	if kind == "Barrel" and randi() % 3 == 0:
		var qty := randi_range(2, 4)
		Inventory.add_item({"name": "String", "description": "Fibrous cord.", "quantity": qty})
		GameManager.item_picked_up.emit("String", qty)
	queue_free()
