extends CanvasLayer

const SPRINT_MAX: float = 3.0
const SPRINT_FADE_DELAY: float = 0.8
const SMALL_MAP_W: float = 200.0
const SMALL_MAP_H: float = 137.5
const DUNGEON_TIME: float = 180.0

var _hud_bg: ColorRect
var godmode_label: Label
var stats_label: Label
var feedback_label: Label
var _warning_label: Label
var _warning_timer: float = 0.0
var sprint_bar: ProgressBar
var cheat_input: LineEdit
var minimap: Control
var _pause_overlay: ColorRect
var _pause_label: Label
var _death_overlay: ColorRect
var _death_label: Label
var _death_timer: float = 0.0

# Hotbar (5 generic slots)
var _hotbar_bg: ColorRect
var _hotbar_slots: Array = []  # [{bg, border, label, num_lbl}]
const HOTBAR_SIZE: int = 5

# Item tracker
var _tracker_label: Label
var _tracker_bg: ColorRect
var _tracker: Dictionary = {}  # item_name -> {count, timer}

# Task section
var _task_bg: ColorRect
var _task_label: Label

var feedback_timer: float = 0.0
var sprint_bar_fade_timer: float = 0.0
var _current_hp: int = 100
var _max_hp: int = 100
var _help_on: bool = false
var _help_label: Label
var _help_bg: ColorRect
var _task_updated_label: Label
var _task_updated_timer: float = 0.0
var _task_prev_index: int = 0
var _dungeon_timer: float = -1.0
var _dungeon_timer_label: Label
var _prev_dungeon_active: bool = false

