extends Node2D

# ── Constants ────────────────────────────────────────────────────────────────

const ROOM_HALF:   int  = 5    # room spans (2*ROOM_HALF+1)² tiles
const GRID_STEP:   int  = 14   # tile distance between room centres
const HALL_HALF:   int  = 1    # hallway is 3 tiles wide (centre ±1)

const ENEMY_SCENE:  PackedScene = preload("res://scenes/enemy.tscn")
const CHEST_SCRIPT               = preload("res://scripts/chest.gd")
const DUNGEON_ORE_SCRIPT         = preload("res://scripts/dungeon_ore.gd")

const ORE_TYPES: Array[Dictionary] = [
	{name="Iron Deposit",      color=Color(0.55, 0.55, 0.58)},
	{name="Copper Vein",       color=Color(0.80, 0.45, 0.20)},
	{name="Coal Seam",         color=Color(0.18, 0.18, 0.20)},
	{name="Crystal Formation", color=Color(0.30, 0.80, 0.90)},
	{name="Gold Seam",         color=Color(0.90, 0.78, 0.10)},
]

const ENTRY_MSGS: Array[String] = [
	"What is this place?",
	"Where am I?",
	"I need to get out of here.",
]
static var _entry_index: int = 0

# ── State ────────────────────────────────────────────────────────────────────

var rng := RandomNumberGenerator.new()
var tilemap: TileMapLayer
var _source_id: int  = 0
var _atlas: Vector2i = Vector2i(0, 0)

# {grid: Vector2i, type: String}
var _rooms: Array[Dictionary] = []
# pairs [Vector2i, Vector2i]
var _connections: Array[Array] = []

# ── Entry ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	get_viewport().physics_object_picking = true
	GameManager.dungeon_active = true
	GameManager.dungeon_over_requested.connect(_exit_dungeon)
	rng.randomize()
	tilemap = $TileMapLayer
	tilemap.add_to_group("tilemap")
	_sample_tileset()
	_generate()
	_add_vignette()
	# Place player at entry room centre
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		player.global_position = _tile_to_world(0, 0)
	GameManager.dungeon_explored_tiles.clear()
	GameManager.feedback_requested.emit(ENTRY_MSGS[_entry_index])
	_entry_index = (_entry_index + 1) % ENTRY_MSGS.size()

func _exit_dungeon() -> void:
	GameManager.dungeon_active = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or tilemap == null:
		return
	var player_cell := tilemap.local_to_map(tilemap.to_local(player.global_position))
	const EXPLORE_RADIUS: int = 7
	for dx in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
		for dy in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
			if dx * dx + dy * dy <= EXPLORE_RADIUS * EXPLORE_RADIUS:
				GameManager.dungeon_explored_tiles[player_cell + Vector2i(dx, dy)] = true

# ── Tile sampling ─────────────────────────────────────────────────────────────

func _sample_tileset() -> void:
	var cells := tilemap.get_used_cells()
	if not cells.is_empty():
		_source_id = tilemap.get_cell_source_id(cells[0])
	else:
		_source_id = 0
	_atlas = Vector2i(5, 1)  # dark gray tile (second to last in atlas)
	tilemap.clear()

# ── Generation ────────────────────────────────────────────────────────────────

func _generate() -> void:
	_place_rooms()
	_fill_tiles()
	_populate_rooms()
	_add_boundary()

func _add_boundary() -> void:
	var walkable: Dictionary = {}
	for cell in tilemap.get_used_cells():
		walkable[cell] = true

	# Single StaticBody2D — one collision circle per unique border tile
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
			# border_body is at origin (child of dungeon root at origin), so world pos == local pos
			cs.position = tilemap.to_global(tilemap.map_to_local(nb))
			border_body.add_child(cs)

