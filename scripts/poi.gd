extends Node2D

const HOVER_RADIUS: float = 32.0
const INTERACTION_RANGE: float = 180.0
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const OUTLINE_WIDTH: float = 1.0
const LABEL_FADE_SPEED: float = 2.5

const MINING_POIS: Array[String] = [
	"Iron Deposit", "Copper Vein", "Coal Seam", "Gold Seam", "Crystal Formation",
]
const EXAMINE_MSGS: Dictionary = {
	"Ancient Ruins":   "Strange markings cover the stone.",
	"Geothermal Vent": "Heat radiates from the fissure.",
}

var poi_name: String = ""
var _hovered: bool = false
var _area: Area2D
var _bounds: Rect2
var _label: Label
var _label_alpha: float = 0.0

func setup(p_name: String, bounds: Rect2, label: Label) -> void:
	poi_name = p_name
	_bounds = bounds
	_label = label

func _ready() -> void:
	z_index = 10
	_area = Area2D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	_area.input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _bounds.size + Vector2(8, 8)
	shape.shape = rect
	shape.position = _bounds.get_center()
	_area.add_child(shape)
	add_child(_area)
	_area.input_event.connect(_on_mouse_input)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()

	# Fade label in/out
	_label_alpha = clampf(
		_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta,
		0.0, 1.0
	)
	if _label != null:
		_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered:
		draw_rect(
			Rect2(_bounds.position - Vector2(2, 2), _bounds.size + Vector2(4, 4)),
			OUTLINE_COLOR, false, OUTLINE_WIDTH
		)

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

	if poi_name in MINING_POIS:
		if GameManager.hotbar[GameManager.hotbar_selected] != "Pickaxe":
			GameManager.feedback_requested.emit("Equip a Pickaxe to mine.")
			return
		var is_rare := poi_name == "Crystal Formation"
		var ore := _ore_drop(poi_name)
		var count := randi_range(1, 5) if is_rare else randi_range(5, 20)
		Inventory.add_item({
			"name": ore,
			"description": "Mined from a %s." % poi_name,
			"quantity": count,
		})
		GameManager.item_picked_up.emit(ore, count)
		queue_free()
	else:
		GameManager.feedback_requested.emit(EXAMINE_MSGS.get(poi_name, "Nothing more to see here."))

func _ore_drop(p_name: String) -> String:
	match p_name:
		"Iron Deposit":      return "Iron Ore"
		"Copper Vein":       return "Copper Ore"
		"Coal Seam":         return "Coal"
		"Gold Seam":         return "Gold Ore"
		"Crystal Formation": return "Crystal Shard"
		_:                   return "Rock"
