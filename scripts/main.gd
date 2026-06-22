extends Node2D

const PORTAL_SCENE: PackedScene     = preload("res://scenes/dungeon_portal.tscn")
const TREE_SCRIPT                    = preload("res://scripts/tree.gd")
const LOG_ITEM_SCRIPT                = preload("res://scripts/log_item.gd")
const ROCK_PILE_SCRIPT               = preload("res://scripts/rock_pile.gd")
const STONE_SCRIPT                   = preload("res://scripts/stone.gd")
const SHRUB_SCRIPT                   = preload("res://scripts/shrub.gd")
const LOG_PILE_SCRIPT                = preload("res://scripts/log_pile.gd")
const CRAFTING_UI_SCRIPT             = preload("res://scripts/crafting_ui.gd")
const GEOTHERMAL_VENT_SCRIPT         = preload("res://scripts/geothermal_vent.gd")
const FORGE_SCRIPT                   = preload("res://scripts/forge.gd")
const ANVIL_SCRIPT                   = preload("res://scripts/anvil.gd")

const GRASS_TILE_A: Vector2i = Vector2i(0, 0)   # primary grass
const GRASS_TILE_B: Vector2i = Vector2i(5, 0)   # grass variant — earthy, near dirt end of atlas
const DIRT_TILE:    Vector2i = Vector2i(6, 0)   # brown dirt (minority patches)
const WATER_TILE:   Vector2i = Vector2i(0, 1)
const ASH_TILE:     Vector2i = Vector2i(5, 1)   # dark gray ash around geothermal vents
const WORLD_SEED: int = 42
const HALF_SIZE: int = 75
const VENT_ASH_RADIUS: int = 5

const PLACE_FAIL_MSGS: Array[String] = [
	"Not there.",
	"I need to find another place.",
	"That should go somewhere else.",
]

var rng := RandomNumberGenerator.new()
var tilemap: TileMapLayer
var _source_id: int = 0
var _atlas_coords: Vector2i = Vector2i(0, 0)
var _crafting_ui: CanvasLayer = null
var _vent_tile_coords: Array[Vector2i] = []
var _water_centers: Array[Vector2i] = []  # pool centres for path routing
var _water_cells: Dictionary = {}          # Vector2i → true, used instead of tilemap atlas for logic
var _path_cells: Dictionary = {}           # Vector2i → true
var _keyed_mat: ShaderMaterial = null     # shared ff00ff-discard material

var _placing_machine: String = ""
var _place_ghost: Node2D = null
var _place_fail_idx: int = 0

func _is_water_cell(cell: Vector2i) -> bool:
	return _water_cells.has(cell)

func _ready() -> void:
	get_viewport().physics_object_picking = true
	add_to_group("main_world")
	GameManager.dungeon_new_requested.connect(_on_dungeon_new)
	GameManager.dungeon_free_requested.connect(_on_dungeon_free)
	tilemap = $TileMapLayer
	tilemap.add_to_group("tilemap")
	rng.seed = WORLD_SEED
	_generate_world()
	call_deferred("_connect_machines")
	call_deferred("_restore_placed_machines")
	GameManager.placement_requested.connect(_enter_placement_mode)

func _connect_machines() -> void:
	for machine in get_tree().get_nodes_in_group("machines"):
		if not machine.interacted.is_connected(_on_machine_interacted):
			machine.interacted.connect(_on_machine_interacted)

func _on_machine_interacted(machine_name: String) -> void:
	match machine_name:
		"Simulacrum Engine":
			GameManager.task_index = max(GameManager.task_index, 4)
			get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
		"Crafting Bench":
			GameManager.task_index = max(GameManager.task_index, 1)
			if _crafting_ui == null:
				_crafting_ui = CRAFTING_UI_SCRIPT.new()
				add_child(_crafting_ui)
			_crafting_ui.open()
		"Loot Bag Generator":
			GameManager.feedback_requested.emit("[Loot Bag Generator] Not yet built.")
		"Extrusion Machine":
			GameManager.feedback_requested.emit("[Extrusion Machine] Not yet built.")
		_:
			GameManager.feedback_requested.emit("[%s] Coming soon." % machine_name)

# ── Machine placement ─────────────────────────────────────────────────────────

