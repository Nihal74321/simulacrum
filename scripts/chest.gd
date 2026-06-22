extends Node2D

const HOVER_RADIUS: float = 24.0
const INTERACTION_RANGE: float = 80.0
const OUTLINE_RECT: Rect2 = Rect2(-22, -36, 44, 34)
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const OUTLINE_WIDTH: float = 1.5
const LABEL_FADE_SPEED: float = 2.5

# Chest art — Large_Open_Empty: 1024×1024, 4×4 = 16 frames.
# Frame 0 = lid fully closed, frame 15 = fully open. Animate 0→15 to open.
const CHEST_TEX: Texture2D = preload("res://asset-holder/Chests/Chests_Spritesheets/x256p_Spritesheets/Large_Open_Empty/Large_Open_Empty_Body_270.png")
const CHEST_HFRAMES: int = 4
const CHEST_VFRAMES: int = 4   # 16 frames
const CLOSED_FRAME: int = 0    # lid fully closed
const OPEN_END_FRAME: int = 15 # fully open
const OPEN_FPS: float = 18.0
const CHEST_SCALE: float = 0.2

const T1_ORES: Array = ["Iron Ore", "Copper Ore", "Gold Ore", "Aluminium Ore", "Tin Ore", "Lead Ore", "Manganese Ore"]
const T2_ORES: Array = ["Neodymium Ore", "Cerium Ore", "Lanthanum Ore", "Yttrium Ore", "Dysprosium Ore"]

var _opened: bool = false
var _hovered: bool = false
var _label_alpha: float = 0.0
var _label: Label
var _sprite: Sprite2D

# Open-animation state
var _opening: bool = false
var _open_frame: int = 0
var _open_anim_t: float = 0.0
var _free_after_open: bool = false

func _ready() -> void:
	z_index = 10
	_sprite = Sprite2D.new()
	_sprite.texture = CHEST_TEX
	_sprite.hframes = CHEST_HFRAMES
	_sprite.vframes = CHEST_VFRAMES
	_sprite.frame = CLOSED_FRAME
	_sprite.scale = Vector2(CHEST_SCALE, CHEST_SCALE)
	_sprite.position = Vector2(-5, -14)
	add_child(_sprite)

	_label = Label.new()
	_label.text = "Chest"
	_label.position = Vector2(-18, -42)
	_label.add_theme_font_size_override("font_size", 7)
	_label.modulate.a = 0.0
	_label.z_index = 20
	add_child(_label)

	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 26)
	cs.shape = rect
	cs.position = Vector2(0, -14)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)
	add_to_group("chests")

func _process(delta: float) -> void:
	if _opening:
		_open_anim_t += delta
		if _open_anim_t >= 1.0 / OPEN_FPS:
			_open_anim_t = fmod(_open_anim_t, 1.0 / OPEN_FPS)
			if _open_frame < OPEN_END_FRAME:
				_open_frame += 1
				_sprite.frame = _open_frame
			else:
				_opening = false
				if _free_after_open:
					queue_free()
		return

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
		draw_rect(OUTLINE_RECT, OUTLINE_COLOR, false, OUTLINE_WIDTH)

func _play_open_anim(free_after: bool) -> void:
	_opened = true
	_opening = true
	_open_frame = CLOSED_FRAME
	_open_anim_t = 0.0
	_free_after_open = free_after
	_label.modulate.a = 0.0
	_sprite.frame = CLOSED_FRAME

func _on_mouse_input(_v: Node, event: InputEvent, _shape: int) -> void:
	if not (event is InputEventMouseButton
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
			and (event as InputEventMouseButton).pressed):
		return
	if _v is Viewport:
		(_v as Viewport).set_input_as_handled()

	if _opened:
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to((player as Node2D).global_position) > INTERACTION_RANGE:
		GameManager.feedback_requested.emit("Too far away.")
		return

	# Dummy chests (trapped rooms): nothing inside — they vanish when checked
	if get_meta("dummy", false):
		GameManager.feedback_requested.emit("... Nothing inside.")
		_play_open_anim(true)
		return

	if GameManager.hotbar[GameManager.hotbar_selected] != "Sickle":
		var msgs := ["I can't do that.", "Not now.", "I need a tool."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])
		return

	var kf_min: int = get_meta("reward_kf_min", 100)
	var kf_max: int = get_meta("reward_kf_max", 250)
	var guaranteed_boon: bool = get_meta("reward_guaranteed_boon", false)
	_open_chest(kf_min, kf_max, guaranteed_boon)
	_play_open_anim(true)

func _open_chest(kf_min: int = 200, kf_max: int = 500, guaranteed_boon: bool = false) -> void:
	# Always award KF plus 3-5 item rolls (each roll independent, duplicates allowed).
	var kf := randi_range(kf_min, kf_max)
	Inventory.add_item({"name": "Knowledge Fragment", "description": "Crystallised memory from a slain simulacrum.", "quantity": kf})
	GameManager.item_picked_up.emit("Knowledge Fragment", kf)

	if guaranteed_boon:
		GameManager.boon_fragments += 1
		Inventory.add_item({"name": "Boon Fragment", "description": "A shard of condensed potential.", "quantity": 1})
		GameManager.item_picked_up.emit("Boon Fragment", 1)

	var rolls := randi_range(3, 5)
	for _i in rolls:
		_roll_one_item()

func _roll_one_item() -> void:
	# roll 0-99: 0 = legendary, 1-5 = rare, 6-15 = uncommon, 16+ = common
	var roll := randi_range(0, 99)

	if roll < 1:
		# Legendary: Boon Fragment
		GameManager.boon_fragments += 1
		Inventory.add_item({"name": "Boon Fragment", "description": "A shard of condensed potential.", "quantity": 1})
		GameManager.item_picked_up.emit("Boon Fragment", 1)
	elif roll < 6:
		# Rare: T2 ore
		var ore: String = T2_ORES[randi() % T2_ORES.size()]
		var qty := randi_range(1, 3)
		Inventory.add_item({"name": ore, "description": "Rare earth ore.", "quantity": qty})
		GameManager.item_picked_up.emit(ore, qty)
	elif roll < 16:
		# Uncommon: T1 ore small or String
		if randi() % 3 == 0:
			var qty := randi_range(2, 4)
			Inventory.add_item({"name": "String", "description": "Fibrous cord.", "quantity": qty})
			GameManager.item_picked_up.emit("String", qty)
		else:
			var ore: String = T1_ORES[randi() % T1_ORES.size()]
			var qty := randi_range(5, 10)
			Inventory.add_item({"name": ore, "description": "Ore.", "quantity": qty})
			GameManager.item_picked_up.emit(ore, qty)
	else:
		# Common: iron plates, big T1 ore haul, or Healing Vial
		var r2 := randi() % 3
		if r2 == 0:
			var qty := randi_range(1, 4)
			Inventory.add_item({"name": "Iron Plate", "description": "Smelted iron.", "quantity": qty})
			GameManager.item_picked_up.emit("Iron Plate", qty)
		elif r2 == 1:
			var ore: String = T1_ORES[randi() % T1_ORES.size()]
			var qty := randi_range(20, 50)
			Inventory.add_item({"name": ore, "description": "Ore.", "quantity": qty})
			GameManager.item_picked_up.emit(ore, qty)
		else:
			var qty := randi_range(1, 3)
			Inventory.add_item({"name": "Healing Vial", "description": "Restores 30 HP. Press F to use.", "quantity": qty})
			GameManager.item_picked_up.emit("Healing Vial", qty)
