extends StaticBody2D

signal interacted(machine_name: String)

const INTERACTION_RANGE: float = 180.0
const HOVER_RADIUS: float = 40.0
const BODY_CENTER: Vector2 = Vector2(0.0, -12.0)
const OUTLINE_RECT: Rect2 = Rect2(-17, -25, 34, 26)
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const OUTLINE_WIDTH: float = 1.0
const LABEL_FADE_SPEED: float = 2.5
const SIM_IRON_PLATES_NEEDED: int = 5

@export var machine_name: String = "Machine"
@export var machine_color: Color = Color(0.35, 0.28, 0.18, 1)
@export var starts_broken: bool = true

var broken: bool = true
var _broken_msg_index: int = 0
var _broken_msgs: Array[String] = [
	"This is broken.",
	"I need to fix this.",
	"I can't use that yet.",
]
var _hovered: bool = false
var _label_alpha: float = 0.0

# Sim engine iteration GUI
var _sim_canvas: CanvasLayer = null
var _sim_panel: Panel = null
var _sim_open: bool = false

# Repair GUI (broken sim engine)
var _repair_canvas: CanvasLayer = null
var _repair_panel: Panel = null
var _repair_open: bool = false

@onready var mouse_area: Area2D = $MouseArea
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	add_to_group("machines")
	z_index = 10
	broken = starts_broken
	if GameManager.godmode:
		broken = false
	_update_visual()
	name_label.modulate.a = 0.0
	name_label.z_index = 20
	mouse_area.input_event.connect(_on_mouse_input)
	GameManager.godmode_changed.connect(_on_godmode_changed)
	if machine_name == "Simulacrum Engine":
		_build_repair_gui()
		_build_sim_gui()

func _build_sim_gui() -> void:
	_sim_canvas = CanvasLayer.new()
	_sim_canvas.layer = 8
	_sim_canvas.visible = false
	add_child(_sim_canvas)

	_sim_panel = Panel.new()
	_sim_panel.size = Vector2(220, 140)
	_sim_canvas.add_child(_sim_panel)

	var title := Label.new()
	title.text = "Simulacrum Engine"
	title.position = Vector2(8, 6)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
	_sim_panel.add_child(title)

	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 0.5)
	sep.position = Vector2(4, 22)
	sep.size = Vector2(212, 1)
	_sim_panel.add_child(sep)

	var iter_lbl := Label.new()
	iter_lbl.name = "IterLabel"
	iter_lbl.position = Vector2(8, 28)
	iter_lbl.add_theme_font_size_override("font_size", 9)
	_sim_panel.add_child(iter_lbl)

	var cost_lbl := Label.new()
	cost_lbl.name = "CostLabel"
	cost_lbl.position = Vector2(8, 48)
	cost_lbl.add_theme_font_size_override("font_size", 9)
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.3, 1.0))
	_sim_panel.add_child(cost_lbl)

	var kf_lbl := Label.new()
	kf_lbl.name = "KFLabel"
	kf_lbl.position = Vector2(8, 66)
	kf_lbl.add_theme_font_size_override("font_size", 9)
	kf_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	_sim_panel.add_child(kf_lbl)

	var run_btn := Button.new()
	run_btn.name = "RunBtn"
	run_btn.text = "Run Iteration"
	run_btn.position = Vector2(8, 86)
	run_btn.size = Vector2(110, 26)
	run_btn.pressed.connect(_run_sim_iteration)
	_sim_panel.add_child(run_btn)

	var close_hint := Label.new()
	close_hint.text = "[ ESC ] close"
	close_hint.position = Vector2(8, 116)
	close_hint.add_theme_font_size_override("font_size", 7)
	close_hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	_sim_panel.add_child(close_hint)

func _build_repair_gui() -> void:
	_repair_canvas = CanvasLayer.new()
	_repair_canvas.layer = 8
	_repair_canvas.visible = false
	add_child(_repair_canvas)

	_repair_panel = Panel.new()
	_repair_panel.size = Vector2(220, 130)
	_repair_canvas.add_child(_repair_panel)

	var title := Label.new()
	title.text = "Simulacrum Engine"
	title.position = Vector2(8, 6)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	_repair_panel.add_child(title)

	var sub := Label.new()
	sub.text = "[ BROKEN ]"
	sub.position = Vector2(8, 22)
	sub.add_theme_font_size_override("font_size", 8)
	sub.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3, 1.0))
	_repair_panel.add_child(sub)

	var sep := ColorRect.new()
	sep.color = Color(0.4, 0.4, 0.4, 0.5)
	sep.position = Vector2(4, 36)
	sep.size = Vector2(212, 1)
	_repair_panel.add_child(sep)

	var req := Label.new()
	req.text = "Requires: %d× Iron Plate" % SIM_IRON_PLATES_NEEDED
	req.position = Vector2(8, 42)
	req.add_theme_font_size_override("font_size", 9)
	_repair_panel.add_child(req)

	var have_lbl := Label.new()
	have_lbl.name = "HaveLabel"
	have_lbl.position = Vector2(8, 60)
	have_lbl.add_theme_font_size_override("font_size", 8)
	have_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	_repair_panel.add_child(have_lbl)

	var deposit_btn := Button.new()
	deposit_btn.name = "DepositBtn"
	deposit_btn.text = "Deposit Iron Plates"
	deposit_btn.position = Vector2(8, 80)
	deposit_btn.size = Vector2(160, 26)
	deposit_btn.pressed.connect(_try_repair)
	_repair_panel.add_child(deposit_btn)

	var hint := Label.new()
	hint.text = "[ ESC ] close"
	hint.position = Vector2(8, 110)
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	_repair_panel.add_child(hint)

