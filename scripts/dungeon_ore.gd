extends Node2D

const HOVER_RADIUS: float = 14.0
const INTERACTION_RANGE: float = 80.0
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

var ore_name: String = ""
var ore_color: Color = Color.WHITE
var _hovered: bool = false
var _label: Label
var _label_alpha: float = 0.0

func _ready() -> void:
	z_index = 10
	_build_visual()

	_label = Label.new()
	_label.text = ore_name
	_label.position = Vector2(-28, -26)
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
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _build_visual() -> void:
	var rng2 := RandomNumberGenerator.new()
	rng2.randomize()
	for _j in rng2.randi_range(2, 4):
		var block := Polygon2D.new()
		var w: float = rng2.randf_range(3.0, 8.0)
		var h: float = rng2.randf_range(3.0, 10.0)
		var ox: float = rng2.randf_range(-8.0, 8.0)
		var oy: float = rng2.randf_range(-8.0, 8.0)
		block.polygon = PackedVector2Array([
			Vector2(ox - w, oy - h), Vector2(ox + w, oy - h),
			Vector2(ox + w, oy + h), Vector2(ox - w, oy + h),
		])
		var v: float = rng2.randf_range(-0.1, 0.1)
		block.color = ore_color + Color(v, v * 0.3, 0.0, 0.0)
		add_child(block)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered:
		draw_arc(Vector2.ZERO, HOVER_RADIUS + 3.0, 0, TAU, 20, OUTLINE_COLOR, 1.5)

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
	if GameManager.hotbar[GameManager.hotbar_selected] != "Pickaxe":
		GameManager.feedback_requested.emit("Equip a Pickaxe to mine.")
		return
	var result := _ore_drop(ore_name)
	var is_rare := ore_name == "Crystal Formation"
	var count := randi_range(1, 5) if is_rare else randi_range(5, 20)
	Inventory.add_item({"name": result, "description": "", "quantity": count})
	GameManager.item_picked_up.emit(result, count)
	queue_free()

func _ore_drop(p_name: String) -> String:
	match p_name:
		"Iron Deposit":      return "Iron Ore"
		"Copper Vein":       return "Copper Ore"
		"Coal Seam":         return "Coal"
		"Gold Seam":         return "Gold Ore"
		"Crystal Formation": return "Crystal Shard"
		_:                   return "Rock"
