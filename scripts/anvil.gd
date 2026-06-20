extends Node2D

const INTERACTION_RANGE: float = 90.0
const HOVER_RADIUS: float = 22.0
const LABEL_FADE_SPEED: float = 2.5
const FORGE_TIME: float = 5.0
const HAMMER_USES: int = 25

const RECIPES: Array[Dictionary] = [
	{input="Heated Iron Ore",    count=2, output="Iron Plate"},
	{input="Heated Copper Ore",  count=2, output="Copper Plate"},
	{input="Heated Gold Ore",    count=2, output="Gold Plate"},
]

var _hovered: bool = false
var _label_alpha: float = 0.0
var _name_label: Label

var _processing: bool = false
var _process_timer: float = 0.0
var _queued_output: String = ""
var _ready_to_collect: bool = false
var _collect_item: String = ""

var _area: Area2D = null
var _marker_canvas: CanvasLayer
var _gui_canvas: CanvasLayer
var _gui_panel: Panel
var _inv_container: VBoxContainer
var _recipe_container: VBoxContainer
var _status_label: Label
var _gui_open: bool = false

func _ready() -> void:
	z_index = 10
	add_to_group("anvils")
	_build_visual()
	_setup_area()
	_build_label()
	_build_gui()
	_build_marker()

func _build_marker() -> void:
	_marker_canvas = CanvasLayer.new()
	_marker_canvas.layer = 9
	add_child(_marker_canvas)
	var marker: Control = load("res://scripts/vent_marker.gd").new()
	marker.set("vent", self)
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_canvas.add_child(marker)

func _build_visual() -> void:
	# Flat anvil body
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-22, -4), Vector2(22, -4),
		Vector2(22, 4),   Vector2(-22, 4),
	])
	base.color = Color(0.28, 0.28, 0.30, 1.0)
	add_child(base)
	# Anvil horn (left)
	var horn := Polygon2D.new()
	horn.polygon = PackedVector2Array([
		Vector2(-22, -4), Vector2(-36, 0),
		Vector2(-22, 4),
	])
	horn.color = Color(0.32, 0.32, 0.34, 1.0)
	add_child(horn)
	# Top plate
	var top := Polygon2D.new()
	top.polygon = PackedVector2Array([
		Vector2(-18, -10), Vector2(18, -10),
		Vector2(22, -4),   Vector2(-22, -4),
	])
	top.color = Color(0.38, 0.38, 0.40, 1.0)
	add_child(top)
	# Legs
	for sx in [-1, 1]:
		var leg := Polygon2D.new()
		leg.polygon = PackedVector2Array([
			Vector2(sx * 8, 4), Vector2(sx * 14, 4),
			Vector2(sx * 14, 12), Vector2(sx * 8, 12),
		])
		leg.color = Color(0.22, 0.22, 0.24, 1.0)
		add_child(leg)

func _build_label() -> void:
	_name_label = Label.new()
	_name_label.text = "Anvil"
	_name_label.position = Vector2(-16, -22)
	_name_label.add_theme_font_size_override("font_size", 7)
	_name_label.modulate.a = 0.0
	_name_label.z_index = 20
	add_child(_name_label)

func _setup_area() -> void:
	_area = Area2D.new()
	_area.collision_layer = 4
	_area.collision_mask = 0
	_area.input_pickable = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(76, 22)
	cs.shape = rect
	cs.position = Vector2(-7, 0)
	_area.add_child(cs)
	add_child(_area)
	_area.input_event.connect(_on_mouse_input)

func _build_gui() -> void:
	_gui_canvas = CanvasLayer.new()
	_gui_canvas.layer = 12
	_gui_canvas.visible = false
	add_child(_gui_canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gui_canvas.add_child(overlay)

	_gui_panel = Panel.new()
	_gui_panel.set_anchors_preset(Control.PRESET_CENTER)
	_gui_panel.position = Vector2(-220, -170)
	_gui_panel.size = Vector2(440, 340)
	_gui_canvas.add_child(_gui_panel)

	# ── Left: inventory ───────────────────────────────────────────────────────
	var inv_title := Label.new()
	inv_title.text = "— INVENTORY —"
	inv_title.position = Vector2(8, 6)
	inv_title.size = Vector2(200, 20)
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1.0))
	_gui_panel.add_child(inv_title)

	var sep_v := ColorRect.new()
	sep_v.color = Color(0.4, 0.4, 0.4, 0.5)
	sep_v.position = Vector2(216, 4)
	sep_v.size = Vector2(1, 330)
	_gui_panel.add_child(sep_v)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.position = Vector2(4, 28)
	inv_scroll.size = Vector2(210, 280)
	_gui_panel.add_child(inv_scroll)

	_inv_container = VBoxContainer.new()
	_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(_inv_container)

	# ── Right: recipes ────────────────────────────────────────────────────────
	var rec_title := Label.new()
	rec_title.text = "— ANVIL FORGE —"
	rec_title.position = Vector2(222, 6)
	rec_title.size = Vector2(210, 20)
	rec_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1.0))
	_gui_panel.add_child(rec_title)

	var hammer_lbl := Label.new()
	hammer_lbl.name = "HammerLabel"
	hammer_lbl.position = Vector2(222, 26)
	hammer_lbl.size = Vector2(210, 16)
	hammer_lbl.add_theme_font_size_override("font_size", 8)
	hammer_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	_gui_panel.add_child(hammer_lbl)

	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.position = Vector2(220, 46)
	recipe_scroll.size = Vector2(214, 200)
	_gui_panel.add_child(recipe_scroll)

	_recipe_container = VBoxContainer.new()
	_recipe_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_scroll.add_child(_recipe_container)

	_status_label = Label.new()
	_status_label.position = Vector2(222, 252)
	_status_label.size = Vector2(210, 40)
	_status_label.add_theme_font_size_override("font_size", 8)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_gui_panel.add_child(_status_label)

	var collect_btn := Button.new()
	collect_btn.name = "CollectBtn"
	collect_btn.text = "Collect"
	collect_btn.position = Vector2(222, 296)
	collect_btn.size = Vector2(100, 24)
	collect_btn.pressed.connect(_collect)
	_gui_panel.add_child(collect_btn)

	var hint := Label.new()
	hint.text = "[ ESC ] close"
	hint.position = Vector2(330, 302)
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	_gui_panel.add_child(hint)

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

	if _gui_open:
		_refresh_gui()
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) > INTERACTION_RANGE + 30.0:
			_close_gui()