func _restore_placed_machines() -> void:
	for entry in GameManager.placed_machines:
		var machine: Node2D
		match str(entry.get("type", "")):
			"Forge":
				machine = FORGE_SCRIPT.new()
			"Anvil":
				machine = ANVIL_SCRIPT.new()
			"Work Station":
				machine = load("res://scripts/workstation.gd").new()
			_:
				continue
		machine.global_position = entry.get("pos", Vector2.ZERO)
		add_child(machine)

func _enter_placement_mode(machine_name: String) -> void:
	_placing_machine = machine_name
	_place_ghost = Node2D.new()
	var ghost_color := Color(0.5, 0.8, 1.0, 0.45)
	match machine_name:
		"Forge":
			ghost_color = Color(0.85, 0.45, 0.1, 0.45)
		"Anvil":
			ghost_color = Color(0.55, 0.55, 0.65, 0.45)
		"Extrusion Machine":
			ghost_color = Color(0.3, 0.6, 0.9, 0.45)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-24, -24), Vector2(24, -24),
		Vector2(24, 24),   Vector2(-24, 24),
	])
	poly.color = ghost_color
	_place_ghost.add_child(poly)
	_place_ghost.z_index = 20
	add_child(_place_ghost)
	GameManager.feedback_requested.emit("Click to place %s. [ESC] cancel." % machine_name)

func _process(_delta: float) -> void:
	if _place_ghost != null:
		_place_ghost.global_position = get_global_mouse_position()

func _unhandled_input(event: InputEvent) -> void:
	if _placing_machine.is_empty():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE \
			and (event as InputEventKey).pressed:
		_cancel_placement()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		var world_pos := get_global_mouse_position()
		if _is_valid_placement(world_pos):
			_place_machine(world_pos)
		else:
			GameManager.feedback_requested.emit(PLACE_FAIL_MSGS[_place_fail_idx])
			_place_fail_idx = (_place_fail_idx + 1) % PLACE_FAIL_MSGS.size()
		get_viewport().set_input_as_handled()

func _cancel_placement() -> void:
	if _place_ghost != null:
		_place_ghost.queue_free()
		_place_ghost = null
	_placing_machine = ""
	GameManager.feedback_requested.emit("Placement cancelled.")

func _is_valid_placement(world_pos: Vector2) -> bool:
	var tile_pos := tilemap.local_to_map(tilemap.to_local(world_pos))
	if _water_cells.has(tile_pos):
		return false
	for machine in get_tree().get_nodes_in_group("machines"):
		if (machine as Node2D).global_position.distance_to(world_pos) < 60.0:
			return false
	for forge in get_tree().get_nodes_in_group("forges"):
		if (forge as Node2D).global_position.distance_to(world_pos) < 60.0:
			return false
	for anvil in get_tree().get_nodes_in_group("anvils"):
		if (anvil as Node2D).global_position.distance_to(world_pos) < 60.0:
			return false
	return true

func _place_machine(world_pos: Vector2) -> void:
	# Remove objects in a small radius at placement spot
	var clear_radius := 40.0
	for child in get_children():
		if child is Node2D:
			var n2d := child as Node2D
			if n2d.global_position.distance_to(world_pos) < clear_radius \
					and (n2d.is_in_group("trees") or n2d.is_in_group("shrubs")
					or n2d.is_in_group("logs") or n2d.is_in_group("rock_piles")
					or n2d.is_in_group("stones") or n2d.is_in_group("log_piles")):
				n2d.queue_free()

	var machine: Node2D
	match _placing_machine:
		"Forge":
			machine = FORGE_SCRIPT.new()
		"Anvil":
			machine = ANVIL_SCRIPT.new()
		"Work Station":
			machine = load("res://scripts/workstation.gd").new()
		_:
			machine = Node2D.new()
			var lbl := Label.new()
			lbl.text = _placing_machine
			lbl.add_theme_font_size_override("font_size", 8)
			machine.add_child(lbl)
	machine.global_position = world_pos
	add_child(machine)
	GameManager.placed_machines.append({type = _placing_machine, pos = world_pos})

	if _place_ghost != null:
		_place_ghost.queue_free()
		_place_ghost = null
	GameManager.feedback_requested.emit("%s placed." % _placing_machine)
	_placing_machine = ""

# ── World generation ──────────────────────────────────────────────────────────

