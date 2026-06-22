extends CanvasLayer

const SPRINT_MAX: float = 3.0
const SPRINT_FADE_DELAY: float = 0.8
const SMALL_MAP_W: float = 200.0
const SMALL_MAP_H: float = 137.5
const DUNGEON_TIME_FIRST: float  = 300.0   # 5 min for first run
const DUNGEON_TIME_LATER: float  = 600.0   # 10 min for 2+ runs
# Legacy alias used in inline code
const DUNGEON_TIME: float = 300.0

var _hud_bg: ColorRect = null
var godmode_label: Label = null
var stats_label: Label = null
var feedback_label: Label
var _warning_label: Label
var _warning_timer: float = 0.0
var sprint_bar: ProgressBar
var cheat_input: LineEdit
var minimap: Control
var _pause_overlay: ColorRect
var _pause_label: Label
var _pause_on_defocus: bool  # mirrors GameManager.pause_on_defocus
var _death_overlay: ColorRect
var _death_label: Label
var _death_timer: float = 0.0

# Red damage-flash overlay
var _flash_overlay: ColorRect
var _flash_phase: float = -1.0    # <0 = inactive; counts 0..0.25 over a pulse
var _flash_peak: float = 0.0      # peak alpha for the current pulse
var _flash_hits: int = 0          # hits within the rolling window
var _flash_window: float = 0.0    # time remaining in the 0.25s stacking window

# Green heal-flash overlay
var _heal_overlay: ColorRect
var _heal_phase: float = -1.0

# Bottom HUD fade alpha (for smooth show/hide)
var _hud_bottom_alpha: float = 1.0

# Hotbar (5 generic slots)
var _hotbar_bg: ColorRect
var _hotbar_slots: Array = []  # [{bg, border, label, num_lbl}]
const HOTBAR_SIZE: int = 5

# Extra slots flanking the hotbar
var _vial_slot_bg: ColorRect       # healing vial slot (left of slot 1)
var _vial_slot_label: Label
var _weapon_slot_bg: ColorRect     # equipped weapon slot (right of slot 5)
var _weapon_slot_label: Label
var _health_orb: Control           # circular HP display
var _frag_counter_label: Label     # fragment count (shown 1s on acquire)
var _frag_counter_timer: float = 0.0

# Item tracker
var _tracker_label: RichTextLabel
var _tracker_bg: ColorRect
var _tracker: Dictionary = {}  # item_name -> {count, timer}

