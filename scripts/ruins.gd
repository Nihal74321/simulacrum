extends Node2D

const TRIGGER_RADIUS: float = 120.0
const CHEST_SCRIPT = preload("res://scripts/ruins_chest.gd")

const T1_ORES: Array = ["Iron Ore", "Copper Ore", "Gold Ore", "Aluminium Ore", "Tin Ore", "Lead Ore", "Manganese Ore"]
const T2_ORES: Array = ["Neodymium Ore", "Cerium Ore", "Lanthanum Ore", "Yttrium Ore", "Dysprosium Ore"]
const WEAPONS_DROP: Array = ["Pickaxe", "Axe", "Sickle", "Broadaxe"]

var _subtitle_shown: bool = false

func _ready() -> void:
	z_index = 5
	_build_visual()
	_spawn_chests()

func _build_visual() -> void:
	# Scattered stone blocks to suggest ruins
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var block_col := Color(0.55, 0.50, 0.40, 1)
	var broken_col := Color(0.45, 0.40, 0.32, 1)
	var positions: Array[Vector2] = [
		Vector2(-28, -12), Vector2(28, -12), Vector2(0, -24),
		Vector2(-40, 4),  Vector2(40, 4),
		Vector2(-18, 8),  Vector2(22, 10),  Vector2(-6, 18),
	]
	for p in positions:
		if rng.randf() < 0.3:
			continue
		var block := Polygon2D.new()
		var w: float = rng.randf_range(6, 14)
		var h: float = rng.randf_range(5, 10)
		block.polygon = PackedVector2Array([
			Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0),
			Vector2(w * 0.5, -h), Vector2(-w * 0.5, -h),
		])
		block.color = block_col if rng.randf() > 0.4 else broken_col
		block.position = p + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		add_child(block)

func _spawn_chests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := rng.randi_range(1, 5)
	var spread: float = 44.0
	for _i in count:
		var chest := CHEST_SCRIPT.new()
		chest.position = Vector2(
			rng.randf_range(-spread, spread),
			rng.randf_range(-spread * 0.5, spread * 0.5),
		)
		add_child(chest)

func _process(_delta: float) -> void:
	if _subtitle_shown:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to((player as Node2D).global_position) <= TRIGGER_RADIUS:
		_subtitle_shown = true
		var msgs := ["This looks abandoned.", "Someone must have been here."]
		GameManager.feedback_requested.emit(msgs[randi() % msgs.size()])