func _generate_world() -> void:
	var cells := tilemap.get_used_cells()
	if cells.is_empty():
		return
	var sample := cells[0]
	_source_id    = tilemap.get_cell_source_id(sample)
	_atlas_coords = DIRT_TILE

	tilemap.clear()
	_build_grass_layer()
	_place_water_pools()

	_vent_tile_coords.clear()
	_generate_pois()
	_apply_vent_ash()
	_spawn_trees()
	_spawn_shrubs()
	_spawn_ground_logs()
	_spawn_rock_piles()
	_spawn_stones()
	_spawn_log_piles()
	_add_boundary()
	_spawn_vent_nodes()
	_place_motivated_paths()
	_add_water_visuals()

func _generate_pois() -> void:
	# Vents are placed FIRST so every other POI/scatter can avoid their ash tiles.
	var poi_types: Array[Dictionary] = [
		{name="Geothermal Vent",   color=Color(0.90, 0.35, 0.10),  count=5, cluster=3},
		{name="Iron Deposit",      color=Color(0.55, 0.55, 0.58),  count=5, cluster=6},
		{name="Copper Vein",       color=Color(0.80, 0.45, 0.20),  count=4, cluster=5},
		{name="Coal Seam",         color=Color(0.18, 0.18, 0.20),  count=8, cluster=8},
		{name="Crystal Formation", color=Color(0.30, 0.80, 0.90),  count=3, cluster=4},
		{name="Gold Seam",         color=Color(0.90, 0.78, 0.10),  count=3, cluster=3},
	]
	for poi in poi_types:
		for _i in poi.count:
			_spawn_poi(poi)
	# Ruins: 2-3 per world
	var ruins_count := rng.randi_range(2, 3)
	for _r in ruins_count:
		_spawn_poi({name="Ruins", color=Color(0.60, 0.55, 0.40), count=1, cluster=1})

func _spawn_poi(poi: Dictionary) -> void:
	var tx: int
	var ty: int
	var is_vent: bool = poi.name == "Geothermal Vent"
	for _attempt in 20:
		tx = rng.randi_range(-HALF_SIZE + 5, HALF_SIZE - 5)
		ty = rng.randi_range(-HALF_SIZE + 5, HALF_SIZE - 5)
		# Non-vent POIs must not land on a vent's ash field
		if not is_vent and _near_vent(tx, ty):
			continue
		if abs(tx) > 25 or abs(ty) > 25:
			break

	var world_pos: Vector2 = tilemap.to_global(tilemap.map_to_local(Vector2i(tx, ty)))

	if poi.name == "Ruins":
		var ruins: Node2D = load("res://scripts/ruins.gd").new()
		ruins.global_position = world_pos
		ruins.name = "Ruins_%d_%d" % [tx, ty]
		call_deferred("add_child", ruins)
		return

	if poi.name == "Geothermal Vent":
		# Consume cluster RNG to keep other POI positions stable; defer node spawn
		var cluster_count: int = rng.randi_range(max(1, poi.cluster - 2), poi.cluster + 4)
		for _j in cluster_count:
			rng.randf_range(3.0, 10.0)
			rng.randf_range(3.0, 13.0)
			rng.randf_range(-18.0, 18.0)
			rng.randf_range(-18.0, 18.0)
			rng.randf_range(-0.06, 0.06)
		_vent_tile_coords.append(Vector2i(tx, ty))
		return

	var root: Node2D = load("res://scripts/poi.gd").new()
	root.global_position = world_pos
	root.name = poi.name.replace(" ", "") + "_%d_%d" % [tx, ty]
	root.set_meta("poi_color", poi.color as Color)

	var cluster_count: int = rng.randi_range(max(1, poi.cluster - 2), poi.cluster + 4)
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for _j in cluster_count:
		var block := Polygon2D.new()
		var w: float = rng.randf_range(3.0, 10.0)
		var h: float = rng.randf_range(3.0, 13.0)
		var ox: float = rng.randf_range(-18.0, 18.0)
		var oy: float = rng.randf_range(-18.0, 18.0)
		block.polygon = PackedVector2Array([
			Vector2(ox - w, oy - h), Vector2(ox + w, oy - h),
			Vector2(ox + w, oy + h), Vector2(ox - w, oy + h),
		])
		var v: float = rng.randf_range(-0.06, 0.06)
		block.color = (poi.color as Color) + Color(v, v, v, 0.0)
		root.add_child(block)
		min_pt = Vector2(min(min_pt.x, ox - w), min(min_pt.y, oy - h))
		max_pt = Vector2(max(max_pt.x, ox + w), max(max_pt.y, oy + h))

	if min_pt.x == INF:
		min_pt = Vector2(-18, -18)
		max_pt = Vector2(18, 18)

	var lbl := Label.new()
	lbl.text = poi.name
	lbl.position = Vector2(-32.0, -26.0)
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.modulate.a = 0.0
	root.add_child(lbl)

	root.setup(poi.name, Rect2(min_pt, max_pt - min_pt), lbl)
	add_child(root)
	root.add_to_group("pois")