# Task section
var _task_bg: ColorRect
var _task_label: RichTextLabel

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
var _task_rows: VBoxContainer = null  # direct reference to avoid find_child issues
const _ALL_ITEMS: Array[String] = [
	"Pickaxe", "Hammer", "Axe", "Sickle",
	"Great Axe", "Crossbow",
	"Healing Vial", "String",
	"Log", "Rock", "Coal", "Heated Coal",
	"Iron Ore", "Copper Ore", "Gold Ore", "Crystal Shard",
	"Heated Iron Ore", "Heated Copper Ore", "Heated Gold Ore",
	"Iron Plate", "Copper Plate", "Gold Plate",
	"Steel",
	"Knowledge Fragment", "Boon Fragment",
	"Forge", "Anvil", "Extrusion Machine",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.health_changed.connect(func(cur: int, mx: int):
		if _health_orb != null:
			_health_orb.set("current_hp", cur)
			_health_orb.set("max_hp", mx)
			_health_orb.queue_redraw()
	)
	GameManager.feedback_requested.connect(_show_feedback)
	GameManager.error_requested.connect(_show_error)
	GameManager.player_died.connect(show_death_overlay)
	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.item_picked_up.connect(_on_item_picked_up)
	GameManager.player_healed.connect(_on_player_healed)
	GameManager.secondary_task_changed.connect(_on_secondary_task_changed)
	GameManager.hotbar_changed.connect(_refresh_hotbar)
	GameManager.godmode_changed.connect(func(enabled: bool): godmode_label.visible = enabled)
	Inventory.inventory_changed.connect(_update_stats)
	Inventory.inventory_changed.connect(_refresh_hotbar)
	_refresh_hotbar()
	Inventory.boons_changed.connect(_update_stats)
	Inventory.boon_equipped.connect(func(_b): _update_stats())
	_pause_on_defocus = GameManager.pause_on_defocus
	get_viewport().focus_exited.connect(func():
		if GameManager.pause_on_defocus:
			get_tree().paused = true
	)

func _build_ui() -> void:

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

	# ── Godmode label (top-left) ──────────────────────────────────────────────
	godmode_label = Label.new()
	godmode_label.text = "GOD MODE"
	godmode_label.visible = GameManager.godmode
	godmode_label.add_theme_color_override("font_color", Color(0.75, 0.3, 1.0, 1.0))
	godmode_label.add_theme_font_size_override("font_size", 10)
	godmode_label.position = Vector2(8, 8)
	godmode_label.z_index = 20
	add_child(godmode_label)

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
		+ "speed [1-5] — movement speed   gamespeed [1-50] — game speed\n"
		+ "give [item] / give all / help give — items\n"
		+ "  items: pickaxe hammer axe sickle great axe crossbow\n"
		+ "         healing vial string boon fragment knowledge fragment\n"
		+ "         iron/copper/gold ore & plate  steel  coal  log  rock\n"
		+ "save — manual save   clear — wipe save & restart\n"
		+ "spawn enemy/miniboss/trapped/chest/chalice/barrel/vent/overworld_chest\n"
		+ "sim new — enter Simulacrum   sim free — spawn portal\n"
		+ "home new / home / home clear — manage warp point\n"
		+ "task reset / next / finish — manage tasks\n"
		+ "help on / off — toggle hints   SPACE — roll   F — healing vial"
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

	_task_label = RichTextLabel.new()
	_task_label.anchor_left   = 1.0
	_task_label.anchor_right  = 1.0
	_task_label.anchor_top    = 0.0
	_task_label.anchor_bottom = 0.0
	_task_label.offset_left   = -(SMALL_MAP_W + 8.0) + 5.0
	_task_label.offset_right  = -13.0
	_task_label.offset_top    = task_top + 16.0
	_task_label.offset_bottom = task_top + task_h
	_task_label.bbcode_enabled = true
	_task_label.scroll_active = false
	_task_label.fit_content = true
	_task_label.add_theme_font_size_override("normal_font_size", 9)
	_task_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9, 1))
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
	const EXT_SLOT: float = 40.0  # extra slots are 10% larger
	const EXT_GAP: float  = 10.0  # gap between hotbar and extra slots
	const ORB_SIZE: float = 50.0  # health orb diameter
	const ORB_GAP: float  = 8.0
	var total_w: float  = HOTBAR_SIZE * SLOT_W + (HOTBAR_SIZE - 1) * GAP
	var half_w: float   = total_w * 0.5

	# Extended bg covers hotbar + extra slots + orb
	var ext_left: float = -(half_w + EXT_GAP + EXT_SLOT + ORB_GAP + ORB_SIZE + 6.0)
	var ext_right: float = half_w + EXT_GAP + EXT_SLOT + 6.0

	_hotbar_bg = ColorRect.new()
	_hotbar_bg.color = Color(0, 0, 0, 0.5)
	_hotbar_bg.anchor_left   = 0.5
	_hotbar_bg.anchor_right  = 0.5
	_hotbar_bg.anchor_top    = 1.0
	_hotbar_bg.anchor_bottom = 1.0
	_hotbar_bg.offset_left   = ext_left
	_hotbar_bg.offset_right  = ext_right
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

	# ── Healing vial slot (left of hotbar) ───────────────────────────────────
	var vial_x_right: float = -half_w - EXT_GAP
	var vial_x_left: float  = vial_x_right - EXT_SLOT
	var slot_top: float    = -(EXT_SLOT + 20.0 + 6.0)
	var slot_bot: float    = -(20.0 + 2.0)

	_vial_slot_bg = ColorRect.new()
	_vial_slot_bg.color = Color(0.08, 0.12, 0.08, 0.9)
	_vial_slot_bg.anchor_left   = 0.5
	_vial_slot_bg.anchor_right  = 0.5
	_vial_slot_bg.anchor_top    = 1.0
	_vial_slot_bg.anchor_bottom = 1.0
	_vial_slot_bg.offset_left   = vial_x_left
	_vial_slot_bg.offset_right  = vial_x_right
	_vial_slot_bg.offset_top    = slot_top
	_vial_slot_bg.offset_bottom = slot_bot
	add_child(_vial_slot_bg)

	_vial_slot_label = Label.new()
	_vial_slot_label.anchor_left   = 0.5
	_vial_slot_label.anchor_right  = 0.5
	_vial_slot_label.anchor_top    = 1.0
	_vial_slot_label.anchor_bottom = 1.0
	_vial_slot_label.offset_left   = vial_x_left
	_vial_slot_label.offset_right  = vial_x_right
	_vial_slot_label.offset_top    = slot_top
	_vial_slot_label.offset_bottom = slot_bot
	_vial_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vial_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vial_slot_label.add_theme_font_size_override("font_size", 7)
	_vial_slot_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1))
	_vial_slot_label.text = "Vial\n[F]\nx0"
	add_child(_vial_slot_label)

	var vial_num := Label.new()
	vial_num.anchor_left   = 0.5
	vial_num.anchor_right  = 0.5
	vial_num.anchor_top    = 1.0
	vial_num.anchor_bottom = 1.0
	vial_num.offset_left   = vial_x_left
	vial_num.offset_right  = vial_x_right
	vial_num.offset_top    = -20.0
	vial_num.offset_bottom = -4.0
	vial_num.text          = "F"
	vial_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vial_num.add_theme_font_size_override("font_size", 7)
	vial_num.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	add_child(vial_num)

	# ── Weapon slot (right of hotbar) ─────────────────────────────────────────
	var wpn_x_left: float  = half_w + EXT_GAP
	var wpn_x_right: float = wpn_x_left + EXT_SLOT

	_weapon_slot_bg = ColorRect.new()
	_weapon_slot_bg.color = Color(0.12, 0.08, 0.08, 0.9)
	_weapon_slot_bg.anchor_left   = 0.5
	_weapon_slot_bg.anchor_right  = 0.5
	_weapon_slot_bg.anchor_top    = 1.0
	_weapon_slot_bg.anchor_bottom = 1.0
	_weapon_slot_bg.offset_left   = wpn_x_left
	_weapon_slot_bg.offset_right  = wpn_x_right
	_weapon_slot_bg.offset_top    = slot_top
	_weapon_slot_bg.offset_bottom = slot_bot
	add_child(_weapon_slot_bg)

	_weapon_slot_label = Label.new()
	_weapon_slot_label.anchor_left   = 0.5
	_weapon_slot_label.anchor_right  = 0.5
	_weapon_slot_label.anchor_top    = 1.0
	_weapon_slot_label.anchor_bottom = 1.0
	_weapon_slot_label.offset_left   = wpn_x_left
	_weapon_slot_label.offset_right  = wpn_x_right
	_weapon_slot_label.offset_top    = slot_top
	_weapon_slot_label.offset_bottom = slot_bot
	_weapon_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_weapon_slot_label.add_theme_font_size_override("font_size", 6)
	_weapon_slot_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4, 1))
	_weapon_slot_label.text = "—"
	add_child(_weapon_slot_label)

	var wpn_num := Label.new()
	wpn_num.anchor_left   = 0.5
	wpn_num.anchor_right  = 0.5
	wpn_num.anchor_top    = 1.0
	wpn_num.anchor_bottom = 1.0
	wpn_num.offset_left   = wpn_x_left
	wpn_num.offset_right  = wpn_x_right
	wpn_num.offset_top    = -20.0
	wpn_num.offset_bottom = -4.0
	wpn_num.text          = "WPN"
	wpn_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_num.add_theme_font_size_override("font_size", 7)
	wpn_num.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	add_child(wpn_num)

	# ── Fragment counter (right of weapon slot, visible 1s on acquire) ─────────
	_frag_counter_label = Label.new()
	_frag_counter_label.anchor_left   = 0.5
	_frag_counter_label.anchor_right  = 0.5
	_frag_counter_label.anchor_top    = 1.0
	_frag_counter_label.anchor_bottom = 1.0
	_frag_counter_label.offset_left   = wpn_x_right + 6.0
	_frag_counter_label.offset_right  = wpn_x_right + 80.0
	_frag_counter_label.offset_top    = -(EXT_SLOT + 20.0 + 6.0)
	_frag_counter_label.offset_bottom = -(20.0 + 2.0)
	_frag_counter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_frag_counter_label.add_theme_font_size_override("font_size", 8)
	_frag_counter_label.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0, 1))
	_frag_counter_label.visible = false
	add_child(_frag_counter_label)

	# ── Health orb (left of healing vial slot) ────────────────────────────────
	var orb_x: float = vial_x_left - ORB_GAP - ORB_SIZE
	var HealthOrbScript := load("res://scripts/health_orb.gd")
	_health_orb = HealthOrbScript.new()
	_health_orb.anchor_left   = 0.5
	_health_orb.anchor_right  = 0.5
	_health_orb.anchor_top    = 1.0
	_health_orb.anchor_bottom = 1.0
	_health_orb.offset_left   = orb_x
	_health_orb.offset_right  = orb_x + ORB_SIZE
	_health_orb.offset_top    = -(ORB_SIZE + 20.0 + 3.0)
	_health_orb.offset_bottom = -(20.0 + 3.0)
	add_child(_health_orb)

	# ── Item tracker (bottom right) ───────────────────────────────────────────
	# 3× the original, then 25% smaller → ~2.25× (font 20)
	_tracker_bg = ColorRect.new()
	_tracker_bg.color = Color(0, 0, 0, 0.55)
	_tracker_bg.anchor_left   = 1.0
	_tracker_bg.anchor_right  = 1.0
	_tracker_bg.anchor_top    = 1.0
	_tracker_bg.anchor_bottom = 1.0
	_tracker_bg.offset_left   = -260.0
	_tracker_bg.offset_right  = -8.0
	_tracker_bg.offset_top    = -176.0
	_tracker_bg.offset_bottom = -68.0
	_tracker_bg.visible = false
	add_child(_tracker_bg)

	var tracker_rtl := RichTextLabel.new()
	tracker_rtl.anchor_left   = 1.0
	tracker_rtl.anchor_right  = 1.0
	tracker_rtl.anchor_top    = 1.0
	tracker_rtl.anchor_bottom = 1.0
	tracker_rtl.offset_left   = -252.0
	tracker_rtl.offset_right  = -16.0
	tracker_rtl.offset_top    = -170.0
	tracker_rtl.offset_bottom = -72.0
	tracker_rtl.bbcode_enabled = true
	tracker_rtl.scroll_active = false
	tracker_rtl.fit_content = true
	tracker_rtl.add_theme_font_size_override("normal_font_size", 20)
	tracker_rtl.visible = false
	_tracker_label = tracker_rtl
	add_child(tracker_rtl)

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

	# ── Red damage-flash overlay (drawn over everything) ──────────────────────
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(0.9, 0.0, 0.0, 0.0)
	_flash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.visible = false
	add_child(_flash_overlay)

	_heal_overlay = ColorRect.new()
	_heal_overlay.color = Color(0.0, 0.85, 0.3, 0.0)
	_heal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heal_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heal_overlay.visible = false
	add_child(_heal_overlay)

	_update_stats()