func _refresh_repair_gui() -> void:
	if _repair_panel == null:
		return
	var plates := Inventory.get_item_count("Iron Plate")
	_repair_panel.get_node("HaveLabel").text = "You have: %d / %d" % [plates, SIM_IRON_PLATES_NEEDED]
	_repair_panel.get_node("DepositBtn").disabled = plates < SIM_IRON_PLATES_NEEDED

func _try_repair() -> void:
	var plates := Inventory.get_item_count("Iron Plate")
	if plates < SIM_IRON_PLATES_NEEDED:
		GameManager.feedback_requested.emit("Need %d Iron Plates." % SIM_IRON_PLATES_NEEDED)
		return
	Inventory.remove_item("Iron Plate", SIM_IRON_PLATES_NEEDED)
	broken = false
	_update_visual()
	_close_repair_gui()
	GameManager.feedback_requested.emit("Simulacrum Engine repaired!")
	GameManager.task_index = max(GameManager.task_index, 7)
	GameManager.secondary_task_changed.emit()

func _close_repair_gui() -> void:
	_repair_open = false
	if _repair_canvas != null:
		_repair_canvas.visible = false

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = (global_position + BODY_CENTER).distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(
		_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta,
		0.0, 1.0
	)
	name_label.modulate.a = _label_alpha

	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * global_position
	if _repair_open and _repair_panel != null:
		_repair_panel.position = screen_pos + Vector2(-110.0, -180.0)
		_refresh_repair_gui()
		var player2 := get_tree().get_first_node_in_group("player") as Node2D
		if player2 != null and global_position.distance_to(player2.global_position) > INTERACTION_RANGE + 30.0:
			_close_repair_gui()
	if _sim_open and _sim_panel != null:
		_sim_panel.position = screen_pos + Vector2(-110.0, -180.0)
		_refresh_sim_gui()
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) > INTERACTION_RANGE + 30.0:
			_close_sim_gui()

func _draw() -> void:
	if _hovered:
		draw_rect(OUTLINE_RECT, OUTLINE_COLOR, false, OUTLINE_WIDTH)

func _refresh_sim_gui() -> void:
	if _sim_panel == null:
		return
	var cost := GameManager.get_sim_cost()
	var kf := Inventory.get_item_count("Knowledge Fragment")
	_sim_panel.get_node("IterLabel").text = "Iterations run: %d" % GameManager.sim_iterations
	_sim_panel.get_node("CostLabel").text = "Next cost: %d KF" % cost
	_sim_panel.get_node("KFLabel").text = "Your KF: %d" % kf
	_sim_panel.get_node("RunBtn").disabled = kf < cost

func _run_sim_iteration() -> void:
	var cost := GameManager.get_sim_cost()
	if Inventory.get_item_count("Knowledge Fragment") < cost:
		GameManager.feedback_requested.emit("Not enough Knowledge Fragments.")
		return
	Inventory.remove_item("Knowledge Fragment", cost)
	GameManager.sim_iterations += 1
	GameManager.feedback_requested.emit("Entering Simulacrum iteration %d…" % GameManager.sim_iterations)
	_close_sim_gui()
	GameManager.dungeon_active = false
	get_tree().change_scene_to_file("res://scenes/dungeon.tscn")

func _close_sim_gui() -> void:
	_sim_open = false
	if _sim_canvas != null:
		_sim_canvas.visible = false

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return

	var click_pos: Vector2 = (event as InputEventMouseButton).position
	# Don't intercept clicks inside open panels
	if _repair_open and _repair_panel != null \
			and Rect2(_repair_panel.position, _repair_panel.size).has_point(click_pos):
		return
	if _sim_open and _sim_panel != null \
			and Rect2(_sim_panel.position, _sim_panel.size).has_point(click_pos):
		return

	if _v is Viewport:
		(_v as Viewport).set_input_as_handled()

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var dist: float = global_position.distance_to((player as Node2D).global_position)
	if dist > INTERACTION_RANGE:
		GameManager.feedback_requested.emit("Too far away.")
		return

	if broken:
		if machine_name == "Simulacrum Engine":
			GameManager.feedback_requested.emit(_broken_msgs[_broken_msg_index])
			_broken_msg_index = (_broken_msg_index + 1) % _broken_msgs.size()
			if _repair_open:
				_close_repair_gui()
			else:
				_repair_open = true
				if _repair_canvas != null:
					_repair_canvas.visible = true
					_refresh_repair_gui()
		else:
			GameManager.feedback_requested.emit(_broken_msgs[_broken_msg_index])
			_broken_msg_index = (_broken_msg_index + 1) % _broken_msgs.size()
	else:
		if machine_name == "Simulacrum Engine":
			if _sim_open:
				_close_sim_gui()
			else:
				_sim_open = true
				if _sim_canvas != null:
					_sim_canvas.visible = true
					_refresh_sim_gui()
		else:
			interacted.emit(machine_name)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _repair_open:
			_close_repair_gui()
			get_viewport().set_input_as_handled()
			return
		if _sim_open:
			_close_sim_gui()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		var click_pos: Vector2 = (event as InputEventMouseButton).position
		if _repair_open and _repair_panel != null \
				and not Rect2(_repair_panel.position, _repair_panel.size).has_point(click_pos):
			_close_repair_gui()
		if _sim_open and _sim_panel != null \
				and not Rect2(_sim_panel.position, _sim_panel.size).has_point(click_pos):
			_close_sim_gui()

func _on_godmode_changed(enabled: bool) -> void:
	if enabled and broken:
		broken = false
		_update_visual()

func _update_visual() -> void:
	if broken:
		$Body.color = machine_color.darkened(0.5)
		$NameLabel.text = machine_name + " [BROKEN]"
	else:
		$Body.color = machine_color
		$NameLabel.text = machine_name