func _near_vent(tx: int, ty: int) -> bool:
	for vtc in _vent_tile_coords:
		var dx := tx - vtc.x
		var dy := ty - vtc.y
		if dx * dx + dy * dy <= VENT_ASH_RADIUS * VENT_ASH_RADIUS:
			return true
	return false

func _apply_vent_ash() -> void:
	for vtc: Vector2i in _vent_tile_coords:
		for dx in range(-VENT_ASH_RADIUS, VENT_ASH_RADIUS + 1):
			for dy in range(-VENT_ASH_RADIUS, VENT_ASH_RADIUS + 1):
				if dx * dx + dy * dy <= VENT_ASH_RADIUS * VENT_ASH_RADIUS:
					var cell := vtc + Vector2i(dx, dy)
					if abs(cell.x) <= HALF_SIZE and abs(cell.y) <= HALF_SIZE:
						tilemap.set_cell(cell, _source_id, ASH_TILE)

func _spawn_vent_nodes() -> void:
	for vtc: Vector2i in _vent_tile_coords:
		var world_pos: Vector2 = tilemap.to_global(tilemap.map_to_local(vtc))
		var vent: Node2D = GEOTHERMAL_VENT_SCRIPT.new()
		vent.position = world_pos
		add_child(vent)

func _make_keyed_material() -> ShaderMaterial:
	if _keyed_mat != null:
		return _keyed_mat
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tif (c.r > 0.7 && c.g < 0.3 && c.b > 0.7) { discard; }\n\tCOLOR = c;\n}\n"
	_keyed_mat = ShaderMaterial.new()
	_keyed_mat.shader = sh
	return _keyed_mat

func _build_grass_layer() -> void:
	const TEX_L: String = "res://asset-holder/SBS - Isometric Textures - Floor Pack/Textures/Grass/Grass_10_L-256x128.png"
	const TEX_R: String = "res://asset-holder/SBS - Isometric Textures - Floor Pack/Textures/Grass/Grass_10_R-256x128.png"

	var grass_ts := TileSet.new()
	grass_ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	grass_ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	grass_ts.tile_size = Vector2i(256, 128)

	for src_id in [0, 1]:
		var src := TileSetAtlasSource.new()
		src.texture = load(TEX_L if src_id == 0 else TEX_R)
		src.texture_region_size = Vector2i(256, 128)
		src.create_tile(Vector2i(0, 0))
		grass_ts.add_source(src, src_id)

	var grass_layer := TileMapLayer.new()
	grass_layer.name = "GrassBackground"
	grass_layer.tile_set = grass_ts
	grass_layer.z_index = -2
	grass_layer.material = _make_keyed_material()
	add_child(grass_layer)
	move_child(grass_layer, 0)

	# Cover HALF_SIZE=75 main tiles: each SBS tile = 8 main tiles → need ±10, use ±12 for margin
	const SBS_HALF: int = 12
	for sx in range(-SBS_HALF, SBS_HALF + 1):
		for sy in range(-SBS_HALF, SBS_HALF + 1):
			var src_id: int = 0 if (sx + sy) % 2 == 0 else 1
			grass_layer.set_cell(Vector2i(sx, sy), src_id, Vector2i(0, 0))

func _place_water_pools() -> void:
	_water_centers.clear()
	_water_cells.clear()
	var num_pools := rng.randi_range(8, 18)
	for _i in num_pools:
		var cx := rng.randi_range(-HALF_SIZE + 12, HALF_SIZE - 12)
		var cy := rng.randi_range(-HALF_SIZE + 12, HALF_SIZE - 12)
		if abs(cx) < 18 and abs(cy) < 18:
			continue
		var rx := rng.randi_range(2, 5)
		var ry: int = max(2, int(rx * rng.randf_range(0.55, 1.0)))
		var angle := rng.randf() * PI
		var ca := cos(angle)
		var sa := sin(angle)
		for dx in range(-rx - 1, rx + 2):
			for dy in range(-ry - 1, ry + 2):
				var rdx := ca * dx + sa * dy
				var rdy := -sa * dx + ca * dy
				if (rdx * rdx) / float(rx * rx) + (rdy * rdy) / float(ry * ry) <= 1.0:
					var cell := Vector2i(cx + dx, cy + dy)
					if abs(cell.x) <= HALF_SIZE and abs(cell.y) <= HALF_SIZE:
						_water_cells[cell] = true
		_water_centers.append(Vector2i(cx, cy))