# ── Death overlay ─────────────────────────────────────────────────────────────

func _on_player_healed() -> void:
	_heal_phase = 0.0

func _update_heal_flash(delta: float) -> void:
	if _heal_phase < 0.0:
		return
	_heal_phase += delta
	const HALF: float = 0.15
	var a: float
	if _heal_phase < HALF:
		a = 0.18 * (_heal_phase / HALF)
	elif _heal_phase < 2.0 * HALF:
		a = 0.18 * (1.0 - (_heal_phase - HALF) / HALF)
	else:
		a = 0.0
		_heal_phase = -1.0
	_heal_overlay.color.a = a
	_heal_overlay.visible = a > 0.0

func _on_player_damaged() -> void:
	# Stack intensity for hits landing inside the rolling 0.25s window.
	if _flash_window > 0.0:
		_flash_hits += 1
	else:
		_flash_hits = 1
	_flash_window = 0.25
	var levels := [0.10, 0.15, 0.20, 0.25]
	_flash_peak = levels[min(_flash_hits - 1, 3)]
	_flash_phase = 0.0  # restart the pulse

func _update_flash(delta: float) -> void:
	if _flash_window > 0.0:
		_flash_window -= delta
	if _flash_phase < 0.0:
		return
	_flash_phase += delta
	const HALF: float = 0.125  # fade in 0.125s, out 0.125s → 0.25s total
	var a: float
	if _flash_phase < HALF:
		a = _flash_peak * (_flash_phase / HALF)
	elif _flash_phase < 2.0 * HALF:
		a = _flash_peak * (1.0 - (_flash_phase - HALF) / HALF)
	else:
		a = 0.0
		_flash_phase = -1.0
	_flash_overlay.color.a = a
	_flash_overlay.visible = a > 0.0