var _hint_canvas: CanvasLayer = null
var _hint_page: int = 0
var _task_overview_canvas: CanvasLayer = null
var _task_overview_open: bool = false
var _task_overview_dirty: bool = false
const _ALL_ITEMS: Array[String] = [
	"Pickaxe", "Hammer",
	"Log", "Rock", "Coal", "Heated Coal",
	"Iron Ore", "Copper Ore", "Gold Ore", "Crystal Shard",
	"Heated Iron Ore", "Heated Copper Ore", "Heated Gold Ore",
	"Iron Plate", "Copper Plate", "Gold Plate",
	"Steel",
	"Knowledge Fragment",
	"Forge", "Anvil", "Extrusion Machine",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.feedback_requested.connect(_show_feedback)
	GameManager.error_requested.connect(_show_error)
	GameManager.player_died.connect(show_death_overlay)
	GameManager.item_picked_up.connect(_on_item_picked_up)
	GameManager.secondary_task_changed.connect(_on_secondary_task_changed)
	GameManager.hotbar_changed.connect(_refresh_hotbar)
	Inventory.inventory_changed.connect(_update_stats)
	Inventory.inventory_changed.connect(_refresh_hotbar)
	_refresh_hotbar()
	Inventory.boons_changed.connect(_update_stats)
	Inventory.boon_equipped.connect(func(_b): _update_stats())
	get_viewport().focus_exited.connect(func(): get_tree().paused = true)

func _build_ui() -> void:
	# ── Top-left HUD bg ───────────────────────────────────────────────────────
	_hud_bg = ColorRect.new()
	_hud_bg.color = Color(0, 0, 0, 0.5)
	_hud_bg.position = Vector2(4, 4)
	_hud_bg.size = Vector2(170, 80)
	add_child(_hud_bg)

	godmode_label = Label.new()
	godmode_label.position = Vector2(10, 8)
	godmode_label.text = "★ GOD MODE"
	godmode_label.add_theme_color_override("font_color", Color(1, 0.8, 0, 1))
	godmode_label.visible = false
	add_child(godmode_label)

	stats_label = Label.new()
	stats_label.position = Vector2(10, 8)
	stats_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	add_child(stats_label)

	# ── Sprint bar ────────────────────────────────────────────────────────────
	sprint_bar = ProgressBar.new()
	sprint_bar.anchor_left   = 0.5
	sprint_bar.anchor_right  = 0.5
	sprint_bar.anchor_top    = 1.0
	sprint_bar.anchor_bottom = 1.0
	sprint_bar.offset_left   = -100.0
	sprint_bar.offset_right  =  100.0
	sprint_bar.offset_top    = -82.0
	sprint_bar.offset_bottom = -77.0
	sprint_bar.max_value = SPRINT_MAX
	sprint_bar.value = SPRINT_MAX
	sprint_bar.show_percentage = false
	sprint_bar.visible = false
	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = Color(0.2, 0.8, 0.9, 1.0)
	sprint_bar.add_theme_stylebox_override("fill", style_fill)
	add_child(sprint_bar)

	# ── Feedback label (centered, auto-width) ─────────────────────────────────
	var feedback_bg := ColorRect.new()
	feedback_bg.name = "FeedbackBg"
	feedback_bg.color = Color(0, 0, 0, 0.5)
	feedback_bg.anchor_left   = 0.5
	feedback_bg.anchor_right  = 0.5
	feedback_bg.anchor_top    = 1.0
	feedback_bg.anchor_bottom = 1.0
	feedback_bg.offset_top    = -138.0
	feedback_bg.offset_bottom = -108.0
	feedback_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	feedback_bg.visible = false
	add_child(feedback_bg)

	feedback_label = Label.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.anchor_left   = 0.5
	feedback_label.anchor_right  = 0.5
	feedback_label.anchor_top    = 1.0
	feedback_label.anchor_bottom = 1.0
	feedback_label.offset_top    = -135.0
	feedback_label.offset_bottom = -110.0
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_color_override("font_color", Color(1, 1, 0.5, 1))
	feedback_label.visible = false
	add_child(feedback_label)

	var warning_bg := ColorRect.new()
	warning_bg.name = "WarningBg"
	warning_bg.color = Color(0, 0, 0, 0.5)
	warning_bg.anchor_left   = 0.5
	warning_bg.anchor_right  = 0.5
	warning_bg.anchor_top    = 1.0
	warning_bg.anchor_bottom = 1.0
	warning_bg.offset_top    = -158.0
	warning_bg.offset_bottom = -133.0
	warning_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	warning_bg.visible = false
	add_child(warning_bg)

	_warning_label = Label.new()
	_warning_label.anchor_left   = 0.5
	_warning_label.anchor_right  = 0.5
	_warning_label.anchor_top    = 1.0
	_warning_label.anchor_bottom = 1.0
	_warning_label.offset_top    = -155.0
	_warning_label.offset_bottom = -135.0
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.add_theme_color_override("font_color", Color(0.7, 0.3, 1.0, 1))
	_warning_label.visible = false
	add_child(_warning_label)

	# ── Cheat input ───────────────────────────────────────────────────────────
	cheat_input = LineEdit.new()
	cheat_input.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cheat_input.position = Vector2(0, -32)
	cheat_input.size = Vector2(0, 24)
	cheat_input.placeholder_text = "enter a command or type help on for hints"
	cheat_input.visible = false
	cheat_input.text_submitted.connect(_on_command_submitted)
	cheat_input.focus_exited.connect(func(): cheat_input.visible = false)
	add_child(cheat_input)

	_help_bg = ColorRect.new()
	_help_bg.color = Color(0, 0, 0, 0.25)
	_help_bg.anchor_left   = 0.0
	_help_bg.anchor_right  = 0.0
	_help_bg.anchor_top    = 1.0
	_help_bg.anchor_bottom = 1.0
	_help_bg.offset_left   = 8.0
	_help_bg.offset_right  = 460.0
	_help_bg.offset_top    = -185.0
	_help_bg.offset_bottom = -50.0
	_help_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_help_bg)

	_help_label = Label.new()
	_help_label.anchor_left   = 0.0
	_help_label.anchor_right  = 0.0
	_help_label.anchor_top    = 1.0
	_help_label.anchor_bottom = 1.0
	_help_label.offset_left   = 14.0
	_help_label.offset_right  = 454.0
	_help_label.offset_top    = -182.0
	_help_label.offset_bottom = -54.0
	_help_label.add_theme_font_size_override("font_size", 11)
	_help_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1))
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_help_label.text = (
		"godmode — toggle god mode\n"
		+ "speed [1-5] — movement speed (3=default)\n"
		+ "gamespeed [1-50] — timer speed (1=default)\n"
		+ "give [item] / give all / help give — items\n"
		+ "sim new — enter Simulacrum   sim free — spawn portal\n"
		+ "home new / home / home clear — manage warp point\n"
		+ "task reset / next / finish — manage tasks\n"
		+ "help on / off — toggle hints   SPACE — roll"
	)
	_help_label.visible = false
	add_child(_help_label)
	# bg follows label visibility
	_help_bg.visible = false

	# ── Minimap ───────────────────────────────────────────────────────────────
	var MinimapScript := load("res://scripts/minimap.gd")
	minimap = MinimapScript.new()
	add_child(minimap)

	# ── Task section (below minimap) ──────────────────────────────────────────
	var task_top: float = 8.0 + SMALL_MAP_H + 4.0
	var task_h: float = 100.0

	_task_bg = ColorRect.new()
	_task_bg.color = Color(0, 0, 0, 0.72)
	_task_bg.anchor_left   = 1.0
	_task_bg.anchor_right  = 1.0
	_task_bg.anchor_top    = 0.0
	_task_bg.anchor_bottom = 0.0
	_task_bg.offset_left   = -(SMALL_MAP_W + 8.0)
	_task_bg.offset_right  = -8.0
	_task_bg.offset_top    = task_top
	_task_bg.offset_bottom = task_top + task_h
	add_child(_task_bg)

	var task_hint_lbl := Label.new()
	task_hint_lbl.text = "Tasks  [ T ]"
	task_hint_lbl.anchor_left   = 1.0
	task_hint_lbl.anchor_right  = 1.0
	task_hint_lbl.anchor_top    = 0.0
	task_hint_lbl.anchor_bottom = 0.0
	task_hint_lbl.offset_left   = -(SMALL_MAP_W + 8.0) + 5.0
	task_hint_lbl.offset_right  = -13.0
	task_hint_lbl.offset_top    = task_top + 3.0
	task_hint_lbl.offset_bottom = task_top + 15.0
	task_hint_lbl.add_theme_font_size_override("font_size", 8)
	task_hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	add_child(task_hint_lbl)

	_task_label = Label.new()
	_task_label.anchor_left   = 1.0
	_task_label.anchor_right  = 1.0
	_task_label.anchor_top    = 0.0
	_task_label.anchor_bottom = 0.0
	_task_label.offset_left   = -(SMALL_MAP_W + 8.0) + 5.0
	_task_label.offset_right  = -13.0
	_task_label.offset_top    = task_top + 16.0
	_task_label.offset_bottom = task_top + task_h
	_task_label.add_theme_font_size_override("font_size", 9)
	_task_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	_task_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_task_label)

	# ── Task updated popup ─────────────────────────────────────────────────────
	_task_updated_label = Label.new()
	_task_updated_label.anchor_left   = 0.5
	_task_updated_label.anchor_right  = 0.5
	_task_updated_label.anchor_top    = 0.0
	_task_updated_label.anchor_bottom = 0.0
	_task_updated_label.offset_left   = -180.0
	_task_updated_label.offset_right  =  180.0
	_task_updated_label.offset_top    = 42.0
	_task_updated_label.offset_bottom = 88.0
	_task_updated_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_task_updated_label.add_theme_font_size_override("font_size", 33)
	_task_updated_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1))
	_task_updated_label.text = "Tasks Updated"
	_task_updated_label.visible = false
	add_child(_task_updated_label)

	# ── Dungeon countdown timer ────────────────────────────────────────────────
	_dungeon_timer_label = Label.new()
	_dungeon_timer_label.anchor_left   = 0.5
	_dungeon_timer_label.anchor_right  = 0.5
	_dungeon_timer_label.anchor_top    = 0.0
	_dungeon_timer_label.anchor_bottom = 0.0
	_dungeon_timer_label.offset_left   = -60.0
	_dungeon_timer_label.offset_right  =  60.0
	_dungeon_timer_label.offset_top    =  8.0
	_dungeon_timer_label.offset_bottom =  36.0
	_dungeon_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dungeon_timer_label.add_theme_font_size_override("font_size", 18)
	_dungeon_timer_label.add_theme_color_override("font_color", Color(1, 0.9, 0.9, 1))
	_dungeon_timer_label.visible = false
	add_child(_dungeon_timer_label)

	# ── Hotbar (bottom centre) ────────────────────────────────────────────────
	const SLOT_W: float = 36.0
	const SLOT_H: float = 36.0
	const GAP: float    = 4.0
	var total_w: float  = HOTBAR_SIZE * SLOT_W + (HOTBAR_SIZE - 1) * GAP
	var half_w: float   = total_w * 0.5

	_hotbar_bg = ColorRect.new()
	_hotbar_bg.color = Color(0, 0, 0, 0.5)
	_hotbar_bg.anchor_left   = 0.5
	_hotbar_bg.anchor_right  = 0.5
	_hotbar_bg.anchor_top    = 1.0
	_hotbar_bg.anchor_bottom = 1.0
	_hotbar_bg.offset_left   = -half_w - 6.0
	_hotbar_bg.offset_right  =  half_w + 6.0
	_hotbar_bg.offset_top    = -(SLOT_H + 20.0 + 8.0)
	_hotbar_bg.offset_bottom = -8.0
	add_child(_hotbar_bg)

	for i in HOTBAR_SIZE:
		var slot_bg := ColorRect.new()
		slot_bg.anchor_left   = 0.5
		slot_bg.anchor_right  = 0.5
		slot_bg.anchor_top    = 1.0
		slot_bg.anchor_bottom = 1.0
		slot_bg.offset_left   = -half_w + i * (SLOT_W + GAP)
		slot_bg.offset_right  = -half_w + i * (SLOT_W + GAP) + SLOT_W
		slot_bg.offset_top    = -(SLOT_H + 20.0 + 4.0)
		slot_bg.offset_bottom = -(20.0 + 4.0)
		slot_bg.color = Color(0.10, 0.10, 0.10, 0.9)
		add_child(slot_bg)

		# Yellow selection border (hidden by default)
		var border := ColorRect.new()
		border.anchor_left   = 0.5
		border.anchor_right  = 0.5
		border.anchor_top    = 1.0
		border.anchor_bottom = 1.0
		border.offset_left   = -half_w + i * (SLOT_W + GAP) - 2.0
		border.offset_right  = -half_w + i * (SLOT_W + GAP) + SLOT_W + 2.0
		border.offset_top    = -(SLOT_H + 20.0 + 6.0)
		border.offset_bottom = -(20.0 + 2.0)
		border.color = Color(1.0, 0.85, 0.0, 0.0)  # alpha 0 = hidden
		add_child(border)

		var slot_label := Label.new()
		slot_label.anchor_left   = 0.5
		slot_label.anchor_right  = 0.5
		slot_label.anchor_top    = 1.0
		slot_label.anchor_bottom = 1.0
		slot_label.offset_left   = -half_w + i * (SLOT_W + GAP)
		slot_label.offset_right  = -half_w + i * (SLOT_W + GAP) + SLOT_W
		slot_label.offset_top    = -(SLOT_H + 20.0 + 4.0)
		slot_label.offset_bottom = -(20.0 + 4.0)
		slot_label.text = ""
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 6)
		slot_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		add_child(slot_label)

		var num_lbl := Label.new()
		num_lbl.anchor_left   = 0.5
		num_lbl.anchor_right  = 0.5
		num_lbl.anchor_top    = 1.0
		num_lbl.anchor_bottom = 1.0
		num_lbl.offset_left   = -half_w + i * (SLOT_W + GAP)
		num_lbl.offset_right  = -half_w + i * (SLOT_W + GAP) + SLOT_W
		num_lbl.offset_top    = -20.0
		num_lbl.offset_bottom = -4.0
		num_lbl.text = str(i + 1)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_lbl.add_theme_font_size_override("font_size", 7)
		num_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		add_child(num_lbl)

		_hotbar_slots.append({bg = slot_bg, border = border, label = slot_label, num_lbl = num_lbl})

	# ── Item tracker (bottom right) ───────────────────────────────────────────
	_tracker_bg = ColorRect.new()
	_tracker_bg.color = Color(0, 0, 0, 0.55)
	_tracker_bg.anchor_left   = 1.0
	_tracker_bg.anchor_right  = 1.0
	_tracker_bg.anchor_top    = 1.0
	_tracker_bg.anchor_bottom = 1.0
	_tracker_bg.offset_left   = -120.0
	_tracker_bg.offset_right  = -8.0
	_tracker_bg.offset_top    = -90.0
	_tracker_bg.offset_bottom = -68.0
	_tracker_bg.visible = false
	add_child(_tracker_bg)

	_tracker_label = Label.new()
	_tracker_label.anchor_left   = 1.0
	_tracker_label.anchor_right  = 1.0
	_tracker_label.anchor_top    = 1.0
	_tracker_label.anchor_bottom = 1.0
	_tracker_label.offset_left   = -116.0
	_tracker_label.offset_right  = -12.0
	_tracker_label.offset_top    = -88.0
	_tracker_label.offset_bottom = -70.0
	_tracker_label.add_theme_font_size_override("font_size", 9)
	_tracker_label.add_theme_color_override("font_color", Color(1, 1, 0.7, 1))
	_tracker_label.visible = false
	add_child(_tracker_label)

	# ── Pause overlay ─────────────────────────────────────────────────────────
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0, 0, 0, 0.25)
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	_pause_label = Label.new()
	_pause_label.anchor_left   = 0.5
	_pause_label.anchor_right  = 0.5
	_pause_label.anchor_top    = 0.5
	_pause_label.anchor_bottom = 0.5
	_pause_label.offset_left   = -200.0
	_pause_label.offset_right  =  200.0
	_pause_label.offset_top    = -40.0
	_pause_label.offset_bottom =  40.0
	_pause_label.text = "GAME PAUSED\nPress ESC or left click to resume"
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 24)
	_pause_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_pause_label.visible = false
	add_child(_pause_label)

	# ── Death overlay ─────────────────────────────────────────────────────────
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0, 0, 0, 0.25)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.visible = false
	add_child(_death_overlay)

	_death_label = Label.new()
	_death_label.anchor_left   = 0.5
	_death_label.anchor_right  = 0.5
	_death_label.anchor_top    = 0.5
	_death_label.anchor_bottom = 0.5
	_death_label.offset_left   = -200.0
	_death_label.offset_right  =  200.0
	_death_label.offset_top    = -30.0
	_death_label.offset_bottom =  30.0
	_death_label.text = "Simulacrum Failed"
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 28)
	_death_label.add_theme_color_override("font_color", Color(1, 0.1, 0.1, 1))
	_death_label.visible = false
	add_child(_death_label)

	_update_stats()