func _carve_path(from: Vector2i, to: Vector2i, half_w: int) -> void:
	var cur := from
	var max_steps: int = (abs(to.x - from.x) + abs(to.y - from.y)) * 3 + 60
	for _step in max_steps:
		if cur == to:
			break
		var dx := to.x - cur.x
		var dy := to.y - cur.y
		var step: Vector2i
		if absf(float(dx)) >= absf(float(dy)):
			step = Vector2i(sign(dx), 0)
		else:
			step = Vector2i(0, sign(dy))
		# 30% chance to wobble perpendicular for natural-looking curves
		if rng.randf() < 0.30:
			if step.x != 0:
				step = Vector2i(0, rng.randi_range(-1, 1))
			else:
				step = Vector2i(rng.randi_range(-1, 1), 0)
		var next := cur + step
		if abs(next.x) > HALF_SIZE or abs(next.y) > HALF_SIZE:
			next = cur
		if _water_cells.has(next):
			# Detour around water — try the other axis
			if step.x != 0:
				next = cur + Vector2i(0, sign(to.y - cur.y) if to.y != cur.y else 1)
			else:
				next = cur + Vector2i(sign(to.x - cur.x) if to.x != cur.x else 1, 0)
		if abs(next.x) > HALF_SIZE or abs(next.y) > HALF_SIZE:
			next = cur + Vector2i(sign(to.x - cur.x), 0) if dx != 0 else cur + Vector2i(0, sign(to.y - cur.y))
		cur = next
		# Paint a band of half_w cells around the path step
		for ox in range(-half_w, half_w + 1):
			for oy in range(-half_w, half_w + 1):
				var pcell := Vector2i(cur.x + ox, cur.y + oy)
				if abs(pcell.x) <= HALF_SIZE and abs(pcell.y) <= HALF_SIZE:
					if not _water_cells.has(pcell):
						_path_cells[pcell] = true

func _place_motivated_paths() -> void:
	_path_cells.clear()
	var spawn := Vector2i(0, 0)
	# Trails from spawn to each water pool (social trails to the water source)
	for wc in _water_centers:
		_carve_path(spawn, wc, 0)
	# Trails between nearby pools (trails between water sources)
	for i in _water_centers.size():
		for j in range(i + 1, _water_centers.size()):
			var a := _water_centers[i]
			var b := _water_centers[j]
			if abs(a.x - b.x) + abs(a.y - b.y) < 25:
				_carve_path(a, b, 0)
	# A few random cross-trails give the world extra character
	for _k in 4:
		var ax := rng.randi_range(-HALF_SIZE + 10, HALF_SIZE - 10)
		var ay := rng.randi_range(-HALF_SIZE + 10, HALF_SIZE - 10)
		var bx := rng.randi_range(-HALF_SIZE + 10, HALF_SIZE - 10)
		var by_ := rng.randi_range(-HALF_SIZE + 10, HALF_SIZE - 10)
		_carve_path(Vector2i(ax, ay), Vector2i(bx, by_), 0)
	_render_paths()

func _render_paths() -> void:
	# Each Path_Dry atlas is 512×192 = 4 cols × 3 rows of 128×64 tiles.
	# Pick one cell per path tile using region_rect so the full atlas isn't shown.
	const PATH_TEX: String = "res://asset-holder/SBS - Isometric Pathways Pack - Small/Exterior Small 128x64/Dry/Path_Dry_01-128x64.png"
	const PCOLS: int = 4
	const PROWS: int = 3
	var path_tex := load(PATH_TEX) as Texture2D

	var layer := Node2D.new()
	layer.name = "PathLayer"
	layer.z_index = -1
	layer.material = _make_keyed_material()
	add_child(layer)

	for cell in _path_cells:
		var cv := cell as Vector2i
		var world_pos := tilemap.to_global(tilemap.map_to_local(cv))
		# Deterministic tile variant per cell
		var idx: int = abs(cv.x * 7 + cv.y * 13) % (PCOLS * PROWS)
		var col: int = idx % PCOLS
		var row: int = idx / PCOLS
		var sprite := Sprite2D.new()
		sprite.texture = path_tex
		sprite.region_enabled = true
		sprite.region_rect = Rect2(col * 128, row * 64, 128, 64)
		sprite.scale = Vector2(0.25, 0.25)
		sprite.material = _make_keyed_material()
		sprite.global_position = world_pos
		layer.add_child(sprite)