func show_death_overlay() -> void:
	_death_overlay.visible = true
	_death_label.visible = true
	_death_timer = 2.0
	if GameManager.dungeon_active:
		GameManager.dungeon_active = false
		await get_tree().create_timer(2.0).timeout
		if get_tree() != null:
			get_tree().change_scene_to_file("res://scenes/main.tscn")

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_flash(delta)
	_update_heal_flash(delta)

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
			for machine in get_tree().get_nodes_in_group("machines"):
				if machine.get("_ui_open") == true:
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

	# Smooth alpha fade for bottom HUD when pausing/unpausing
	var target_alpha := 0.0 if is_paused else 1.0
	_hud_bottom_alpha = move_toward(_hud_bottom_alpha, target_alpha, delta * 5.0)
	var hud_a := _hud_bottom_alpha
	_hotbar_bg.modulate.a = hud_a
	for slot_data in _hotbar_slots:
		slot_data.bg.modulate.a        = hud_a
		slot_data.border.modulate.a    = hud_a
		slot_data.label.modulate.a     = hud_a
		slot_data.num_lbl.modulate.a   = hud_a
	_vial_slot_bg.modulate.a      = hud_a
	_vial_slot_label.modulate.a   = hud_a
	_weapon_slot_bg.modulate.a    = hud_a
	_weapon_slot_label.modulate.a = hud_a
	_health_orb.modulate.a        = hud_a
	_hotbar_bg.visible            = hud_a > 0.01
	_vial_slot_bg.visible         = hud_a > 0.01
	_weapon_slot_bg.visible       = hud_a > 0.01
	_health_orb.visible           = hud_a > 0.01

	if is_paused:
		sprint_bar.visible = false
		feedback_label.visible = false
		minimap.visible = false
		_task_bg.visible = false
		_task_label.visible = false
		_frag_counter_label.visible = false
		return

	minimap.visible = true
	_task_bg.visible = true
	_task_label.visible = true

	# Update healing vial slot
	var vial_count := Inventory.get_item_count("Healing Vial")
	_vial_slot_label.text = "Vial\n[F]\nx%d" % vial_count
	_vial_slot_bg.color = Color(0.08, 0.18, 0.08, 0.9) if vial_count > 0 else Color(0.08, 0.06, 0.06, 0.9)

	# Update weapon slot
	var wpn := GameManager.equipped_weapon
	_weapon_slot_label.text = wpn if not wpn.is_empty() else "—"

	# Fragment counter
	if _frag_counter_timer > 0.0:
		_frag_counter_timer -= delta
		_frag_counter_label.modulate.a = clampf(_frag_counter_timer / 0.4, 0.0, 1.0)
		_frag_counter_label.visible = true
		if _frag_counter_timer <= 0.0:
			_frag_counter_label.visible = false

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
			"quantity": 50
		})
		GameManager.item_picked_up.emit("Knowledge Fragment", 50)
	_task_prev_index = cur_ti
	if _task_updated_timer > 0.0:
		_task_updated_timer -= delta
		_task_updated_label.modulate.a = clampf(_task_updated_timer / 0.5, 0.0, 1.0)
		if _task_updated_timer <= 0.0:
			_task_updated_label.visible = false

	# Dungeon timer
	var dungeon_on := GameManager.dungeon_active
	if dungeon_on and not _prev_dungeon_active:
		_dungeon_timer = DUNGEON_TIME_LATER if GameManager.sim_iterations > 1 else DUNGEON_TIME_FIRST
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
	var task_lines: Array[String] = []
	var task_colors: Array[Color] = []   # per-line color; empty = default

	task_lines.append("TASKS")
	task_colors.append(Color(0.55, 0.55, 0.55, 1))

	if GameManager.dungeon_active:
		task_lines.append("▶ Find The Exit")
		task_colors.append(Color(0.9, 0.9, 0.9, 1))
	else:
		var ti := GameManager.task_index
		var iron_have := Inventory.get_item_count("Iron Ore")
		var plate_have := Inventory.get_item_count("Iron Plate")
		match ti:
			0:
				task_lines.append("▶ Go to the Crafting Bench")
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			1:
				task_lines.append("▶ Craft a Pickaxe")
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			2:
				task_lines.append("▶ Find an Iron Deposit")
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			3:
				task_lines.append("▶ Mine Iron Ore [%d/5]" % iron_have)
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			4:
				task_lines.append("▶ Find a Geothermal Vent")
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			5:
				task_lines.append("▶ Smelt an Iron Plate")
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			6:
				task_lines.append("▶ Fix the Simulacrum Engine [%d/5 Iron Plates]" % plate_have)
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
			_:
				# After fixing the engine: main task is Run the Sim Engine, plus
				# three OPTIONAL gear crafts.
				task_lines.append("▶ Run the Simulacrum Engine")
				task_colors.append(Color(0.9, 0.9, 0.9, 1))
				var optional := [["Axe", "Craft an Axe"], ["Sickle", "Craft a Sickle"], ["Broadaxe", "Craft a Broadaxe"]]
				for opt in optional:
					var owned := Inventory.get_item_count(opt[0]) > 0
					var mark := "✓" if owned else "•"
					task_lines.append("  %s (OPTIONAL) %s" % [mark, opt[1]])
					task_colors.append(Color(0.4, 0.8, 0.45, 1) if owned else Color(0.6, 0.6, 0.6, 1))

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
			task_lines.append("  Vent: %s [%d:%02d]" % [plate, mm, ss])
			task_colors.append(Color(1.0, 0.60, 0.1, 1))
		elif ready:
			var item: String = vent.get("_collect_item") as String
			task_lines.append("  Vent: %s [collect]" % item)
			task_colors.append(Color(0.3, 0.9, 0.35, 1))
		elif c_flash > 0.0:
			var plate: String = vent.get("_complete_plate") as String
			task_lines.append("  Vent: %s [complete]" % plate)
			task_colors.append(Color(0.3, 0.9, 0.35, 1))

	# Forge status
	for forge in get_tree().get_nodes_in_group("forges"):
		var is_proc: bool = forge.get("_processing") == true
		var ready: bool = forge.get("_ready_to_collect") == true
		if is_proc:
			var secs: float = max(0.0, forge.get("_process_timer") as float)
			var mm := int(secs) / 60
			var ss := int(secs) % 60
			var output: String = forge.get("_queued_output") as String
			task_lines.append("  Forge: %s [%d:%02d]" % [output, mm, ss])
			task_colors.append(Color(1.0, 0.60, 0.1, 1))
		elif ready:
			var item: String = forge.get("_collect_item") as String
			task_lines.append("  Forge: %s [collect]" % item)
			task_colors.append(Color(0.3, 0.9, 0.35, 1))

	# Tracked recipes (from crafting UI [TRACK] button)
	for tr in GameManager.tracked_recipes:
		var rname: String = tr.get("name", "")
		var parts: Array[String] = []
		var all_met := true
		for ing in tr.get("ingredients", []):
			var have := Inventory.get_item_count(ing.item)
			parts.append("%d/%d %s" % [have, ing.qty, ing.item])
			if have < ing.qty:
				all_met = false
		task_lines.append("◆ %s (%s)" % [rname.to_upper(), ", ".join(parts)])
		task_colors.append(Color(0.4, 0.85, 0.4, 1) if all_met else Color(0.5, 0.75, 1.0, 1))

	# Build BBCode string with per-line colors
	var bbcode := ""
	for li in task_lines.size():
		var c: Color = task_colors[li]
		var hex := "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
		if li > 0:
			bbcode += "\n"
		bbcode += "[color=%s]%s[/color]" % [hex, task_lines[li]]
	_task_label.text = bbcode

	# Resize task box to fit content. RichTextLabel.get_content_height() accounts
	# for wrapped lines (long tracked-recipe rows can span multiple lines).
	const TASK_PAD: float = 22.0
	var content_h: float = _task_label.get_content_height()
	if content_h <= 0.0:
		content_h = task_lines.size() * 13.0  # first-frame fallback before layout
	var needed_h: float = max(content_h + TASK_PAD + 8.0, 40.0)
	_task_bg.offset_bottom = _task_bg.offset_top + needed_h
	_task_label.offset_bottom = _task_bg.offset_top + needed_h

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
		var tracker_bb := ""
		for key in _tracker:
			var col: Color = _tracker[key].get("color", Color(0.65, 0.65, 0.65, 1))
			var hex := "#%02x%02x%02x" % [int(col.r*255), int(col.g*255), int(col.b*255)]
			if not tracker_bb.is_empty():
				tracker_bb += "\n"
			tracker_bb += "[color=%s]x%d %s[/color]" % [hex, _tracker[key].count, key]
		_tracker_label.text = tracker_bb
		_tracker_label.visible = true
		_tracker_bg.visible = true
	else:
		_tracker_label.visible = false
		_tracker_bg.visible = false

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

	# While typing in a UI search field, let the field consume keys — only ESC
	# (ui_cancel) still triggers HUD shortcuts.
	if event is InputEventKey and not event.is_action_pressed("ui_cancel"):
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit:
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

	if event is InputEventKey and (event as InputEventKey).keycode == KEY_P \
			and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		GameManager.pause_on_defocus = not GameManager.pause_on_defocus
		_pause_on_defocus = GameManager.pause_on_defocus
		var status := "ON" if GameManager.pause_on_defocus else "OFF"
		GameManager.feedback_requested.emit("Pause on defocus: %s" % status)
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
			return
		if _inventory_is_open():
			_close_inventory()
			get_viewport().set_input_as_handled()
			return
		# Close the crafting UI if open
		var craft_closed := false
		for cui in get_tree().get_nodes_in_group("crafting_ui"):
			if (cui as CanvasLayer).visible:
				if cui.has_method("close"):
					cui.close()
				else:
					(cui as CanvasLayer).visible = false
					GameManager.block_input = false
				craft_closed = true
		if craft_closed:
			get_viewport().set_input_as_handled()
			return
		# Close any open in-world machine GUIs
		var closed_machine := false
		for machine in get_tree().get_nodes_in_group("machines"):
			# Workstation-style GUI
			if machine.get("_ui_open") == true and machine.has_method("_close_ui"):
				machine._close_ui()
				closed_machine = true
			# Simulacrum Engine repair GUI
			if machine.get("_repair_open") == true and machine.has_method("_close_repair_gui"):
				machine._close_repair_gui()
				closed_machine = true
			# Simulacrum Engine iteration GUI
			if machine.get("_sim_open") == true and machine.has_method("_close_sim_gui"):
				machine._close_sim_gui()
				closed_machine = true
		for forge in get_tree().get_nodes_in_group("forges"):
			if forge.get("_gui_open") == true and forge.has_method("_close_gui"):
				forge._close_gui()
				closed_machine = true
		for anvil in get_tree().get_nodes_in_group("anvils"):
			if anvil.get("_gui_open") == true and anvil.has_method("_close_gui"):
				anvil._close_gui()
				closed_machine = true
		if closed_machine:
			get_viewport().set_input_as_handled()
			return
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
		for tool_name: String in ["Pickaxe", "Hammer", "Axe", "Sickle", "Great Axe"]:
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
				if canonical == "Boon Fragment":
					GameManager.boon_fragments += 1
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
	elif lower == "save":
		var sm := get_node_or_null("/root/SaveManager")
		if sm and sm.has_method("save_game"):
			sm.save_game(true)
		else:
			GameManager.feedback_requested.emit("Save not available.")
	elif lower == "clear":
		_show_clear_protection_ui()
	elif lower.begins_with("spawn "):
		_process_spawn(lower.substr(6).strip_edges())
	else:
		GameManager.feedback_requested.emit("Unknown command: " + cmd)

