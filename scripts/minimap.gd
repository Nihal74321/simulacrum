extends Control

const SMALL_SIZE  := Vector2(200.0, 137.5)
const LARGE_SIZE  := Vector2(500.0, 340.0)
const MAP_SCALE   := 0.09

var is_large: bool = false :
	set(v):
		is_large = v
		_apply_size()

func _ready() -> void:
	visible = true
	_apply_size()

func _apply_size() -> void:
	if is_large:
		# Centred on screen
		anchor_left   = 0.5
		anchor_right  = 0.5
		anchor_top    = 0.5
		anchor_bottom = 0.5
		offset_left   = -LARGE_SIZE.x * 0.5
		offset_right  =  LARGE_SIZE.x * 0.5
		offset_top    = -LARGE_SIZE.y * 0.5
		offset_bottom =  LARGE_SIZE.y * 0.5
	else:
		# Top-right, inset 8 px
		anchor_left   = 1.0
		anchor_right  = 1.0
		anchor_top    = 0.0
		anchor_bottom = 0.0
		offset_left   = -(SMALL_SIZE.x + 8.0)
		offset_right  = -8.0
		offset_top    = 8.0
		offset_bottom = 8.0 + SMALL_SIZE.y

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var sz := LARGE_SIZE if is_large else SMALL_SIZE
	var scale := MAP_SCALE * (3.0 if is_large else 1.0)
	var center := sz * 0.5

	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.10, 0.08, 0.85))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.6, 0.6, 0.6, 1.0), false, 1.5)

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		_label_center(sz, "no signal")
		return

	var origin: Vector2 = player.global_position
	var bounds := Rect2(Vector2.ZERO, sz)

	# Draw tilemap ground
	var tm: TileMapLayer = get_tree().get_first_node_in_group("tilemap") as TileMapLayer
	if tm != null:
		var in_dungeon := GameManager.dungeon_active
		if in_dungeon:
			for cell in tm.get_used_cells():
				if not GameManager.dungeon_explored_tiles.has(cell):
					continue
				var world_pos: Vector2 = tm.to_global(tm.map_to_local(cell))
				var rel := (world_pos - origin) * scale
				var pt := center + rel
				if not bounds.has_point(pt):
					continue
				var atlas := tm.get_cell_atlas_coords(cell)
				var col: Color
				if atlas == Vector2i(5, 1):
					col = Color(0.25, 0.25, 0.25, 0.7)
				elif atlas == Vector2i(6, 0):
					col = Color(0.35, 0.22, 0.10, 0.7)
				else:
					col = Color(0.30, 0.28, 0.35, 0.85)
				draw_rect(Rect2(pt - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), col)
		else:
			# Overworld: draw solid grass rectangle for the world bounds
			const HALF: int = 75
			var grass_col := Color(0.15, 0.30, 0.12, 0.7)
			var water_col := Color(0.1, 0.25, 0.55, 0.7)
			var ash_col   := Color(0.25, 0.25, 0.25, 0.7)
			for gx in range(-HALF, HALF + 1):
				for gy in range(-HALF, HALF + 1):
					var world_pos: Vector2 = tm.to_global(tm.map_to_local(Vector2i(gx, gy)))
					var rel := (world_pos - origin) * scale
					var pt := center + rel
					if not bounds.has_point(pt):
						continue
					var cell_v := Vector2i(gx, gy)
					var main_node := get_tree().get_first_node_in_group("main_world")
					var col: Color = grass_col
					if main_node != null and main_node.has_method("_is_water_cell") and main_node._is_water_cell(cell_v):
						col = water_col
					elif tm.get_cell_atlas_coords(cell_v) == Vector2i(5, 1):
						col = ash_col
					draw_rect(Rect2(pt - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), col)

	for poi in get_tree().get_nodes_in_group("pois"):
		var rel := ((poi as Node2D).global_position - origin) * scale
		var pt := center + rel
		if bounds.has_point(pt):
			var col: Color = poi.get_meta("poi_color", Color(0.6, 0.6, 0.4))
			draw_circle(pt, 2.0, col)

	for m in get_tree().get_nodes_in_group("machines"):
		var rel := ((m as Node2D).global_position - origin) * scale
		var pt := center + rel
		if bounds.has_point(pt):
			draw_rect(Rect2(pt - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.7, 1.0, 1.0))

	for c in get_tree().get_nodes_in_group("chests"):
		var rel := ((c as Node2D).global_position - origin) * scale
		var pt := center + rel
		if bounds.has_point(pt):
			draw_rect(Rect2(pt - Vector2(2, 2), Vector2(4, 4)), Color(0.7, 0.5, 0.15, 1.0))

	for e in get_tree().get_nodes_in_group("enemies"):
		var rel := ((e as Node2D).global_position - origin) * scale
		var pt := center + rel
		if bounds.has_point(pt):
			draw_circle(pt, 2.5, Color(0.9, 0.15, 0.15, 1.0))

	for vent in get_tree().get_nodes_in_group("geothermal_vents"):
		var vent_node := vent as Node2D
		if vent_node.global_position.distance_to(origin) > 300.0:
			continue
		var rel := (vent_node.global_position - origin) * scale
		var pt := center + rel
		if bounds.has_point(pt):
			draw_circle(pt, 3.0, Color(0.9, 0.4, 0.1, 1.0))

	draw_circle(center, 3.5, Color(1.0, 1.0, 1.0, 1.0))

	if is_large:
		_draw_string_safe("N", center + Vector2(0, -sz.y * 0.45))
		_draw_string_safe("S", center + Vector2(0,  sz.y * 0.45))
		_draw_string_safe("W", center + Vector2(-sz.x * 0.45, 0))
		_draw_string_safe("E", center + Vector2( sz.x * 0.45, 0))

func _label_center(sz: Vector2, text: String) -> void:
	draw_string(ThemeDB.fallback_font, sz * 0.5 - Vector2(20, -8), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5))

func _draw_string_safe(text: String, pos: Vector2) -> void:
	draw_string(ThemeDB.fallback_font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.6, 0.6, 0.6, 0.8))