# ── Death overlay ─────────────────────────────────────────────────────────────

func show_death_overlay() -> void:
	_death_overlay.visible = true
	_death_label.visible = true
	_death_timer = 2.0

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Safety: clear block_input if no fullscreen GUI is actually visible
	if GameManager.block_input:
		var any_open := false
		for node in get_tree().get_nodes_in_group("inventory_ui"):
			if (node as CanvasLayer).visible:
				any_open = true
				break
		if not any_open:
			for node in get_tree().get_nodes_in_group("crafting_ui"):
				if (node as CanvasLayer).visible:
					any_open = true
					break
		if not any_open:
			for forge in get_tree().get_nodes_in_group("forges"):
				if forge.get("_gui_open") == true:
					any_open = true
					break
		if not any_open:
			for anvil in get_tree().get_nodes_in_group("anvils"):
				if anvil.get("_gui_open") == true:
					any_open = true
					break
		if not any_open:
			GameManager.block_input = false

	# Death overlay countdown
	if _death_timer > 0.0:
		_death_timer -= delta
		if _death_timer <= 0.0:
			_death_overlay.visible = false
			_death_label.visible = false

	var is_paused := get_tree().paused
	_pause_overlay.visible = is_paused
	_pause_label.visible = is_paused

	if is_paused:
		_hud_bg.visible = false
		godmode_label.visible = false
		stats_label.visible = false
		sprint_bar.visible = false
		feedback_label.visible = false
		minimap.visible = false
		_task_bg.visible = false
		_task_label.visible = false
		_hotbar_bg.visible = false
		for slot_data in _hotbar_slots:
			slot_data.bg.visible = false
			slot_data.border.visible = false
			slot_data.label.visible = false
			slot_data.num_lbl.visible = false
		return

	minimap.visible = true
	_hud_bg.visible = true
	stats_label.visible = true
	_task_bg.visible = true
	_task_label.visible = true

	# Auto-advance tasks by world-state checks
	_check_task_conditions()

	if _task_overview_open and _task_overview_dirty:
		_task_overview_dirty = false
		_refresh_task_overview()

	# Task popup — detect index increase, grant KF reward
	var cur_ti := GameManager.task_index
	if cur_ti != _task_prev_index:
		_task_overview_dirty = true
	if cur_ti > _task_prev_index and cur_ti < 99:
		_task_updated_timer = 2.5
		_task_updated_label.visible = true
		Inventory.add_item({
			"name": "Knowledge Fragment",
			"description": "Crystallised memory.",
			"quantity": 100
		})
		GameManager.item_picked_up.emit("Knowledge Fragment", 100)
	_task_prev_index = cur_ti
	if _task_updated_timer > 0.0:
		_task_updated_timer -= delta
		_task_updated_label.modulate.a = clampf(_task_updated_timer / 0.5, 0.0, 1.0)
		if _task_updated_timer <= 0.0:
			_task_updated_label.visible = false

	# Dungeon timer
	var dungeon_on := GameManager.dungeon_active
	if dungeon_on and not _prev_dungeon_active:
		_dungeon_timer = DUNGEON_TIME
	_prev_dungeon_active = dungeon_on
	if dungeon_on and _dungeon_timer >= 0.0:
		_dungeon_timer -= delta
		var secs: float = max(0.0, _dungeon_timer)
		var mm := int(secs) / 60
		var ss := int(secs) % 60
		_dungeon_timer_label.text = "%d:%02d" % [mm, ss]
		_dungeon_timer_label.add_theme_color_override("font_color",
			Color(1, 0.3, 0.3, 1) if secs < 30.0 else Color(1, 0.9, 0.9, 1))
		_dungeon_timer_label.visible = true
		if _dungeon_timer <= 0.0:
			GameManager.player_died.emit()
	else:
		_dungeon_timer_label.visible = false

	# Update task label
	var task_text := "TASKS\n"
	if GameManager.dungeon_active:
		task_text += "▶ Find exit"
	else:
		match GameManager.task_index:
			0: task_text += "▶ Go to the Crafting Bench"
			1: task_text += "▶ Craft a Pickaxe"
			2: task_text += "▶ Find an Iron Deposit"
			3: task_text += "▶ Mine 5 Iron Ore"
			4: task_text += "▶ Find a Geothermal Vent"
			5: task_text += "▶ Smelt an Iron Plate"
			6: task_text += "▶ Fix the Sim Engine (5× Iron Plate)"
			_: task_text += "▶ Run the Simulacrum"
	# Geothermal vent status
	for vent in get_tree().get_nodes_in_group("geothermal_vents"):
		var is_proc: bool = vent.get("_processing") == true
		var ready: bool = vent.get("_ready_to_collect") == true
		var c_flash: float = vent.get("_complete_flash") as float
		if is_proc:
			var secs: float = max(0.0, vent.get("_process_timer") as float)
			var mm := int(secs) / 60
			var ss := int(secs) % 60
			var plate: String = vent.get("_queued_plate") as String
			task_text += "\n  Geothermal Vent: %s [%d:%02d]" % [plate, mm, ss]
		elif ready:
			var item: String = vent.get("_collect_item") as String
			task_text += "\n  Geothermal Vent: %s [collect!]" % item
		elif c_flash > 0.0:
			var plate: String = vent.get("_complete_plate") as String
			task_text += "\n  Geothermal Vent: %s [complete]" % plate
	# Forge status
	for forge in get_tree().get_nodes_in_group("forges"):
		var is_proc: bool = forge.get("_processing") == true
		var ready: bool = forge.get("_ready_to_collect") == true
		if is_proc:
			var secs: float = max(0.0, forge.get("_process_timer") as float)
			var mm := int(secs) / 60
			var ss := int(secs) % 60
			var output: String = forge.get("_queued_output") as String
			task_text += "\n  Forge: %s [%d:%02d]" % [output, mm, ss]
		elif ready:
			var item: String = forge.get("_collect_item") as String
			task_text += "\n  Forge: %s [collect!]" % item
	_task_label.text = task_text

	# Auto-hide hint panel when prompt closes
	if _hint_canvas != null and _hint_canvas.visible and not cheat_input.visible:
		_hint_canvas.visible = false

	# Item tracker
	var to_erase: Array = []
	for key in _tracker.keys():
		_tracker[key].timer -= delta
		if _tracker[key].timer <= 0.0:
			to_erase.append(key)
	for key in to_erase:
		_tracker.erase(key)

	if not _tracker.is_empty():
		var lines := ""
		for key in _tracker:
			lines += "x%d %s\n" % [_tracker[key].count, key]
		_tracker_label.text = lines.strip_edges()
		_tracker_label.visible = true
		_tracker_bg.visible = true
	else:
		_tracker_label.visible = false
		_tracker_bg.visible = false

	var godmode_on := GameManager.godmode
	godmode_label.visible = godmode_on
	stats_label.position.y = 28.0 if godmode_on else 8.0
	var content_bottom: float = stats_label.position.y + stats_label.size.y + 6.0
	_hud_bg.size.y = max(content_bottom, 40.0)

	var _help_vis := _help_on and cheat_input.visible
	_help_label.visible = _help_vis
	_help_bg.visible    = _help_vis

	if feedback_timer > 0.0:
		feedback_timer -= delta
		if feedback_timer <= 0.0:
			feedback_label.visible = false
			var fbg := get_node_or_null("FeedbackBg") as ColorRect
			if fbg != null:
				fbg.visible = false

	if _warning_timer > 0.0:
		_warning_timer -= delta
		if _warning_timer <= 0.0:
			_warning_label.visible = false
			var wbg := get_node_or_null("WarningBg") as ColorRect
			if wbg != null:
				wbg.visible = false

	var energy := GameManager.sprint_energy
	var active := GameManager.sprint_active
	sprint_bar.value = energy

	if active or energy < SPRINT_MAX:
		sprint_bar.visible = true
		sprint_bar.modulate.a = 1.0
		sprint_bar_fade_timer = SPRINT_FADE_DELAY
	elif sprint_bar.visible:
		sprint_bar_fade_timer -= delta
		if sprint_bar_fade_timer <= 0.0:
			sprint_bar.visible = false
		else:
			sprint_bar.modulate.a = sprint_bar_fade_timer / SPRINT_FADE_DELAY

