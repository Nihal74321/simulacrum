extends Node2D

const INTERACTION_RANGE: float = 90.0
const HOVER_RADIUS: float = 26.0
const LABEL_FADE_SPEED: float = 2.5
const HEAT_TIME: float = 40.0
const STEEL_TIME: float = 300.0
const FUEL_PER_COAL: int = 100
# Batch sizes the forge accepts and the time each batch takes
const BATCH_TIME: Dictionary = {1: 40.0, 10: 200.0, 100: 1000.0}
const BATCH_QTYS: Array[int] = [1, 10, 100]

const ORE_TO_HEATED: Dictionary = {
	"Iron Ore":    "Heated Iron Ore",
	"Copper Ore":  "Heated Copper Ore",
	"Gold Ore":    "Heated Gold Ore",
}
const IDLE_MSGS: Array[String] = [
	"Roaring hot.", "The forge awaits.", "Ready for ore.",
]

var _hovered: bool = false
var _label_alpha: float = 0.0
var _name_label: Label

var _fuel_charges: int = 0
var _processing: bool = false
var _process_timer: float = 0.0
var _queued_recipe: String = ""   # ore name, or "steel"
var _queued_output: String = ""
var _queued_qty: int = 1
var _ready_to_collect: bool = false
var _collect_item: String = ""
var _collect_qty: int = 1

# GUI
var _gui_canvas: CanvasLayer
var _gui_panel: Panel
var _gui_open: bool = false

# Marker
var _marker_canvas: CanvasLayer

func _pos_key() -> String:
	return "%d_%d" % [int(global_position.x), int(global_position.y)]

func _save_state() -> void:
	if not _processing and not _ready_to_collect:
		GameManager.forge_states.erase(_pos_key())
		return
	GameManager.forge_states[_pos_key()] = {
		processing = _processing,
		process_timer = _process_timer,
		total_time = _get_recipe_time() if _processing else 0.0,
		queued_recipe = _queued_recipe,
		queued_output = _queued_output,
		queued_qty = _queued_qty,
		ready_to_collect = _ready_to_collect,
		collect_item = _collect_item,
		collect_qty = _collect_qty,
		fuel_charges = _fuel_charges,
		saved_at = Time.get_unix_time_from_system(),
		gamespeed = GameManager.gamespeed_level,
	}

func _restore_state() -> void:
	var key := _pos_key()
	if not GameManager.forge_states.has(key):
		return
	var s: Dictionary = GameManager.forge_states[key]
	var elapsed := (Time.get_unix_time_from_system() - float(s.get("saved_at", 0.0))) * float(s.get("gamespeed", 1))
	_fuel_charges = int(s.get("fuel_charges", 0))
	_queued_recipe = str(s.get("queued_recipe", ""))
	_queued_output = str(s.get("queued_output", ""))
	_queued_qty = int(s.get("queued_qty", 1))
	_collect_qty = int(s.get("collect_qty", 1))
	if bool(s.get("ready_to_collect", false)):
		_ready_to_collect = true
		_collect_item = str(s.get("collect_item", ""))
	elif bool(s.get("processing", false)):
		_process_timer = float(s.get("process_timer", 0.0)) - elapsed
		if _process_timer <= 0.0:
			_finish_recipe()
		else:
			_processing = true
	queue_redraw()

func _ready() -> void:
	z_index = 10
	add_to_group("forges")
	_build_visual()
	_setup_area()
	_build_label()
	_build_gui()
	_build_marker()
	_restore_state()

func _build_visual() -> void:
	var rng2 := RandomNumberGenerator.new()
	rng2.randomize()
	# Main forge body
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-20, -30), Vector2(20, -30),
		Vector2(22, 10),   Vector2(-22, 10),
	])
	body.color = Color(0.35, 0.20, 0.10, 1.0)
	add_child(body)
	# Firebox opening
	var fire := Polygon2D.new()
	fire.polygon = PackedVector2Array([
		Vector2(-10, -20), Vector2(10, -20),
		Vector2(10, -4),   Vector2(-10, -4),
	])
	fire.color = Color(0.9, 0.45, 0.05, 1.0)
	add_child(fire)
	# Chimney
	var chimney := Polygon2D.new()
	chimney.polygon = PackedVector2Array([
		Vector2(-4, -44), Vector2(4, -44),
		Vector2(5, -30),  Vector2(-5, -30),
	])
	chimney.color = Color(0.20, 0.15, 0.10, 1.0)
	add_child(chimney)