func _draw() -> void:
	if _hovered:
		draw_rect(Rect2(-38, -12, 76, 18), Color(1, 0.85, 0, 1), false, 1.5)
	if _processing:
		var progress: float = 1.0 - clampf(_process_timer / FORGE_TIME, 0.0, 1.0)
		var bar_w := 44.0
		draw_rect(Rect2(-bar_w * 0.5, -24.0, bar_w, 4.0), Color(0.15, 0.15, 0.15, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, -24.0, bar_w * progress, 4.0), Color(0.5, 0.7, 1.0, 1.0))
	if _ready_to_collect:
		draw_rect(Rect2(-38, -12, 76, 18), Color(0.2, 0.9, 0.3, 1), false, 2.0)

func _refresh_gui() -> void:
	if _gui_panel == null:
		return
	# Inventory
	for c in _inv_container.get_children():
		c.queue_free()
	for item in Inventory.items:
		var lbl := Label.new()
		lbl.text = "  %s ×%d" % [item["name"], item.get("quantity", 1)]
		lbl.add_theme_font_size_override("font_size", 8)
		_inv_container.add_child(lbl)

	# Hammer status
	var hammer_uses := Inventory.get_item_count("Hammer")
	var hammer_lbl := _gui_panel.get_node("HammerLabel") as Label
	if hammer_uses == 0:
		hammer_lbl.text = "No Hammer — craft one at the Bench"
		hammer_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3, 1.0))
	else:
		hammer_lbl.text = "Hammer: %d uses remaining" % hammer_uses
		hammer_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))

	# Recipes
	for c in _recipe_container.get_children():
		c.queue_free()
	for recipe in RECIPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_recipe_container.add_child(row)

		var count_have := Inventory.get_item_count(recipe.input)
		var lbl := Label.new()
		lbl.text = "2× %s → %s" % [recipe.input, recipe.output]
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(lbl)

		var btn := Button.new()
		btn.text = "Forge"
		btn.add_theme_font_size_override("font_size", 7)
		btn.disabled = _processing or _ready_to_collect or hammer_uses == 0 or count_have < 2
		var captured_recipe: Dictionary = recipe
		btn.pressed.connect(func(): _start_forge(captured_recipe))
		row.add_child(btn)

	# Status
	if _ready_to_collect:
		_status_label.text = "Ready: %s" % _collect_item
		_status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3, 1.0))
	elif _processing:
		var secs: float = max(0.0, _process_timer)
		_status_label.text = "Forging… %ds" % int(secs)
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
	else:
		_status_label.text = ""

	_gui_panel.get_node("CollectBtn").visible = _ready_to_collect

func _start_forge(recipe: Dictionary) -> void:
	if _processing or _ready_to_collect:
		return
	if Inventory.get_item_count("Hammer") == 0:
		GameManager.feedback_requested.emit("Need a Hammer.")
		return
	if Inventory.get_item_count(recipe.input) < 2:
		GameManager.feedback_requested.emit("Need 2× %s." % recipe.input)
		return
	Inventory.remove_item(recipe.input, 2)
	# Consume one hammer use
	Inventory.remove_item("Hammer", 1)
	var uses_left := Inventory.get_item_count("Hammer")
	if uses_left == 0 and HAMMER_USES > 1:
		# Restore with one fewer use — using quantity to track durability
		pass  # hammer is fully consumed per 25 plates; here one hammer = 25 uses
	_queued_output = recipe.output
	_processing = true
	_process_timer = FORGE_TIME
	GameManager.feedback_requested.emit("Forging %s…" % recipe.output)
	queue_redraw()

func _finish() -> void:
	_processing = false
	_process_timer = 0.0
	_ready_to_collect = true
	_collect_item = _queued_output
	_queued_output = ""
	GameManager.feedback_requested.emit("Anvil done — collect your %s." % _collect_item)
	queue_redraw()

func _collect() -> void:
	if not _ready_to_collect:
		return
	Inventory.add_item({"name": _collect_item, "description": "Forged plate.", "quantity": 1})
	GameManager.item_picked_up.emit(_collect_item, 1)
	GameManager.feedback_requested.emit("Collected: %s." % _collect_item)
	_ready_to_collect = false
	_collect_item = ""
	queue_redraw()

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if _gui_open:
		return
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
	if _area != null:
		_area.input_pickable = false
	_refresh_gui()

func _close_gui() -> void:
	_gui_open = false
	_gui_canvas.visible = false
	GameManager.block_input = false
	if _area != null:
		_area.input_pickable = true

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
		var vp_size := get_viewport().get_visible_rect().size
		var panel_rect := Rect2(vp_size * 0.5 + Vector2(-220, -170), Vector2(440, 340))
		if not panel_rect.has_point((event as InputEventMouseButton).position):
			_close_gui()