# ── Hotbar ────────────────────────────────────────────────────────────────────

func _refresh_hotbar() -> void:
	_hotbar_bg.visible = true
	for i in HOTBAR_SIZE:
		var slot_data: Dictionary = _hotbar_slots[i]
		var item_name: String = GameManager.hotbar[i]
		var is_selected: bool = (i == GameManager.hotbar_selected)
		slot_data.bg.color = Color(0.18, 0.18, 0.18, 0.9) if is_selected else Color(0.10, 0.10, 0.10, 0.9)
		slot_data.border.color = Color(1.0, 0.85, 0.0, 1.0) if is_selected else Color(0, 0, 0, 0)
		if item_name.is_empty():
			slot_data.label.text = ""
			slot_data.label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
		else:
			# Truncate long names to fit
			var short := item_name.left(8) if item_name.length() > 8 else item_name
			slot_data.label.text = short
			slot_data.label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		slot_data.bg.visible = true
		slot_data.border.visible = true
		slot_data.label.visible = true
		slot_data.num_lbl.visible = true

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Left click resumes pause (checked first, before anything else)
	if get_tree().paused \
			and event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		get_tree().paused = false
		get_viewport().set_input_as_handled()
		return

	if cheat_input.visible:
		if event.is_action_pressed("ui_cancel"):
			_toggle_cheat()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_cheat_engine"):
		minimap.is_large = false
		_close_inventory()
		if get_tree().paused:
			get_tree().paused = false
		_toggle_cheat()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_minimap"):
		minimap.is_large = !minimap.is_large
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event as InputEventKey).keycode == KEY_T \
			and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_toggle_task_overview()
		get_viewport().set_input_as_handled()
		return

	# Number keys 1-5 → select hotbar slot
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		var slot := -1
		if   kc == KEY_1: slot = 0
		elif kc == KEY_2: slot = 1
		elif kc == KEY_3: slot = 2
		elif kc == KEY_4: slot = 3
		elif kc == KEY_5: slot = 4
		if slot >= 0:
			GameManager.hotbar_selected = slot
			GameManager.hotbar_changed.emit()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_cancel"):
		if _task_overview_open:
			_close_task_overview()
			get_viewport().set_input_as_handled()
			return
		if minimap.is_large:
			minimap.is_large = false
			get_viewport().set_input_as_handled()
		elif _inventory_is_open():
			_close_inventory()
			get_viewport().set_input_as_handled()
		else:
			get_tree().paused = !get_tree().paused
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	if _task_overview_open and _task_overview_canvas != null:
		var panel := _task_overview_canvas.get_child(0) as Panel
		if panel != null and not panel.get_global_rect().has_point(event.position):
			_close_task_overview()
			get_viewport().set_input_as_handled()
			return
	if minimap.is_large and not minimap.get_rect().has_point(event.position):
		minimap.is_large = false
		get_viewport().set_input_as_handled()