func _build_label() -> void:
	_name_label = Label.new()
	_name_label.text = "Forge"
	_name_label.position = Vector2(-20, -52)
	_name_label.add_theme_font_size_override("font_size", 7)
	_name_label.modulate.a = 0.0
	_name_label.z_index = 20
	add_child(_name_label)

func _setup_area() -> void:
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(46, 42)
	cs.shape = rect
	cs.position = Vector2(0, -10)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _build_gui() -> void:
	_gui_canvas = CanvasLayer.new()
	_gui_canvas.layer = 8
	_gui_canvas.visible = false
	add_child(_gui_canvas)

	_gui_panel = Panel.new()
	_gui_panel.size = Vector2(238, 270)
	_gui_canvas.add_child(_gui_panel)

	var title := Label.new()
	title.text = "Forge"
	title.position = Vector2(8, 6)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.1, 1.0))
	_gui_panel.add_child(title)

	var fuel_lbl := Label.new()
	fuel_lbl.name = "FuelLabel"
	fuel_lbl.position = Vector2(8, 24)
	fuel_lbl.add_theme_font_size_override("font_size", 8)
	fuel_lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1.0))
	_gui_panel.add_child(fuel_lbl)

	var add_fuel_btn := Button.new()
	add_fuel_btn.name = "FuelBtn"
	add_fuel_btn.text = "Add Heated Coal (+100)"
	add_fuel_btn.position = Vector2(8, 40)
	add_fuel_btn.size = Vector2(200, 22)
	add_fuel_btn.add_theme_font_size_override("font_size", 8)
	add_fuel_btn.pressed.connect(_add_fuel)
	_gui_panel.add_child(add_fuel_btn)

	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 0.5)
	sep.position = Vector2(4, 66)
	sep.size = Vector2(212, 1)
	_gui_panel.add_child(sep)

	var recipes_lbl := Label.new()
	recipes_lbl.text = "Heat ore — ×1 (40s) / ×10 (200s) / ×100 (1000s):"
	recipes_lbl.position = Vector2(8, 70)
	recipes_lbl.add_theme_font_size_override("font_size", 7)
	_gui_panel.add_child(recipes_lbl)

	# Per-ore batch buttons (×1 / ×10 / ×100)
	var recipe_names: Array[String] = ["Iron Ore", "Copper Ore", "Gold Ore"]
	for i in recipe_names.size():
		var ore_name: String = recipe_names[i]
		var row_y: float = 86.0 + i * 26.0
		var name_lbl := Label.new()
		name_lbl.text = ore_name.replace(" Ore", "")
		name_lbl.position = Vector2(8, row_y + 3)
		name_lbl.add_theme_font_size_override("font_size", 8)
		_gui_panel.add_child(name_lbl)
		var xs := [Vector2(58, 46), Vector2(106, 50), Vector2(158, 56)]
		for q in BATCH_QTYS.size():
			var qty: int = BATCH_QTYS[q]
			var btn := Button.new()
			btn.name = "Btn_%s_%d" % [ore_name.replace(" ", ""), qty]
			btn.text = "×%d" % qty
			btn.position = Vector2(xs[q].x, row_y)
			btn.size = Vector2(xs[q].y - 4.0, 22)
			btn.add_theme_font_size_override("font_size", 8)
			var cap_ore := ore_name
			var cap_qty := qty
			btn.pressed.connect(func(): _start_recipe(cap_ore, cap_qty))
			_gui_panel.add_child(btn)

	var steel_btn := Button.new()
	steel_btn.name = "SteelBtn"
	steel_btn.text = "Steel: 1 Coal + 9 Iron Ore (5 min)"
	steel_btn.position = Vector2(8, 168)
	steel_btn.size = Vector2(206, 22)
	steel_btn.add_theme_font_size_override("font_size", 7)
	steel_btn.pressed.connect(func(): _start_steel())
	_gui_panel.add_child(steel_btn)

	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.position = Vector2(8, 196)
	status_lbl.add_theme_font_size_override("font_size", 8)
	_gui_panel.add_child(status_lbl)

	var collect_btn := Button.new()
	collect_btn.name = "CollectBtn"
	collect_btn.text = "Collect"
	collect_btn.position = Vector2(8, 218)
	collect_btn.size = Vector2(100, 22)
	collect_btn.add_theme_font_size_override("font_size", 8)
	collect_btn.pressed.connect(_collect)
	_gui_panel.add_child(collect_btn)

	var hint_lbl := Label.new()
	hint_lbl.text = "[ ESC ] close"
	hint_lbl.position = Vector2(120, 222)
	hint_lbl.add_theme_font_size_override("font_size", 7)
	hint_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	_gui_panel.add_child(hint_lbl)

