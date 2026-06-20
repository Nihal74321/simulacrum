extends Node2D

const INTERACTION_RANGE: float = 85.0
const VISIBLE_RANGE: float = 280.0
const PROCESSING_TIME: float = 300.0
const COAL_TIME: float = 90.0
const ORES_REQUIRED: int = 5
const HOVER_RADIUS: float = 22.0
const LABEL_FADE_SPEED: float = 2.5
const BAR_W: float = 44.0
const BAR_H: float = 4.0
const BAR_Y: float = -42.0

const ORE_TO_PLATE: Dictionary = {
	"Iron Ore":    "Iron Plate",
	"Copper Ore":  "Copper Plate",
	"Gold Ore":    "Gold Plate",
}
const IDLE_MSGS: Array[String] = [
	"That looks hot.",
	"That could melt iron…",
	"That burns.",
]

var _hovered: bool = false
var _label_alpha: float = 0.0
var _name_label: Label

var _processing: bool = false
var _process_timer: float = 0.0
var _current_recipe: String = ""   # "smelt" or "coal"
var _queued_ore: String = ""
var _queued_plate: String = ""
var _complete_flash: float = 0.0
var _complete_plate: String = ""

# Collect-from-machine
var _ready_to_collect: bool = false
var _collect_item: String = ""

var _gui_canvas: CanvasLayer
var _gui_panel: Panel
var _gui_rows: VBoxContainer
var _gui_open: bool = false
var _gui_dirty: bool = false

var _marker_canvas: CanvasLayer

func _pos_key() -> String:
	return "%d_%d" % [int(global_position.x), int(global_position.y)]

func _save_state() -> void:
	if not _processing and not _ready_to_collect:
		GameManager.vent_states.erase(_pos_key())
		return
	GameManager.vent_states[_pos_key()] = {
		processing = _processing,
		process_timer = _process_timer,
		total_time = _get_total_time() if _processing else 0.0,
		current_recipe = _current_recipe,
		queued_ore = _queued_ore,
		queued_plate = _queued_plate,
		ready_to_collect = _ready_to_collect,
		collect_item = _collect_item,
		complete_flash = _complete_flash,
		complete_plate = _complete_plate,
		saved_at = Time.get_unix_time_from_system(),
		gamespeed = GameManager.gamespeed_level,
	}

func _restore_state() -> void:
	var key := _pos_key()
	if not GameManager.vent_states.has(key):
		return
	var s: Dictionary = GameManager.vent_states[key]
	var elapsed := (Time.get_unix_time_from_system() - float(s.get("saved_at", 0.0))) * float(s.get("gamespeed", 1))
	_current_recipe = str(s.get("current_recipe", ""))
	_queued_ore = str(s.get("queued_ore", ""))
	_queued_plate = str(s.get("queued_plate", ""))
	_complete_flash = float(s.get("complete_flash", 0.0))
	_complete_plate = str(s.get("complete_plate", ""))
	if bool(s.get("ready_to_collect", false)):
		_ready_to_collect = true
		_collect_item = str(s.get("collect_item", ""))
	elif bool(s.get("processing", false)):
		_process_timer = float(s.get("process_timer", 0.0)) - elapsed
		if _process_timer <= 0.0:
			_finish()
		else:
			_processing = true
	queue_redraw()

func _ready() -> void:
	z_index = 10
	add_to_group("geothermal_vents")
	_build_visual()
	_setup_area()
	_build_label()
	_build_gui()
	_build_marker()
	_restore_state()

func _build_visual() -> void:
	var base_color := Color(0.9, 0.35, 0.1, 1.0)
	var rng2 := RandomNumberGenerator.new()
	rng2.randomize()
	for _i in 5:
		var poly := Polygon2D.new()
		var w: float = rng2.randf_range(4.0, 11.0)
		var h: float = rng2.randf_range(4.0, 13.0)
		var ox: float = rng2.randf_range(-14.0, 14.0)
		var oy: float = rng2.randf_range(-14.0, 4.0)
		poly.polygon = PackedVector2Array([
			Vector2(ox - w, oy - h), Vector2(ox + w, oy - h),
			Vector2(ox + w, oy + h), Vector2(ox - w, oy + h),
		])
		var v: float = rng2.randf_range(-0.08, 0.08)
		poly.color = base_color + Color(v, v * 0.3, 0.0, 0.0)
		add_child(poly)

func _build_label() -> void:
	_name_label = Label.new()
	_name_label.text = "Geothermal Vent"
	_name_label.position = Vector2(-40, -34)
	_name_label.add_theme_font_size_override("font_size", 7)
	_name_label.modulate.a = 0.0
	_name_label.z_index = 20
	add_child(_name_label)

var _area: Area2D

func _setup_area() -> void:
	_area = Area2D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	_area.input_pickable = true
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HOVER_RADIUS
	cs.shape = circle
	_area.add_child(cs)
	add_child(_area)
	_area.input_event.connect(_on_mouse_input)