func _add_water_visuals() -> void:
	# Floor_Elements_01 is 768×768 = 3 cols × 6 rows of 256×128 tiles.
	# Tile (0,0) is the first water/liquid element.
	const WATER_TEX: String = "res://asset-holder/SBS - Isometric Floor Tiles - Large 256x128/Large 256x128/Exterior/Elements/Floor_Elements_01-256x128.png"
	var water_tex := load(WATER_TEX) as Texture2D
	if water_tex == null:
		return

	# Water layer must sit above the main TileMapLayer (z=0) so it covers
	# the default water tile drawn by the tilemap.
	var layer := Node2D.new()
	layer.name = "WaterVisuals"
	layer.z_index = 1
	layer.material = _make_keyed_material()
	add_child(layer)

	for cell in _water_cells:
		var cv := cell as Vector2i
		var world_pos := tilemap.to_global(tilemap.map_to_local(cv))
		var sprite := Sprite2D.new()
		sprite.texture = water_tex
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 128, 256, 128)
		sprite.scale = Vector2(0.125, 0.125)
		sprite.material = _make_keyed_material()
		sprite.global_position = world_pos
		layer.add_child(sprite)

func _spawn_shrubs() -> void:
	for x in range(-HALF_SIZE + 2, HALF_SIZE - 1):
		for y in range(-HALF_SIZE + 2, HALF_SIZE - 1):
			if abs(x) < 8 and abs(y) < 8:
				continue
			if _water_cells.has(Vector2i(x, y)):
				continue
			if _near_vent(x, y):
				continue
			if rng.randf() < 0.15:
				var world_pos := tilemap.to_global(tilemap.map_to_local(Vector2i(x, y)))
				var shrub: Node2D = SHRUB_SCRIPT.new()
				shrub.position = world_pos
				add_child(shrub)

func _spawn_trees() -> void:
	for x in range(-HALF_SIZE + 2, HALF_SIZE - 1):
		for y in range(-HALF_SIZE + 2, HALF_SIZE - 1):
			if abs(x) < 12 and abs(y) < 12:
				continue
			if _water_cells.has(Vector2i(x, y)):
				continue
			if _near_vent(x, y):
				continue
			if rng.randf() < 0.0825:
				var world_pos := tilemap.to_global(tilemap.map_to_local(Vector2i(x, y)))
				var tree: Node2D = TREE_SCRIPT.new()
				tree.position = world_pos
				add_child(tree)

func _spawn_ground_logs() -> void:
	for x in range(-HALF_SIZE + 2, HALF_SIZE - 1):
		for y in range(-HALF_SIZE + 2, HALF_SIZE - 1):
			if abs(x) < 8 and abs(y) < 8:
				continue
			if _water_cells.has(Vector2i(x, y)):
				continue
			if _near_vent(x, y):
				continue
			if rng.randf() < 0.10:
				var world_pos := tilemap.to_global(tilemap.map_to_local(Vector2i(x, y)))
				var log_item: Node2D = LOG_ITEM_SCRIPT.new()
				log_item.position = world_pos
				add_child(log_item)

func _spawn_rock_piles() -> void:
	for x in range(-HALF_SIZE + 2, HALF_SIZE - 1):
		for y in range(-HALF_SIZE + 2, HALF_SIZE - 1):
			if abs(x) < 8 and abs(y) < 8:
				continue
			if _water_cells.has(Vector2i(x, y)):
				continue
			if _near_vent(x, y):
				continue
			if rng.randf() < 0.12:
				var world_pos := tilemap.to_global(tilemap.map_to_local(Vector2i(x, y)))
				var pile: Node2D = ROCK_PILE_SCRIPT.new()
				pile.position = world_pos
				add_child(pile)