# ── Cheat engine ──────────────────────────────────────────────────────────────

func _toggle_cheat() -> void:
	cheat_input.visible = !cheat_input.visible
	if cheat_input.visible:
		cheat_input.grab_focus()
		cheat_input.text = ""
	else:
		cheat_input.release_focus()

func _on_command_submitted(cmd: String) -> void:
	_process_command(cmd.strip_edges())
	cheat_input.text = ""
	cheat_input.visible = false
	cheat_input.release_focus()

func _process_command(cmd: String) -> void:
	var lower := cmd.to_lower()
	if lower == "godmode":
		GameManager.set_godmode(!GameManager.godmode)
	elif lower == "home":
		if GameManager.dungeon_active:
			GameManager.error_requested.emit("I cannot do that.")
		elif GameManager.home_position.x == INF:
			GameManager.error_requested.emit("I cannot do that.")
		else:
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player:
				player.global_position = GameManager.home_position
				GameManager.feedback_requested.emit("Warped home.")
	elif lower == "home new":
		if GameManager.dungeon_active:
			GameManager.error_requested.emit("I cannot do that.")
		else:
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player:
				GameManager.home_position = player.global_position
				GameManager.feedback_requested.emit("Home set.")
	elif lower == "home clear":
		if GameManager.dungeon_active:
			GameManager.error_requested.emit("I cannot do that.")
		else:
			GameManager.home_position = Vector2(INF, INF)
			GameManager.feedback_requested.emit("Home cleared.")
	elif lower == "give all":
		for tool_name: String in ["Pickaxe", "Hammer", "Axe", "Sickle", "Sword", "Spear"]:
			Inventory.add_item({"name": tool_name, "description": "", "quantity": 1})
		GameManager.feedback_requested.emit("Received all tools.")
	elif lower.begins_with("give "):
		var item_name := cmd.substr(5).strip_edges()
		var canonical := _canonicalize_item(item_name)
		if canonical.is_empty():
			GameManager.feedback_requested.emit("Unknown item: " + item_name)
		else:
			const PLACEABLES: Array[String] = ["Forge", "Anvil", "Extrusion Machine"]
			if canonical in PLACEABLES:
				GameManager.placement_requested.emit(canonical)
			else:
				Inventory.add_item({"name": canonical, "description": "", "quantity": 1})
				GameManager.item_picked_up.emit(canonical, 1)
				GameManager.feedback_requested.emit("Received: " + canonical)
	elif lower == "simulacrum new" or lower == "sim new":
		GameManager.dungeon_active = false
		get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
	elif lower == "simulacrum over" or lower == "sim over":
		GameManager.dungeon_over_requested.emit()
	elif lower == "simulacrum free" or lower == "sim free":
		GameManager.dungeon_free_requested.emit()
	elif lower == "task reset":
		GameManager.task_index = 0
		GameManager.feedback_requested.emit("Tasks reset.")
	elif lower == "task next":
		GameManager.task_index += 1
		GameManager.feedback_requested.emit("Task advanced.")
	elif lower == "task finish":
		GameManager.task_index = 99
		GameManager.feedback_requested.emit("All tasks complete.")
	elif lower == "help on":
		_help_on = true
		GameManager.feedback_requested.emit("Help hints: ON")
	elif lower == "help off":
		_help_on = false
		GameManager.feedback_requested.emit("Help hints: OFF")
	elif lower == "help":
		_help_label.visible = true
		_help_bg.visible = true
		get_tree().create_timer(5.0).timeout.connect(func():
			if not _help_on:
				_help_label.visible = false
				_help_bg.visible = false
		)
	elif lower == "help give":
		_set_hint_panel(not (_hint_canvas != null and _hint_canvas.visible))
	elif lower.begins_with("gamespeed "):
		var parts := lower.split(" ")
		if parts.size() == 2 and parts[1].is_valid_int():
			var val := parts[1].to_int()
			if val >= 1 and val <= 50:
				GameManager.set_gamespeed(val)
				_show_warning("adjusting gamespeed can break certain game elements")
				return
		GameManager.feedback_requested.emit("Usage: gamespeed [1-50]")
	elif lower.begins_with("speed "):
		var parts := lower.split(" ")
		if parts.size() == 2 and parts[1].is_valid_int():
			var val := parts[1].to_int()
			if val >= 1 and val <= 5:
				GameManager.set_speed(val)
				return
		GameManager.feedback_requested.emit("Usage: speed [1-5]")
	else:
		GameManager.feedback_requested.emit("Unknown command: " + cmd)