func _build_gui() -> void:
	_gui_canvas = CanvasLayer.new()
	_gui_canvas.layer = 20
	_gui_canvas.visible = false
	add_child(_gui_canvas)

	_gui_panel = Panel.new()
	_gui_panel.size = Vector2(220, 210)
	_gui_canvas.add_child(_gui_panel)

	var title := Label.new()
	title.text = "Geothermal Vent"
	title.position = Vector2(8, 6)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1.0))
	_gui_panel.add_child(title)

	var recipe_hint := Label.new()
	recipe_hint.text = "5 ore → 1 plate  (5 min)"
	recipe_hint.position = Vector2(8, 22)
	recipe_hint.add_theme_font_size_override("font_size", 7)
	recipe_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
	_gui_panel.add_child(recipe_hint)

	var recipe_hint2 := Label.new()
	recipe_hint2.text = "1 Coal → 1 Heated Coal  (1.5 min)"
	recipe_hint2.position = Vector2(8, 32)
	recipe_hint2.add_theme_font_size_override("font_size", 7)
	recipe_hint2.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
	_gui_panel.add_child(recipe_hint2)

	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 0.5)
	sep.position = Vector2(4, 44)
	sep.size = Vector2(212, 1)
	_gui_panel.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 48)
	scroll.size = Vector2(212, 110)
	_gui_panel.add_child(scroll)

	_gui_rows = VBoxContainer.new()
	_gui_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gui_rows)

	var collect_btn := Button.new()
	collect_btn.name = "CollectBtn"
	collect_btn.text = "Collect"
	collect_btn.position = Vector2(8, 162)
	collect_btn.size = Vector2(100, 24)
	collect_btn.visible = false
	collect_btn.pressed.connect(_collect)
	_gui_panel.add_child(collect_btn)

	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.position = Vector2(8, 162)
	status_lbl.size = Vector2(210, 18)
	status_lbl.add_theme_font_size_override("font_size", 8)
	_gui_panel.add_child(status_lbl)

	var hint := Label.new()
	hint.text = "[ ESC ] to close"
	hint.position = Vector2(8, 186)
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	_gui_panel.add_child(hint)

func _build_marker() -> void:
	_marker_canvas = CanvasLayer.new()
	_marker_canvas.layer = 9
	add_child(_marker_canvas)

	var marker_ctrl: Control = load("res://scripts/vent_marker.gd").new()
	marker_ctrl.set("vent", self)
	marker_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_canvas.add_child(marker_ctrl)

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
			_finish()

	if _complete_flash > 0.0:
		_complete_flash -= delta
		if _complete_flash <= 0.0:
			_complete_plate = ""
			queue_redraw()

	if _gui_open:
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * global_position
		_gui_panel.position = screen_pos + Vector2(-110.0, -240.0)
		if _gui_dirty:
			_gui_dirty = false
			_refresh_gui_rows()
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) > INTERACTION_RANGE + 30.0:
			_close_gui()

func _get_total_time() -> float:
	return COAL_TIME if _current_recipe == "coal" else PROCESSING_TIME

func _draw() -> void:
	if _hovered:
		draw_arc(Vector2.ZERO, HOVER_RADIUS + 2.0, 0.0, TAU, 24, Color(1, 0.85, 0, 1), 1.5)
	if _processing:
		var progress: float = 1.0 - clampf(_process_timer / _get_total_time(), 0.0, 1.0)
		draw_rect(Rect2(-BAR_W * 0.5, BAR_Y, BAR_W, BAR_H), Color(0.15, 0.15, 0.15, 0.85))
		draw_rect(Rect2(-BAR_W * 0.5, BAR_Y, BAR_W * progress, BAR_H), Color(1.0, 0.55, 0.1, 1.0))
	if _ready_to_collect:
		draw_arc(Vector2.ZERO, HOVER_RADIUS + 2.0, 0.0, TAU, 24, Color(0.2, 0.9, 0.3, 1), 2.0)

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	# If GUI is open and click is inside the panel, let buttons handle it
	if _gui_open and Rect2(_gui_panel.position, _gui_panel.size).has_point(
			(event as InputEventMouseButton).position):
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
		return

	if _processing:
		_open_gui()
		return

	if _ready_to_collect:
		_open_gui()
		return

	var has_ore := false
	for ore: String in ORE_TO_PLATE.keys():
		if Inventory.get_item_count(ore) > 0:
			has_ore = true
			break
	var has_coal := Inventory.get_item_count("Coal") > 0
	if not has_ore and not has_coal:
		GameManager.feedback_requested.emit(IDLE_MSGS[randi() % IDLE_MSGS.size()])
		return

	_open_gui()

func _open_gui() -> void:
	_gui_open = true
	_gui_dirty = true
	_gui_canvas.visible = true
	if _area != null:
		_area.input_pickable = false