func _build_marker() -> void:
	_marker_canvas = CanvasLayer.new()
	_marker_canvas.layer = 9
	add_child(_marker_canvas)
	var marker: Control = load("res://scripts/vent_marker.gd").new()
	marker.set("vent", self)
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_canvas.add_child(marker)

var _processing_accessible: bool = false

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_name_label.modulate.a = _label_alpha

	if _processing:
		_process_timer -= delta
		queue_redraw()
		if _process_timer <= 0.0:
			_finish_recipe()
	# Track so vent_marker can read _processing
	_processing_accessible = _processing

	if _gui_open:
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * global_position
		_gui_panel.position = screen_pos + Vector2(-110.0, -280.0)
		_refresh_gui()
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) > INTERACTION_RANGE + 30.0:
			_close_gui()

func _draw() -> void:
	if _hovered:
		draw_arc(Vector2(0, -10), 28.0, 0.0, TAU, 24, Color(1, 0.85, 0, 1), 1.5)
	if _processing:
		var progress: float = 1.0 - clampf(_process_timer / (_get_recipe_time()), 0.0, 1.0)
		var bar_w := 44.0
		var bar_h := 4.0
		draw_rect(Rect2(-bar_w * 0.5, -48.0, bar_w, bar_h), Color(0.15, 0.15, 0.15, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, -48.0, bar_w * progress, bar_h), Color(1.0, 0.55, 0.1, 1.0))
	if _ready_to_collect:
		draw_arc(Vector2(0, -10), 28.0, 0.0, TAU, 24, Color(0.2, 0.9, 0.3, 1), 2.0)

func _get_recipe_time() -> float:
	if _queued_recipe == "steel":
		return STEEL_TIME
	return BATCH_TIME.get(_queued_qty, HEAT_TIME)

func _refresh_gui() -> void:
	if _gui_panel == null:
		return
	var fuel_lbl := _gui_panel.get_node("FuelLabel") as Label
	fuel_lbl.text = "Fuel: %d charges" % _fuel_charges
	_gui_panel.get_node("FuelBtn").disabled = Inventory.get_item_count("Heated Coal") == 0
	var status_lbl := _gui_panel.get_node("StatusLabel") as Label
	if _ready_to_collect:
		status_lbl.text = "Ready: %s" % _collect_item
		status_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))
	elif _processing:
		var secs: float = max(0.0, _process_timer)
		status_lbl.text = "Forging... %d:%02d" % [int(secs)/60, int(secs)%60]
		status_lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
	else:
		status_lbl.text = ""
	_gui_panel.get_node("CollectBtn").visible = _ready_to_collect
	var busy := _processing or _ready_to_collect
	for ore_name in ["Iron Ore", "Copper Ore", "Gold Ore"]:
		var have := Inventory.get_item_count(ore_name)
		for qty in BATCH_QTYS:
			var btn_name: String = "Btn_%s_%d" % [ore_name.replace(" ", ""), qty]
			var btn := _gui_panel.get_node_or_null(btn_name) as Button
			if btn != null:
				btn.disabled = busy or _fuel_charges < qty or have < qty
	_gui_panel.get_node("SteelBtn").disabled = busy or _fuel_charges == 0 \
		or Inventory.get_item_count("Coal") == 0 or Inventory.get_item_count("Iron Ore") < 9