func _show_clear_protection_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(overlay)

	var panel := Panel.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -180.0
	panel.offset_right  =  180.0
	panel.offset_top    = -80.0
	panel.offset_bottom =  80.0
	canvas.add_child(panel)

	var title := Label.new()
	title.text = "⚠  WIPE SAVE DATA?"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 16)
	title.size = Vector2(360, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25, 1))
	panel.add_child(title)

	var sub := Label.new()
	sub.text = "This will delete all save data and restart the game.\nThis cannot be undone."
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.position = Vector2(0, 48)
	sub.size = Vector2(360, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 9)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1))
	panel.add_child(sub)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm — Wipe & Restart"
	confirm_btn.position = Vector2(20, 110)
	confirm_btn.size = Vector2(150, 30)
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1))
	confirm_btn.pressed.connect(func():
		canvas.queue_free()
		var sm2 := get_node_or_null("/root/SaveManager")
		if sm2 and sm2.has_method("clear_save"):
			sm2.clear_save()
		_reset_game_state()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	panel.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.position = Vector2(190, 110)
	cancel_btn.size = Vector2(150, 30)
	cancel_btn.pressed.connect(func(): canvas.queue_free())
	panel.add_child(cancel_btn)

func _process_spawn(what: String) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		GameManager.error_requested.emit("No player found.")
		return
	var spawn_pos := player.global_position + Vector2(64, 0)
	var scene_root := get_tree().current_scene

	match what:
		"enemy":
			var enemy_scn := load("res://scenes/enemy.tscn") as PackedScene
			if enemy_scn:
				var e := enemy_scn.instantiate() as Node2D
				e.global_position = spawn_pos
				scene_root.add_child(e)
				GameManager.feedback_requested.emit("Spawned enemy.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/enemy.tscn")
		"miniboss":
			var enemy_scn := load("res://scenes/enemy.tscn") as PackedScene
			if enemy_scn:
				var e := enemy_scn.instantiate()
				e.global_position = spawn_pos
				scene_root.add_child(e)
				if e.has_method("set"):
					e.set("max_health", 25)
					e.set("health", 25)
					e.set("attack_damage", 6)
					e.set("miss_chance", 0.05)
				GameManager.feedback_requested.emit("Spawned miniboss.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/enemy.tscn")
		"trapped":
			var chest_scn := load("res://scenes/chest.tscn") as PackedScene
			if chest_scn:
				var c := chest_scn.instantiate()
				c.global_position = spawn_pos
				if c.has_method("set"):
					c.set("is_trapped", true)
					c.set("is_empty", true)
				scene_root.add_child(c)
				GameManager.feedback_requested.emit("Spawned trapped chest.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/chest.tscn")
		"chest":
			var chest_scn := load("res://scenes/chest.tscn") as PackedScene
			if chest_scn:
				var c := chest_scn.instantiate()
				c.global_position = spawn_pos
				if c.has_method("set"):
					c.set("reward_kf_min", 250)
					c.set("reward_kf_max", 750)
					c.set("guarantee_boon_fragment", true)
				scene_root.add_child(c)
				GameManager.feedback_requested.emit("Spawned reward chest.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/chest.tscn")
		"chalice":
			var chalice_scn := load("res://scenes/chalice.tscn") as PackedScene
			if chalice_scn:
				var c := chalice_scn.instantiate() as Node2D
				c.global_position = spawn_pos
				scene_root.add_child(c)
				GameManager.feedback_requested.emit("Spawned chalice.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/chalice.tscn")
		"barrel":
			var barrel_scn := load("res://scenes/breakable.tscn") as PackedScene
			if barrel_scn:
				var b := barrel_scn.instantiate() as Node2D
				b.global_position = spawn_pos
				scene_root.add_child(b)
				GameManager.feedback_requested.emit("Spawned barrel.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/breakable.tscn")
		"vent", "geothermal vent", "geothermal_vent":
			var vent_scn := load("res://scenes/geothermal_vent.tscn") as PackedScene
			if vent_scn:
				var v := vent_scn.instantiate() as Node2D
				v.global_position = spawn_pos
				if v.has_method("set"):
					v.set("has_ash", false)
				scene_root.add_child(v)
				GameManager.feedback_requested.emit("Spawned vent.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/geothermal_vent.tscn")
		"overworld chest", "overworld_chest":
			var ruins_scn := load("res://scenes/ruins_chest.tscn") as PackedScene
			if ruins_scn:
				var r := ruins_scn.instantiate() as Node2D
				r.global_position = spawn_pos
				scene_root.add_child(r)
				GameManager.feedback_requested.emit("Spawned overworld chest.")
			else:
				GameManager.error_requested.emit("Missing: res://scenes/ruins_chest.tscn")
		_:
			GameManager.feedback_requested.emit("Usage: /spawn enemy|miniboss|trapped|chest|chalice|barrel|vent|overworld_chest")

func _reset_game_state() -> void:
	# Wipe inventory
	Inventory.items.clear()
	Inventory.inventory_changed.emit()
	# Reset all GameManager persistent state to defaults
	GameManager.task_index                    = 0
	GameManager.hotbar                        = ["", "", "", "", ""]
	GameManager.hotbar_selected               = 0
	GameManager.equipped_weapon               = ""
	GameManager.active_boons.clear()
	GameManager.boon_fragments                = 0
	GameManager.workstation_fragments_pending = 0
	GameManager.sim_iterations                = 0
	GameManager.sim_engine_fixed              = false
	GameManager.dungeon_active                = false
	GameManager.home_position                 = Vector2(INF, INF)
	GameManager.placed_machines.clear()
	GameManager.forge_states.clear()
	GameManager.vent_states.clear()
	GameManager.tracked_recipes.clear()
	GameManager._save_restore_pos             = Vector2(INF, INF)
	GameManager._save_restore_health          = -1
	GameManager._godmode_inv_snapshot.clear()
	GameManager._godmode_was_active           = false
	if GameManager.godmode:
		GameManager.godmode = false
		GameManager.godmode_changed.emit(false)
	Engine.time_scale = 1.0

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
		"sword":                return "Great Axe"
		"great axe":            return "Great Axe"
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
		"healing vial", "vial": return "Healing Vial"
		"string":               return "String"
		"crossbow":             return "Crossbow"
		"boon fragment":        return "Boon Fragment"
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
		if node.has_method("_close"):
			node._close()
		else:
			(node as CanvasLayer).visible = false
	GameManager.block_input = false

# ── Item tracker ──────────────────────────────────────────────────────────────

static func _item_rarity_color(item_name: String) -> Color:
	const LEGENDARY: Array[String] = ["Boon Fragment"]
	const RARE: Array[String] = [
		"Neodymium Ore", "Cerium Ore", "Lanthanum Ore", "Yttrium Ore", "Dysprosium Ore",
		"Crystal Shard", "Steel",
	]
	const UNCOMMON: Array[String] = [
		"Iron Ore", "Copper Ore", "Gold Ore", "Aluminium Ore", "Tin Ore",
		"Lead Ore", "Manganese Ore", "String", "Crossbow",
	]
	if item_name in LEGENDARY: return Color(0.7, 0.3, 1.0, 1)
	if item_name in RARE:      return Color(0.3, 0.5, 1.0, 1)
	if item_name in UNCOMMON:  return Color(0.3, 0.85, 0.35, 1)
	return Color(0.65, 0.65, 0.65, 1)  # Common

func _on_item_picked_up(item_name: String, qty: int) -> void:
	if _tracker.has(item_name):
		_tracker[item_name].count += qty
	else:
		_tracker[item_name] = {count = qty, timer = 0.0, color = _item_rarity_color(item_name)}
	_tracker[item_name].timer = 1.5
	# Show fragment counter for 1s when Boon Fragments are acquired
	if item_name == "Boon Fragment":
		_frag_counter_label.text = "◆ %d Frag%s" % [GameManager.boon_fragments, "s" if GameManager.boon_fragments != 1 else ""]
		_frag_counter_timer = 1.0
		_frag_counter_label.modulate.a = 1.0
		_frag_counter_label.visible = true

# ── Stats & health ────────────────────────────────────────────────────────────

func _on_health_changed(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum
	_update_stats()

func _update_stats() -> void:
	pass  # top-left stats removed

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
	{text="Fix the Simulacrum Engine (5× Iron Plate)", prereq="Smelt an Iron Plate first"},
	{text="Craft an Axe (OPTIONAL)",        prereq="Fix the Simulacrum Engine first"},
	{text="Craft a Sickle (OPTIONAL)",      prereq="Fix the Simulacrum Engine first"},
	{text="Craft a Broadaxe (OPTIONAL)",    prereq="Fix the Simulacrum Engine first"},
	{text="Run the Simulacrum Engine",      prereq="Fix the Simulacrum Engine first"},
]

func _toggle_task_overview() -> void:
	if _task_overview_open:
		_close_task_overview()
	else:
		_open_task_overview()

func _open_task_overview() -> void:
	_task_overview_open = true
	_build_task_overview()  # rebuild fresh each open — avoids stale state
	_task_overview_canvas.visible = true
	_task_overview_dirty = false
	_refresh_task_overview()  # immediate refresh so content shows on first open

func _close_task_overview() -> void:
	_task_overview_open = false
	if _task_overview_canvas != null:
		_task_overview_canvas.visible = false

func _build_task_overview() -> void:
	if _task_overview_canvas != null:
		_task_overview_canvas.queue_free()
		_task_overview_canvas = null
		_task_rows = null
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
	_task_rows = rows

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
	if _task_rows == null:
		return
	var rows := _task_rows
	# Free existing children — use immediate free to avoid duplicates
	for c in rows.get_children():
		c.free()

	var ti := GameManager.task_index

	# ── Main story tasks ──────────────────────────────────────────────────────
	var section_lbl := Label.new()
	section_lbl.text = "STORY TASKS"
	section_lbl.add_theme_font_size_override("font_size", 9)
	section_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.3, 1.0))
	rows.add_child(section_lbl)

	for i in _TASK_DEFS.size():
		var def: Dictionary = _TASK_DEFS[i]
		var is_done    := i < ti
		var is_current := i == ti
		# available = current task; locked = not yet reached
		var task_lbl := Label.new()
		var mark := "✓ " if is_done else ("▶ " if is_current else "  ")
		task_lbl.text = mark + str(def.get("text", ""))
		task_lbl.add_theme_font_size_override("font_size", 10)
		if is_done:
			task_lbl.add_theme_color_override("font_color", Color(0.35, 0.75, 0.35, 1.0))
		elif is_current:
			task_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		else:
			task_lbl.add_theme_color_override("font_color", Color(0.40, 0.40, 0.40, 1.0))
		rows.add_child(task_lbl)

	# ── Temporary / live tasks ────────────────────────────────────────────────
	var has_temp := false
	var temp_lines: Array[String] = []
	var temp_colors: Array[Color] = []

	if GameManager.dungeon_active:
		temp_lines.append("▶ Find The Exit (Simulacrum)")
		temp_colors.append(Color(1.0, 1.0, 1.0, 1.0))
		has_temp = true

	for vent in get_tree().get_nodes_in_group("geothermal_vents"):
		if vent.get("_processing") == true:
			var secs: float = max(0.0, vent.get("_process_timer") as float)
			var mm := int(secs) / 60; var ss := int(secs) % 60
			temp_lines.append("  Vent: %s [%d:%02d]" % [vent.get("_queued_plate") as String, mm, ss])
			temp_colors.append(Color(1.0, 0.6, 0.1, 1.0))
			has_temp = true
		elif vent.get("_ready_to_collect") == true:
			temp_lines.append("  Vent: %s [collect]" % (vent.get("_collect_item") as String))
			temp_colors.append(Color(0.3, 0.9, 0.35, 1.0))
			has_temp = true

	for forge in get_tree().get_nodes_in_group("forges"):
		if forge.get("_processing") == true:
			var secs: float = max(0.0, forge.get("_process_timer") as float)
			var mm := int(secs) / 60; var ss := int(secs) % 60
			temp_lines.append("  Forge: %s [%d:%02d]" % [forge.get("_queued_output") as String, mm, ss])
			temp_colors.append(Color(1.0, 0.6, 0.1, 1.0))
			has_temp = true
		elif forge.get("_ready_to_collect") == true:
			temp_lines.append("  Forge: %s [collect]" % (forge.get("_collect_item") as String))
			temp_colors.append(Color(0.3, 0.9, 0.35, 1.0))
			has_temp = true

	if has_temp:
		var div := ColorRect.new()
		div.color = Color(0.35, 0.35, 0.35, 0.45)
		div.custom_minimum_size = Vector2(0, 1)
		rows.add_child(div)
		var sec2 := Label.new()
		sec2.text = "ACTIVE"
		sec2.add_theme_font_size_override("font_size", 9)
		sec2.add_theme_color_override("font_color", Color(0.7, 0.65, 0.3, 1.0))
		rows.add_child(sec2)
		for li in temp_lines.size():
			var tl := Label.new()
			tl.text = temp_lines[li]
			tl.add_theme_font_size_override("font_size", 10)
			tl.add_theme_color_override("font_color", temp_colors[li])
			rows.add_child(tl)

	# ── Tracked recipes ───────────────────────────────────────────────────────
	if not GameManager.tracked_recipes.is_empty():
		var div2 := ColorRect.new()
		div2.color = Color(0.35, 0.35, 0.35, 0.45)
		div2.custom_minimum_size = Vector2(0, 1)
		rows.add_child(div2)
		var sec3 := Label.new()
		sec3.text = "TRACKED RECIPES"
		sec3.add_theme_font_size_override("font_size", 9)
		sec3.add_theme_color_override("font_color", Color(0.7, 0.65, 0.3, 1.0))
		rows.add_child(sec3)
		for tr in GameManager.tracked_recipes:
			var rname: String = tr.get("name", "")
			var all_met := true
			var parts: Array[String] = []
			for ing in tr.get("ingredients", []):
				var have := Inventory.get_item_count(ing.item)
				parts.append("%d/%d %s" % [have, ing.qty, ing.item])
				if have < ing.qty:
					all_met = false
			var tl := Label.new()
			tl.text = ("✓ " if all_met else "◆ ") + rname + " (%s)" % ", ".join(parts)
			tl.add_theme_font_size_override("font_size", 9)
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD
			tl.add_theme_color_override("font_color",
				Color(0.35, 0.85, 0.35, 1.0) if all_met else Color(0.5, 0.75, 1.0, 1.0))
			rows.add_child(tl)

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
		const TOOLS_SET: Array[String] = ["Pickaxe", "Hammer", "Sickle", "Axe"]
		var give_qty: int = 1 if item_name in TOOLS_SET else 10
		btn.text = "Give" if give_qty == 1 else "Give ×10"
		btn.add_theme_font_size_override("font_size", 7)
		var captured := item_name
		var qty := give_qty
		btn.pressed.connect(func():
			Inventory.add_item({"name": captured, "description": "", "quantity": qty})
			if captured == "Boon Fragment":
				GameManager.boon_fragments += qty
			GameManager.item_picked_up.emit(captured, qty)
			GameManager.feedback_requested.emit("Received ×%d: %s" % [qty, captured])
		)
		row.add_child(btn)