func _place_rooms() -> void:
	var total_rooms := rng.randi_range(10, 30)
	var occupied: Dictionary = {}
	var frontier: Array[Vector2i] = []
	_rooms.append({grid = Vector2i(0, 0), type = "entry"})
	occupied[Vector2i(0, 0)] = true
	frontier.append(Vector2i(0, 0))

	while _rooms.size() < total_rooms and not frontier.is_empty():
		var fi  := rng.randi_range(0, frontier.size() - 1)
		var src := frontier[fi]
		var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		for i in range(dirs.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Vector2i = dirs[i]; dirs[i] = dirs[j]; dirs[j] = tmp

		var expanded := false
		for dir in dirs:
			var nb: Vector2i = src + dir
			if occupied.has(nb):
				continue
			occupied[nb] = true
			_rooms.append({grid = nb, type = _pick_room_type()})
			_connections.append([src, nb])
			frontier.append(nb)
			expanded = true
			if _rooms.size() >= total_rooms:
				break

		if not expanded:
			frontier.remove_at(fi)

	# Force the last room to be the exit
	if _rooms.size() > 1:
		_rooms[_rooms.size() - 1].type = "exit"

func _pick_room_type() -> String:
	var r := rng.randi_range(0, 99)
	if   r < 40: return "combat"
	elif r < 65: return "loot"
	elif r < 80: return "ores"
	else:        return "safe"

# ── Tile filling ──────────────────────────────────────────────────────────────

func _fill_tiles() -> void:
	for room in _rooms:
		_fill_room(room.grid)
	for conn in _connections:
		_fill_hallway(conn[0], conn[1])

func _fill_room(grid: Vector2i) -> void:
	var cx := grid.x * GRID_STEP
	var cy := grid.y * GRID_STEP
	for dx in range(-ROOM_HALF, ROOM_HALF + 1):
		for dy in range(-ROOM_HALF, ROOM_HALF + 1):
			tilemap.set_cell(Vector2i(cx + dx, cy + dy), _source_id, _atlas)

func _fill_hallway(a: Vector2i, b: Vector2i) -> void:
	var dir := b - a  # in grid units, one of the 4 cardinal directions
	var ax := a.x * GRID_STEP
	var ay := a.y * GRID_STEP
	var bx := b.x * GRID_STEP
	var by := b.y * GRID_STEP

	if dir.x != 0:
		var sx: int     = sign(dir.x) as int
		var x_start: int = ax + (ROOM_HALF + 1) * sx
		var x_end: int   = bx - (ROOM_HALF + 1) * sx
		var step: int    = sign(x_end - x_start) as int
		var tx: int      = x_start
		while tx != x_end + step:
			for dy in range(-HALL_HALF, HALL_HALF + 1):
				tilemap.set_cell(Vector2i(tx, ay + dy), _source_id, _atlas)
			tx += step
	else:
		var sy: int     = sign(dir.y) as int
		var y_start: int = ay + (ROOM_HALF + 1) * sy
		var y_end: int   = by - (ROOM_HALF + 1) * sy
		var step: int    = sign(y_end - y_start) as int
		var ty: int      = y_start
		while ty != y_end + step:
			for dx in range(-HALL_HALF, HALL_HALF + 1):
				tilemap.set_cell(Vector2i(ax + dx, ty), _source_id, _atlas)
			ty += step

# ── Population ────────────────────────────────────────────────────────────────

func _populate_rooms() -> void:
	for room in _rooms:
		match room.type:
			"combat": _spawn_enemies(room.grid)
			"loot":   _spawn_chests(room.grid)
			"ores":   _spawn_ores(room.grid)
			"exit":   _spawn_exit(room.grid)

func _spawn_enemies(grid: Vector2i) -> void:
	var count := rng.randi_range(2, 5)
	for _i in count:
		var enemy: Node2D = ENEMY_SCENE.instantiate()
		enemy.position = _random_room_world(grid)
		add_child(enemy)

func _spawn_chests(grid: Vector2i) -> void:
	var count := rng.randi_range(5, 9)
	var cx := grid.x * GRID_STEP
	var cy := grid.y * GRID_STEP
	var corner_offset: int = ROOM_HALF - 1
	# 4 corners; distribute chests across them
	var corners: Array[Vector2i] = [
		Vector2i(cx - corner_offset, cy - corner_offset),
		Vector2i(cx + corner_offset, cy - corner_offset),
		Vector2i(cx - corner_offset, cy + corner_offset),
		Vector2i(cx + corner_offset, cy + corner_offset),
	]
	for i in count:
		var corner := corners[i % corners.size()]
		var jitter_x := rng.randi_range(-1, 1)
		var jitter_y := rng.randi_range(-1, 1)
		var chest: Node2D = CHEST_SCRIPT.new()
		chest.position = _tile_to_world(corner.x + jitter_x, corner.y + jitter_y)
		add_child(chest)

func _spawn_ores(grid: Vector2i) -> void:
	var count := rng.randi_range(8, 15)
	var placed: Array[Vector2] = []
	for _i in count:
		var ore_type: Dictionary = ORE_TYPES[rng.randi_range(0, ORE_TYPES.size() - 1)]
		var pos := _random_room_world(grid, placed)
		placed.append(pos)
		var ore: Node2D = DUNGEON_ORE_SCRIPT.new()
		ore.set("ore_name", ore_type.name)
		ore.set("ore_color", ore_type.color)
		ore.position = pos
		add_child(ore)


func _spawn_exit(grid: Vector2i) -> void:
	var world_pos := _tile_to_world(grid.x * GRID_STEP, grid.y * GRID_STEP)

	# Trigger area — auto-exits when player steps on it
	var trigger := Area2D.new()
	trigger.collision_layer = 0
	trigger.collision_mask  = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	shape.shape = circle
	trigger.add_child(shape)
	trigger.position = world_pos
	trigger.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			GameManager.dungeon_active = false
			get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	add_child(trigger)

	# Visual: glowing green portal ring
	var gfx := Node2D.new()
	gfx.position = world_pos
	gfx.z_index = 8
	var script := GDScript.new()
	script.source_code = """
extends Node2D
var _t: float = 0.0
func _process(delta):
    _t += delta
    queue_redraw()
func _draw():
    var pulse = 0.65 + sin(_t * 3.0) * 0.35
    draw_arc(Vector2.ZERO, 22.0, 0, TAU, 32, Color(0.2, 1.0, 0.4, pulse), 3.0)
    draw_circle(Vector2.ZERO, 14.0, Color(0.15, 0.9, 0.3, pulse * 0.35))
"""
	gfx.set_script(script)
	add_child(gfx)

	var lbl := Label.new()
	lbl.text = "EXIT"
	lbl.position = world_pos + Vector2(-12, -38)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 1))
	lbl.z_index = 20
	add_child(lbl)

func _add_vignette() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
    vec2 uv = UV - vec2(0.5);
    float d = length(uv * vec2(1.6, 2.0));
    float v = smoothstep(0.35, 0.85, d);
    COLOR = vec4(0.0, 0.0, 0.0, v * 0.45);
}
"""
	mat.shader = shader
	cr.material = mat
	canvas.add_child(cr)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _tile_to_world(tx: int, ty: int) -> Vector2:
	return tilemap.to_global(tilemap.map_to_local(Vector2i(tx, ty)))

func _random_room_world(grid: Vector2i, avoid: Array[Vector2] = []) -> Vector2:
	var cx := grid.x * GRID_STEP
	var cy := grid.y * GRID_STEP
	for _attempt in 20:
		var dx := rng.randi_range(-(ROOM_HALF - 1), ROOM_HALF - 1)
		var dy := rng.randi_range(-(ROOM_HALF - 1), ROOM_HALF - 1)
		var pos := _tile_to_world(cx + dx, cy + dy)
		var ok := true
		for other in avoid:
			if pos.distance_to(other) < 30.0:
				ok = false
				break
		if ok:
			return pos
	return _tile_to_world(cx, cy)