func _close_gui() -> void:
	_gui_open = false
	_gui_canvas.visible = false
	if _area != null:
		_area.input_pickable = true

func _refresh_gui_rows() -> void:
	for c in _gui_rows.get_children():
		c.queue_free()

	var collect_btn := _gui_panel.get_node("CollectBtn") as Button
	var status_lbl := _gui_panel.get_node("StatusLabel") as Label

	if _ready_to_collect:
		collect_btn.visible = true
		collect_btn.text = "Collect %s" % _collect_item
		status_lbl.visible = false
		var lbl := Label.new()
		lbl.text = "%s ready to collect!" % _collect_item
		lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))
		lbl.add_theme_font_size_override("font_size", 9)
		_gui_rows.add_child(lbl)
		return

	collect_btn.visible = false

	if _processing:
		var secs: float = max(0.0, _process_timer)
		status_lbl.visible = true
		status_lbl.text = ""
		var what := "Heated Coal" if _current_recipe == "coal" else _queued_plate
		var lbl := Label.new()
		lbl.text = "Making %s… %d:%02d" % [what, int(secs)/60, int(secs)%60]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 1.0))
		_gui_rows.add_child(lbl)
		return

	status_lbl.visible = false

	var found_any := false

	# Coal → Heated Coal
	var coal_count := Inventory.get_item_count("Coal")
	if coal_count > 0:
		found_any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_gui_rows.add_child(row)
		var lbl := Label.new()
		lbl.text = "Coal"
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Heat Coal"
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(_start_coal)
		row.add_child(btn)

	# Metal ore → plate
	for ore: String in ORE_TO_PLATE.keys():
		var count := Inventory.get_item_count(ore)
		if count == 0:
			continue
		found_any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_gui_rows.add_child(row)
		var lbl := Label.new()
		lbl.text = "%s" % ore
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if count >= ORES_REQUIRED:
			var btn := Button.new()
			btn.text = "Smelt 5"
			btn.add_theme_font_size_override("font_size", 8)
			var ore_key := ore
			btn.pressed.connect(func(): _start_smelting(ore_key))
			row.add_child(btn)
		else:
			var need_lbl := Label.new()
			need_lbl.text = "Need 5"
			need_lbl.add_theme_font_size_override("font_size", 8)
			need_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
			row.add_child(need_lbl)

	if not found_any:
		var none_lbl := Label.new()
		none_lbl.text = "No usable materials in inventory."
		none_lbl.add_theme_font_size_override("font_size", 8)
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		_gui_rows.add_child(none_lbl)

func _start_coal() -> void:
	Inventory.remove_item("Coal", 1)
	_current_recipe = "coal"
	_queued_ore = "Coal"
	_queued_plate = "Heated Coal"
	_processing = true
	_process_timer = COAL_TIME
	_ready_to_collect = false
	_collect_item = ""
	_close_gui()
	_save_state()
	GameManager.feedback_requested.emit("Heating Coal…")
	GameManager.secondary_task_changed.emit()
	queue_redraw()

func _start_smelting(ore: String) -> void:
	Inventory.remove_item(ore, ORES_REQUIRED)
	_current_recipe = "smelt"
	_queued_ore = ore
	_queued_plate = ORE_TO_PLATE.get(ore, "")
	_processing = true
	_process_timer = PROCESSING_TIME
	_ready_to_collect = false
	_collect_item = ""
	_complete_flash = 0.0
	_complete_plate = ""
	_close_gui()
	_save_state()
	GameManager.feedback_requested.emit("Smelting %s…" % ore)
	GameManager.secondary_task_changed.emit()
	queue_redraw()

func _finish() -> void:
	_processing = false
	_process_timer = 0.0
	if _current_recipe == "coal":
		_collect_item = "Heated Coal"
		_complete_plate = ""
		_complete_flash = 0.0
	else:
		var plate: String = ORE_TO_PLATE.get(_queued_ore, "")
		_collect_item = plate
		_complete_plate = plate
		_complete_flash = 12.0
	_ready_to_collect = true
	_queued_ore = ""
	_queued_plate = ""
	_current_recipe = ""
	_save_state()
	GameManager.feedback_requested.emit("%s ready — collect from vent." % _collect_item)
	GameManager.secondary_task_changed.emit()
	_gui_dirty = true
	queue_redraw()

func _collect() -> void:
	if not _ready_to_collect:
		return
	Inventory.add_item({"name": _collect_item, "description": "From geothermal vent.", "quantity": 1})
	GameManager.item_picked_up.emit(_collect_item, 1)
	GameManager.feedback_requested.emit("Collected: %s." % _collect_item)
	_ready_to_collect = false
	_collect_item = ""
	_complete_plate = ""
	_complete_flash = 0.0
	_save_state()
	_gui_dirty = true
	queue_redraw()

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
