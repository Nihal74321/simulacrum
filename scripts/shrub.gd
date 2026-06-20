extends Node2D

const PLANT_TEXTURES: Array[String] = [
	"res://asset-holder/Monsterra/256x256/Monsterra_0001.png",
	"res://asset-holder/PalmBush/256x256/PalmBush_Body_0001.png",
	"res://asset-holder/PalmSmall/256x256/PalmSmall_0001.png",
]

const MAX_DISPLAY_HEIGHT: float = 48.0
const OCCLUDE_RADIUS: float = 40.0
const BASE_Z: int = 4

func _ready() -> void:
	z_index = 4

	var path: String = PLANT_TEXTURES[randi() % PLANT_TEXTURES.size()]
	var tex: Texture2D = load(path)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	var native_h: float = float(tex.get_height())
	# Only scale down if taller than max; otherwise use native size
	var s: float = min(1.0, MAX_DISPLAY_HEIGHT / native_h) if native_h > 0 else 1.0
	sprite.scale = Vector2(s, s)
	sprite.offset = Vector2(0, -native_h * 0.5)
	add_child(sprite)

	add_to_group("shrubs")

func _process(_delta: float) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		var dist := global_position.distance_to(player.global_position)
		var in_front := player.global_position.y > global_position.y - 6.0
		var occluding := dist < OCCLUDE_RADIUS and in_front
		z_index = -1 if occluding else BASE_Z
		modulate.a = 0.3 if occluding else 1.0
	else:
		z_index = BASE_Z
		modulate.a = 1.0
