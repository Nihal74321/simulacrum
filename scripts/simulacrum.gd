extends Node2D

const ROOM_HALF: int = 10
const GREEN_ATLAS: Vector2i = Vector2i(4, 1)

const ENTRY_MSGS: Array[String] = [
	"What is this place?",
	"Where am I?",
	"I need to get out of here.",
]
static var _entry_index: int = 0

func _ready() -> void:
	get_viewport().physics_object_picking = true
	GameManager.dungeon_active = true
	GameManager.dungeon_over_requested.connect(_exit)
	GameManager.feedback_requested.emit(ENTRY_MSGS[_entry_index])
	_entry_index = (_entry_index + 1) % ENTRY_MSGS.size()
	_generate_floor()
	_add_boundary()

func _generate_floor() -> void:
	var tilemap := $TileMapLayer as TileMapLayer
	var cells := tilemap.get_used_cells()
	var source_id: int = 0
	if not cells.is_empty():
		source_id = tilemap.get_cell_source_id(cells[0])
	tilemap.clear()
	for x in range(-ROOM_HALF, ROOM_HALF + 1):
		for y in range(-ROOM_HALF, ROOM_HALF + 1):
			tilemap.set_cell(Vector2i(x, y), source_id, GREEN_ATLAS)

func _add_boundary() -> void:
	var tilemap := $TileMapLayer as TileMapLayer
	var walkable: Dictionary = {}
	for cell in tilemap.get_used_cells():
		walkable[cell] = true

	var border_body := StaticBody2D.new()
	add_child(border_body)

	var seen: Dictionary = {}
	for cell_v in walkable:
		var cell := cell_v as Vector2i
		for nb in [
			Vector2i(cell.x + 1, cell.y), Vector2i(cell.x - 1, cell.y),
			Vector2i(cell.x, cell.y + 1), Vector2i(cell.x, cell.y - 1),
		]:
			if walkable.has(nb) or seen.has(nb):
				continue
			seen[nb] = true
			var cs := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			circle.radius = 12.0
			cs.shape = circle
			cs.position = tilemap.to_global(tilemap.map_to_local(nb))
			border_body.add_child(cs)

func _exit() -> void:
	GameManager.dungeon_active = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")
