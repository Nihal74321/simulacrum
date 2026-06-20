extends Node2D

const HOVER_RADIUS: float = 18.0
const INTERACTION_RANGE: float = 80.0
const OUTLINE_COLOR: Color = Color(1, 0.85, 0, 1)
const LABEL_FADE_SPEED: float = 2.5

const TREE_TEXTURES: Array[String] = [
	"res://assets/trees/tree_01.png",
	"res://assets/trees/tree_02.png",
	"res://assets/trees/tree_05.png",
	"res://assets/trees/tree_08.png",
	"res://assets/trees/tree_09.png",
	"res://assets/trees/tree_11.png",
	"res://assets/trees/tree_12.png",
]

# Display height in pixels — tweak to taste
const DISPLAY_HEIGHT: float = 72.0
# Radius within which tree drops behind player + fades.
# 80px ≈ tree half-height + 1 tile buffer so canopy never buries the player.
const OCCLUDE_RADIUS: float = 80.0
const BASE_Z: int = 10

var _hovered: bool = false
var _label: Label
var _label_alpha: float = 0.0

func _ready() -> void:
	z_index = 10
	add_to_group("trees")

	var path: String = TREE_TEXTURES[randi() % TREE_TEXTURES.size()]
	var tex: Texture2D = load(path)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	var native_h: float = float(tex.get_height())
	var s: float = DISPLAY_HEIGHT / native_h if native_h > 0 else 1.0
	sprite.scale = Vector2(s, s)
	# Offset so sprite sits with its base at the tile centre
	sprite.offset = Vector2(0, -native_h * 0.5)
	add_child(sprite)

	_label = Label.new()
	_label.text = "Tree"
	_label.position = Vector2(-14, -(DISPLAY_HEIGHT + 4.0))
	_label.add_theme_font_size_override("font_size", 7)
	_label.modulate.a = 0.0
	_label.z_index = 20
	add_child(_label)

	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.input_pickable = true
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HOVER_RADIUS
	cs.shape = circle
	cs.position = Vector2(0, -12)
	area.add_child(cs)
	add_child(area)
	area.input_event.connect(_on_mouse_input)

func _process(delta: float) -> void:
	var was := _hovered
	_hovered = global_position.distance_to(get_global_mouse_position()) < HOVER_RADIUS
	if _hovered != was:
		queue_redraw()
	_label_alpha = clampf(_label_alpha + (1.0 if _hovered else -1.0) * LABEL_FADE_SPEED * delta, 0.0, 1.0)
	_label.modulate.a = _label_alpha
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		var dist := global_position.distance_to(player.global_position)
		# "In front" = player Y is at or below the tree anchor (player is south of the tree)
		var in_front := player.global_position.y > global_position.y - 8.0
		var occluding := dist < OCCLUDE_RADIUS and in_front
		# Drop behind player so they're never buried under the sprite
		z_index = -1 if occluding else BASE_Z
		modulate.a = 0.25 if occluding else 1.0
	else:
		z_index = BASE_Z
		modulate.a = 1.0

func _draw() -> void:
	if _hovered:
		draw_arc(Vector2(0, -12), 15.0, 0, TAU, 16, OUTLINE_COLOR, 1.0)

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
	if GameManager.hotbar[GameManager.hotbar_selected] != "Axe":
		var msgs := ["I can't do that.", "Not now.", "I need a tool."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])
		return

	var logs := randi_range(5, 10)
	Inventory.add_item({"name": "Log", "description": "Cut from a tree.", "quantity": logs})
	GameManager.item_picked_up.emit("Log", logs)
	queue_free()