func _check_task_conditions() -> void:
	var ti := GameManager.task_index
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	match ti:
		2:  # find iron deposit
			for poi in get_tree().get_nodes_in_group("pois"):
				var n2d := poi as Node2D
				if n2d.name.begins_with("IronDeposit") \
						and n2d.global_position.distance_to(player.global_position) < 140.0:
					GameManager.task_index = 3
					return
		3:  # mine 5 iron ore
			if Inventory.get_item_count("Iron Ore") >= 5:
				GameManager.task_index = 4
		4:  # find geothermal vent
			for vent in get_tree().get_nodes_in_group("geothermal_vents"):
				var n2d := vent as Node2D
				if n2d.global_position.distance_to(player.global_position) < 200.0:
					GameManager.task_index = 5
					return
		5:  # smelt iron plate
			if Inventory.get_item_count("Iron Plate") >= 1:
				GameManager.task_index = 6

func _canonicalize_item(raw: String) -> String:
	match raw.to_lower().strip_edges():
		"pickaxe":              return "Pickaxe"
		"hammer":               return "Hammer"
		"sickle":               return "Sickle"
		"sword":                return "Sword"
		"axe":                  return "Axe"
		"log":                  return "Log"
		"rock":                 return "Rock"
		"coal":                 return "Coal"
		"heated coal":          return "Heated Coal"
		"iron ore", "iron":     return "Iron Ore"
		"copper ore", "copper": return "Copper Ore"
		"gold ore", "gold":     return "Gold Ore"
		"crystal shard", "crystal": return "Crystal Shard"
		"heated iron ore":      return "Heated Iron Ore"
		"heated copper ore":    return "Heated Copper Ore"
		"heated gold ore":      return "Heated Gold Ore"
		"iron plate":           return "Iron Plate"
		"copper plate":         return "Copper Plate"
		"gold plate":           return "Gold Plate"
		"steel":                return "Steel"
		"knowledge fragment", "fragment": return "Knowledge Fragment"
		"spear":                return "Spear"
		"forge":                return "Forge"
		"anvil":                return "Anvil"
		"extrusion machine", "extrusion": return "Extrusion Machine"
		_:                      return ""