func _add_fuel() -> void:
	if Inventory.get_item_count("Heated Coal") == 0:
		return
	Inventory.remove_item("Heated Coal", 1)
	_fuel_charges += FUEL_PER_COAL
	GameManager.feedback_requested.emit("Forge fueled: %d charges." % _fuel_charges)

func _start_recipe(ore_name: String, qty: int = 1) -> void:
	if _processing or _ready_to_collect:
		return
	if _fuel_charges < qty:
		GameManager.feedback_requested.emit("Forge needs %d Heated Coal charges." % qty)
		return
	if Inventory.get_item_count(ore_name) < qty:
		GameManager.feedback_requested.emit("Need %d %s." % [qty, ore_name])
		return
	Inventory.remove_item(ore_name, qty)
	_fuel_charges = max(0, _fuel_charges - qty)
	_queued_recipe = ore_name
	_queued_output = ORE_TO_HEATED.get(ore_name, "")
	_queued_qty = qty
	_processing = true
	_process_timer = BATCH_TIME.get(qty, HEAT_TIME)
	_save_state()
	GameManager.feedback_requested.emit("Heating %d %s…" % [qty, ore_name])
	GameManager.secondary_task_changed.emit()
	queue_redraw()

func _start_steel() -> void:
	if _processing or _ready_to_collect:
		return
	if _fuel_charges == 0:
		GameManager.feedback_requested.emit("Forge needs Heated Coal fuel.")
		return
	if Inventory.get_item_count("Coal") < 1 or Inventory.get_item_count("Iron Ore") < 9:
		GameManager.feedback_requested.emit("Need 1 Coal and 9 Iron Ore.")
		return
	Inventory.remove_item("Coal", 1)
	Inventory.remove_item("Iron Ore", 9)
	_fuel_charges = max(0, _fuel_charges - 1)
	_queued_recipe = "steel"
	_queued_output = "Steel"
	_queued_qty = 1
	_processing = true
	_process_timer = STEEL_TIME
	_save_state()
	GameManager.feedback_requested.emit("Smelting steel…")
	GameManager.secondary_task_changed.emit()
	queue_redraw()

func _finish_recipe() -> void:
	_processing = false
	_process_timer = 0.0
	_ready_to_collect = true
	_collect_item = _queued_output
	_collect_qty = _queued_qty
	_queued_recipe = ""
	_queued_output = ""
	_save_state()
	GameManager.feedback_requested.emit("Forge done — collect your %s." % _collect_item)
	GameManager.secondary_task_changed.emit()
	queue_redraw()

func _collect() -> void:
	if not _ready_to_collect:
		return
	Inventory.add_item({"name": _collect_item, "description": "Forged item.", "quantity": _collect_qty})
	GameManager.item_picked_up.emit(_collect_item, _collect_qty)
	GameManager.feedback_requested.emit("Collected: %d %s." % [_collect_qty, _collect_item])
	_ready_to_collect = false
	_collect_item = ""
	_collect_qty = 1
	_save_state()
	queue_redraw()

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	if _v is Viewport:
		(_v as Viewport).set_input_as_handled()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	if global_position.distance_to(player.global_position) > INTERACTION_RANGE:
		GameManager.feedback_requested.emit("Too far away.")
		return
	if _gui_open:
		_close_gui()
	else:
		_open_gui()

func _open_gui() -> void:
	_gui_open = true
	_gui_canvas.visible = true
	GameManager.block_input = true
	_refresh_gui()

func _close_gui() -> void:
	_gui_open = false
	_gui_canvas.visible = false
	GameManager.block_input = false

func _input(event: InputEvent) -> void:
	if not _gui_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_gui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		var click_pos: Vector2 = (event as InputEventMouseButton).position
		if not Rect2(_gui_panel.position, _gui_panel.size).has_point(click_pos):
			_close_gui()