func _spawn_stones() -> void:
	for x in range(-HALF_SIZE + 2, HALF_SIZE - 1):
		for y in range(-HALF_SIZE + 2, HALF_SIZE - 1):
			if abs(x) < 10 and abs(y) < 10:
				continue
			if _water_cells.has(Vector2i(x, y)):
				continue
			if _near_vent(x, y):
				continue
			if rng.randf() < 0.05:
				var world_pos := tilemap.to_global(tilemap.map_to_local(Vector2i(x, y)))
				var stone: Node2D = STONE_SCRIPT.new()
				stone.set("big", rng.randf() < 0.4)
				stone.position = world_pos
				add_child(stone)

func _spawn_log_piles() -> void:
	for x in range(-HALF_SIZE + 2, HALF_SIZE - 1):
		for y in range(-HALF_SIZE + 2, HALF_SIZE - 1):
			if abs(x) < 8 and abs(y) < 8:
				continue
			if _water_cells.has(Vector2i(x, y)):
				continue
			if _near_vent(x, y):
				continue
			if rng.randf() < 0.03:
				var world_pos := tilemap.to_global(tilemap.map_to_local(Vector2i(x, y)))
				var pile: Node2D = LOG_PILE_SCRIPT.new()
				pile.position = world_pos
				add_child(pile)

# ── Boundary walls + border visuals (overworld only) ─────────────────────────

func _add_boundary() -> void:
	const BORDER_EXTRA: int = 14  # 9 previous + 5 more

	var outer: int = HALF_SIZE + BORDER_EXTRA
	for x in range(-outer, outer + 1):
		for y in range(-outer, outer + 1):
			if abs(x) > HALF_SIZE or abs(y) > HALF_SIZE:
				tilemap.set_cell(Vector2i(x, y), _source_id, _atlas_coords)

	var N  := tilemap.to_global(tilemap.map_to_local(Vector2i(-HALF_SIZE, -HALF_SIZE)))
	var E  := tilemap.to_global(tilemap.map_to_local(Vector2i( HALF_SIZE, -HALF_SIZE)))
	var S  := tilemap.to_global(tilemap.map_to_local(Vector2i( HALF_SIZE,  HALF_SIZE)))
	var W  := tilemap.to_global(tilemap.map_to_local(Vector2i(-HALF_SIZE,  HALF_SIZE)))

	var ON := tilemap.to_global(tilemap.map_to_local(Vector2i(-outer, -outer)))
	var OE := tilemap.to_global(tilemap.map_to_local(Vector2i( outer, -outer)))
	var OS := tilemap.to_global(tilemap.map_to_local(Vector2i( outer,  outer)))
	var OW := tilemap.to_global(tilemap.map_to_local(Vector2i(-outer,  outer)))

	# Invisible collision walls along the playable diamond edge
	var inner_diamond := [N, E, S, W]
	for i in 4:
		var wall := StaticBody2D.new()
		var cs   := CollisionShape2D.new()
		var seg  := SegmentShape2D.new()
		seg.a = inner_diamond[i]
		seg.b = inner_diamond[(i + 1) % 4]
		cs.shape = seg
		wall.add_child(cs)
		add_child(wall)

	# Dark overlay over border ring
	var border_col := Color(0.0, 0.0, 0.0, 0.55)
	var border_strips: Array[Array] = [
		[N, E, OE, ON],
		[E, S, OS, OE],
		[S, W, OW, OS],
		[W, N, ON, OW],
	]
	for strip in border_strips:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([strip[0], strip[1], strip[2], strip[3]])
		poly.color = border_col
		poly.z_index = 5
		add_child(poly)

	# Thin blue border line
	var line := Line2D.new()
	line.points = PackedVector2Array([N, E, S, W, N])
	line.width = 1.5
	line.default_color = Color(0.25, 0.55, 1.0, 0.9)
	line.z_index = 6
	add_child(line)

# ── Dungeon handlers ──────────────────────────────────────────────────────────

func _on_dungeon_new() -> void:
	get_tree().change_scene_to_file("res://scenes/dungeon.tscn")

func _on_dungeon_free() -> void:
	var portal: Node2D = PORTAL_SCENE.instantiate()
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		portal.global_position = player.global_position + Vector2(50.0, 0.0)
	else:
		portal.global_position = tilemap.to_global(tilemap.map_to_local(Vector2i(5, 0)))
	add_child(portal)
	GameManager.feedback_requested.emit("A portal tears open nearby.")
