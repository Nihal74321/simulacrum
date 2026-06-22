extends Node2D

const FRAGMENT_COST: int = 4
const CLAIM_KF_COST: int = 1000
const HOVER_RADIUS: float = 24.0
const INTERACTION_RANGE: float = 90.0

const BOONS: Array[Dictionary] = [
	{
		id    = "Boon of the Traveller",
		title = "Boon of the Traveller",
		desc  = "+40% movement speed, sprint duration +50%, sprint recharge 2× faster.",
	},
	{
		id    = "Boon of Judgement",
		title = "Boon of Judgement",
		desc  = "Perma AOE: 4 damage to up to 2 enemies in a 3-tile radius every 3 seconds.",
	},
	{
		id    = "Boon of the Hunter",
		title = "Boon of the Hunter",
		desc  = "+20% movement speed, +1 tile melee attack range.",
	},
	{
		id    = "Iron Gauntlet",
		title = "Iron Gauntlet",
		desc  = "+50% damage dealt, +50% attack cooldown, -20% movement speed.",
	},
]

const OUTLINE_RECT: Rect2    = Rect2(-14, -22, 28, 22)
const OUTLINE_COLOR: Color   = Color(1.0, 0.85, 0.0, 1.0)
const OUTLINE_WIDTH: float   = 1.0
const LABEL_FADE_SPEED: float = 2.5

var _hovered: bool = false
var _ui_open: bool = false
var _panel: Node = null
var _label_alpha: float = 0.0
# Fragments placed into the circle this session (not yet claimed)
var _fragments_pending: int = 0

func _ready() -> void:
	z_index = 10
	add_to_group("machines")
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask  = 0
	area.input_pickable  = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 24)
	cs.shape = rect
	cs.position = Vector2(0, -8)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	var new_alpha := clampf(
		_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	if not is_equal_approx(new_alpha, _label_alpha):
		_label_alpha = new_alpha
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-12, -20, 24, 20), Color(0.25, 0.22, 0.35, 1))
	draw_circle(Vector2(0, -24), 6.0, Color(0.6, 0.3, 1.0, 0.85))
	draw_circle(Vector2(0, -24), 3.5, Color(0.9, 0.7, 1.0, 1.0))
	if _label_alpha > 0.0 and not _ui_open:
		draw_rect(OUTLINE_RECT, Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, _label_alpha), false, OUTLINE_WIDTH)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-26, -32), "Work Station", HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(1.0, 1.0, 1.0, _label_alpha))

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	if _v is Viewport:
		(_v as Viewport).set_input_as_handled()
	if _ui_open:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to((player as Node2D).global_position) > INTERACTION_RANGE:
		GameManager.feedback_requested.emit("Too far away.")
		return
	_open_ui()

func _open_ui() -> void:
	_ui_open = true
	GameManager.block_input = true
	_panel = _build_panel()
	get_tree().root.add_child(_panel)

func _close_ui() -> void:
	_ui_open = false
	GameManager.block_input = false
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null

func _place_fragment() -> void:
	if GameManager.boon_fragments < 1:
		GameManager.feedback_requested.emit("No Boon Fragments.")
		return
	GameManager.boon_fragments -= 1
	Inventory.remove_item("Boon Fragment", 1)
	_fragments_pending += 1
	_close_ui()
	_open_ui()

func _claim_boon() -> void:
	var kf_count := Inventory.get_item_count("Knowledge Fragment")
	if kf_count < CLAIM_KF_COST:
		GameManager.feedback_requested.emit("Need %d Knowledge Fragments." % CLAIM_KF_COST)
		return
	var available: Array = []
	for boon in BOONS:
		if not GameManager.has_boon(boon.id):
			available.append(boon.id)
	if available.is_empty():
		GameManager.feedback_requested.emit("All boons already claimed.")
		return
	Inventory.remove_item("Knowledge Fragment", CLAIM_KF_COST)
	_fragments_pending = 0
	var chosen: String = available[randi() % available.size()]
	GameManager.grant_boon(chosen)
	_close_ui()
	_open_ui()

func _build_panel() -> Node:
	var canvas := CanvasLayer.new()
	canvas.layer = 20

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240, -220)
	panel.size = Vector2(480, 240)
	canvas.add_child(panel)

	var title := Label.new()
	title.text = "— WORK STATION —"
	title.position = Vector2(0, 10)
	title.size = Vector2(480, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0, 1))
	panel.add_child(title)

	# Fragment inventory count
	var frag_lbl := Label.new()
	frag_lbl.name = "FragLbl"
	frag_lbl.text = "Boon Fragments in inventory: %d" % GameManager.boon_fragments
	frag_lbl.position = Vector2(0, 34)
	frag_lbl.size = Vector2(480, 16)
	frag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frag_lbl.add_theme_font_size_override("font_size", 9)
	frag_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1))
	panel.add_child(frag_lbl)

	# 4-quarter circle
	var BoonCircleScript := load("res://scripts/boon_circle.gd")
	var circle: Control = BoonCircleScript.new()
	circle.set("filled_quarters", _fragments_pending)
	var csize := 108.0  # 2 × RADIUS
	circle.anchor_left = 0.5
	circle.anchor_right = 0.5
	circle.anchor_top = 0.0
	circle.anchor_bottom = 0.0
	circle.offset_left  = -csize * 0.5
	circle.offset_right =  csize * 0.5
	circle.offset_top   = 56.0
	circle.offset_bottom = 56.0 + csize
	panel.add_child(circle)

	# Action button
	var can_claim := _fragments_pending >= FRAGMENT_COST
	var action_btn := Button.new()
	if can_claim:
		action_btn.text = "Claim Random Boon  (%d KF)" % CLAIM_KF_COST
		var kf_have := Inventory.get_item_count("Knowledge Fragment")
		action_btn.disabled = kf_have < CLAIM_KF_COST
		action_btn.pressed.connect(func(): _claim_boon())
	else:
		action_btn.text = "Place Boon Fragment  (%d → circle)" % _fragments_pending
		action_btn.disabled = GameManager.boon_fragments < 1
		action_btn.pressed.connect(func(): _place_fragment())
	action_btn.position = Vector2(90, 180)
	action_btn.size = Vector2(300, 30)
	panel.add_child(action_btn)

	var close_btn := Button.new()
	close_btn.text = "Close [ESC]"
	close_btn.position = Vector2(190, 208)
	close_btn.size = Vector2(100, 22)
	close_btn.pressed.connect(func(): _close_ui())
	panel.add_child(close_btn)

	var esc_catcher := Node.new()
	var esc_script := GDScript.new()
	esc_script.source_code = """
extends Node
var ws: Node = null
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		ws._close_ui()
"""
	esc_catcher.set_script(esc_script)
	esc_catcher.set("ws", self)
	canvas.add_child(esc_catcher)

	return canvas