# ── Inventory helpers ─────────────────────────────────────────────────────────

func _inventory_is_open() -> bool:
	for node in get_tree().get_nodes_in_group("inventory_ui"):
		if (node as CanvasLayer).visible:
			return true
	return false

func _close_inventory() -> void:
	for node in get_tree().get_nodes_in_group("inventory_ui"):
		(node as CanvasLayer).visible = false
	GameManager.block_input = false

# ── Item tracker ──────────────────────────────────────────────────────────────

func _on_item_picked_up(item_name: String, qty: int) -> void:
	if _tracker.has(item_name):
		_tracker[item_name].count += qty
	else:
		_tracker[item_name] = {count = qty, timer = 0.0}
	_tracker[item_name].timer = 1.5

# ── Stats & health ────────────────────────────────────────────────────────────

func _on_health_changed(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum
	_update_stats()

func _update_stats() -> void:
	var frags: int = Inventory.get_item_count("Knowledge Fragment")
	var boon: String = Inventory.get_equipped_boon_name()
	stats_label.text = (
		"HP: %d / %d\nFrags: %d\nBoon: %s"
		% [_current_hp, _max_hp, frags, boon]
	)

func _fit_subtitle_bg(lbl: Label, bg: ColorRect, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var text_w: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pad := 32.0
	var w := text_w + pad
	lbl.offset_left  = -w * 0.5
	lbl.offset_right =  w * 0.5
	bg.offset_left   = -w * 0.5
	bg.offset_right  =  w * 0.5

func _show_warning(msg: String) -> void:
	_warning_label.text = msg
	_warning_label.visible = true
	_warning_timer = 5.0
	var wbg := get_node_or_null("WarningBg") as ColorRect
	if wbg != null:
		wbg.visible = true
		_fit_subtitle_bg(_warning_label, wbg, 14)

func _show_feedback(msg: String) -> void:
	feedback_label.text = msg
	feedback_label.add_theme_color_override("font_color", Color(1, 1, 0.5, 1))
	feedback_label.visible = true
	feedback_timer = 3.0
	var fbg := get_node_or_null("FeedbackBg") as ColorRect
	if fbg != null:
		fbg.visible = true
		_fit_subtitle_bg(feedback_label, fbg, 14)

func _show_error(msg: String) -> void:
	feedback_label.text = msg
	feedback_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	feedback_label.visible = true
	feedback_timer = 3.0
	var fbg := get_node_or_null("FeedbackBg") as ColorRect
	if fbg != null:
		fbg.visible = true
		_fit_subtitle_bg(feedback_label, fbg, 14)

func _on_secondary_task_changed() -> void:
	_task_updated_timer = 2.5
	_task_updated_label.visible = true

# ── Task overview (T key) ─────────────────────────────────────────────────────

const _TASK_DEFS: Array = [
	{text="Go to the Crafting Bench",        prereq=""},
	{text="Craft a Pickaxe",                 prereq="Visit the Crafting Bench first"},
	{text="Find an Iron Deposit",            prereq="Craft a Pickaxe first"},
	{text="Mine 5 Iron Ore",                 prereq="Find an Iron Deposit first"},
	{text="Find a Geothermal Vent",          prereq="Mine 5 Iron Ore first"},
	{text="Smelt an Iron Plate",             prereq="Find a Geothermal Vent first"},
	{text="Fix the Sim Engine (5× Iron Plate)", prereq="Smelt an Iron Plate first"},
]

func _toggle_task_overview() -> void:
	if _task_overview_open:
		_close_task_overview()
	else:
		_open_task_overview()

func _open_task_overview() -> void:
	_task_overview_open = true
	if _task_overview_canvas == null:
		_build_task_overview()
	_task_overview_canvas.visible = true
	_task_overview_dirty = true

func _close_task_overview() -> void:
	_task_overview_open = false
	if _task_overview_canvas != null:
		_task_overview_canvas.visible = false

func _build_task_overview() -> void:
	_task_overview_canvas = CanvasLayer.new()
	_task_overview_canvas.layer = 10
	add_child(_task_overview_canvas)

	var vp_size := get_viewport().get_visible_rect().size
	var panel := Panel.new()
	panel.position = vp_size * 0.5 - Vector2(200, 200)
	panel.size = Vector2(400, 400)
	_task_overview_canvas.add_child(panel)

	var title := Label.new()
	title.text = "— TASKS —"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 10
	title.offset_bottom = 32
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4, 1.0))
	panel.add_child(title)

	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 0.5)
	sep.position = Vector2(8, 34)
	sep.size = Vector2(384, 1)
	panel.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 40)
	scroll.size = Vector2(384, 336)
	panel.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	var hint := Label.new()
	hint.text = "[ T ] or [ ESC ] to close"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -20
	hint.offset_bottom = -4
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	panel.add_child(hint)

