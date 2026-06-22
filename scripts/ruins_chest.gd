extends Node2D

const HOVER_RADIUS: float = 22.0
const INTERACTION_RANGE: float = 80.0
const OUTLINE_RECT: Rect2 = Rect2(-10, -16, 20, 16)
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

const T1_ORES: Array = ["Iron Ore", "Copper Ore", "Gold Ore", "Aluminium Ore", "Tin Ore", "Lead Ore", "Manganese Ore"]
const T2_ORES: Array = ["Neodymium Ore", "Cerium Ore", "Lanthanum Ore", "Yttrium Ore", "Dysprosium Ore"]
const WEAPON_DROPS: Array = ["Pickaxe", "Axe", "Sickle", "Broadaxe"]

var _opened: bool = false
var _hovered: bool = false
var _label_alpha: float = 0.0
var _label: Label

func _ready() -> void:
	z_index = 10
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-9, -14), Vector2(9, -14),
		Vector2(9, 0),    Vector2(-9, 0),
	])
	body.color = Color(0.40, 0.30, 0.18, 1)  # older/darker than regular chests
	add_child(body)

	var lid := Polygon2D.new()
	lid.polygon = PackedVector2Array([
		Vector2(-9, -14), Vector2(9, -14),
		Vector2(9, -9),   Vector2(-9, -9),
	])
	lid.color = Color(0.50, 0.38, 0.22, 1)
	add_child(lid)

	_label = Label.new()
	_label.text = "Old Chest"
	_label.position = Vector2(-20, -26)
	_label.add_theme_font_size_override("font_size", 7)
	_label.modulate.a = 0.0
	add_child(_label)

	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 18)
	cs.shape = rect
	cs.position = Vector2(0, -7)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(
		_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta,
		0.0, 1.0
	)
	_label.modulate.a = _label_alpha

func _draw() -> void:
	if _hovered and not _opened:
		draw_rect(OUTLINE_RECT, OUTLINE_COLOR, false, 1.0)

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	if _v is Viewport:
		(_v as Viewport).set_input_as_handled()
	if _opened:
		GameManager.feedback_requested.emit("Already looted.")
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to((player as Node2D).global_position) > INTERACTION_RANGE:
		GameManager.feedback_requested.emit("Too far away.")
		return
	if GameManager.hotbar[GameManager.hotbar_selected] != "Sickle":
		var msgs := ["I can't do that.", "Not now.", "I need a tool."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])
		return
	_open()
	queue_free()

func _open() -> void:
	var roll := randi_range(0, 99)
	if roll < 1:
		# Legendary: random weapon
		var weapon: String = WEAPON_DROPS[randi() % WEAPON_DROPS.size()]
		Inventory.add_item({"name": weapon, "description": "Found in ruins.", "quantity": 1})
		GameManager.item_picked_up.emit(weapon, 1)
	elif roll < 1 + 5:
		# Rare: 2-5 T2 ore
		var ore: String = T2_ORES[randi() % T2_ORES.size()]
		var qty := randi_range(2, 5)
		Inventory.add_item({"name": ore, "description": "Rare earth ore.", "quantity": qty})
		GameManager.item_picked_up.emit(ore, qty)
	elif roll < 1 + 5 + 20:
		# Uncommon: 1-5 iron plate
		var qty := randi_range(1, 5)
		Inventory.add_item({"name": "Iron Plate", "description": "Smelted iron.", "quantity": qty})
		GameManager.item_picked_up.emit("Iron Plate", qty)
	else:
		# Common: 5-15 T1 ore
		var ore: String = T1_ORES[randi() % T1_ORES.size()]
		var qty := randi_range(5, 15)
		Inventory.add_item({"name": ore, "description": "Common ore.", "quantity": qty})
		GameManager.item_picked_up.emit(ore, qty)