func _refresh_task_overview() -> void:
	if _task_overview_canvas == null:
		return
	var panel := _task_overview_canvas.get_child(0) as Panel
	if panel == null:
		return
	var rows := panel.find_child("Rows") as VBoxContainer
	if rows == null:
		return
	for c in rows.get_children():
		c.queue_free()

	var ti := GameManager.task_index
	for i in _TASK_DEFS.size():
		var def: Dictionary = _TASK_DEFS[i]
		var is_done := i < ti
		var is_current := i == ti
		var is_locked := i > ti

		var status := "[done] " if is_done else (">> " if is_current else "   ")
		var task_lbl := Label.new()
		task_lbl.text = status + str(def.get("text", ""))
		task_lbl.add_theme_font_size_override("font_size", 11)
		if is_done:
			task_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 1.0))
		elif is_current:
			task_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
		else:
			task_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
		rows.add_child(task_lbl)

		if is_locked:
			var prereq_str: String = str(def.get("prereq", ""))
			if not prereq_str.is_empty():
				var prereq_lbl := Label.new()
				prereq_lbl.text = "     [locked] " + prereq_str
				prereq_lbl.add_theme_font_size_override("font_size", 8)
				prereq_lbl.add_theme_color_override("font_color", Color(0.4, 0.35, 0.35, 1.0))
				rows.add_child(prereq_lbl)

		var sep := ColorRect.new()
		sep.color = Color(0.3, 0.3, 0.3, 0.4)
		sep.custom_minimum_size = Vector2(0, 1)
		rows.add_child(sep)

# ── Give-hint item browser ─────────────────────────────────────────────────────

func _set_hint_panel(on: bool) -> void:
	if on:
		if _hint_canvas == null:
			_build_hint_panel()
		_hint_page = 0
		_hint_canvas.visible = true
		_refresh_hint_page()
		GameManager.feedback_requested.emit("Item list: ON")
	else:
		if _hint_canvas != null:
			_hint_canvas.visible = false
		GameManager.feedback_requested.emit("Item list: OFF")

func _build_hint_panel() -> void:
	_hint_canvas = CanvasLayer.new()
	_hint_canvas.layer = 7
	add_child(_hint_canvas)

	var panel := Panel.new()
	panel.anchor_left   = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = 8.0
	panel.offset_right  = 258.0
	panel.offset_top    = -408.0
	panel.offset_bottom = -198.0
	panel.set_meta("_hint_panel", true)
	_hint_canvas.add_child(panel)

	var title := Label.new()
	title.text = "All Items"
	title.position = Vector2(8, 6)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5, 1.0))
	panel.add_child(title)

	var page_lbl := Label.new()
	page_lbl.name = "PageLabel"
	page_lbl.position = Vector2(140, 6)
	page_lbl.add_theme_font_size_override("font_size", 8)
	page_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	panel.add_child(page_lbl)

	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 0.5)
	sep.position = Vector2(4, 22)
	sep.size = Vector2(242, 1)
	panel.add_child(sep)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.position = Vector2(4, 26)
	rows.size = Vector2(242, 150)
	panel.add_child(rows)

	var nav := HBoxContainer.new()
	nav.position = Vector2(4, 180)
	nav.size = Vector2(242, 20)
	panel.add_child(nav)

	var prev_btn := Button.new()
	prev_btn.text = "◀ Prev"
	prev_btn.add_theme_font_size_override("font_size", 8)
	prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_btn.pressed.connect(func():
		_hint_page = max(0, _hint_page - 1)
		_refresh_hint_page()
	)
	nav.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "Next ▶"
	next_btn.add_theme_font_size_override("font_size", 8)
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.pressed.connect(func():
		var total_pages := int(ceil(float(_ALL_ITEMS.size()) / 10.0))
		_hint_page = min(total_pages - 1, _hint_page + 1)
		_refresh_hint_page()
	)
	nav.add_child(next_btn)

func _refresh_hint_page() -> void:
	if _hint_canvas == null:
		return
	var panel: Panel = null
	for c in _hint_canvas.get_children():
		if c.has_meta("_hint_panel"):
			panel = c as Panel
			break
	if panel == null:
		return

	var rows := panel.get_node("Rows") as VBoxContainer
	for c in rows.get_children():
		c.queue_free()

	var total_pages := int(ceil(float(_ALL_ITEMS.size()) / 10.0))
	var page_lbl := panel.get_node("PageLabel") as Label
	page_lbl.text = "Page %d / %d" % [_hint_page + 1, total_pages]

	var start := _hint_page * 10
	for i in 10:
		var idx := start + i
		if idx >= _ALL_ITEMS.size():
			break
		var item_name: String = _ALL_ITEMS[idx]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		rows.add_child(row)

		var lbl := Label.new()
		lbl.text = item_name
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1.0))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var btn := Button.new()
		const TOOLS_SET: Array[String] = ["Pickaxe", "Hammer", "Sickle", "Sword", "Axe"]
		var give_qty: int = 1 if item_name in TOOLS_SET else 10
		btn.text = "Give" if give_qty == 1 else "Give ×10"
		btn.add_theme_font_size_override("font_size", 7)
		var captured := item_name
		var qty := give_qty
		btn.pressed.connect(func():
			Inventory.add_item({"name": captured, "description": "", "quantity": qty})
			GameManager.item_picked_up.emit(captured, qty)
			GameManager.feedback_requested.emit("Received ×%d: %s" % [qty, captured])
		)
		row.add_child(btn)
