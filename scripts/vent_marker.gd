extends Control

var vent: Node2D = null

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if vent == null:
		return
	var is_processing: bool = vent.get("_processing") == true
	var cf_raw: Variant = vent.get("_complete_flash")
	var complete_flash: float = float(cf_raw) if cf_raw != null else 0.0
	# Forge/anvil use _ready_to_collect instead of _complete_flash
	var rtc_raw: Variant = vent.get("_ready_to_collect")
	var is_complete: bool = complete_flash > 0.0 or rtc_raw == true
	var cp_raw: Variant = vent.get("_complete_plate")
	var complete_plate: String = str(cp_raw) if cp_raw != null else ""
	if complete_plate.is_empty() or complete_plate == "null":
		var ci_raw: Variant = vent.get("_collect_item")
		complete_plate = str(ci_raw) if ci_raw != null and str(ci_raw) != "null" else ""

	if not is_processing and not is_complete:
		return

	var vp_size := get_viewport().get_visible_rect().size
	var canvas_t := get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = canvas_t * vent.global_position

	var margin := 28.0
	var bounds := Rect2(margin, margin, vp_size.x - margin * 2.0, vp_size.y - margin * 2.0)
	if bounds.has_point(screen_pos):
		return

	var center := vp_size * 0.5
	var dir := (screen_pos - center).normalized()

	var t: float = INF
	if abs(dir.x) > 0.0001:
		var edge_x: float = (vp_size.x - margin) if dir.x > 0.0 else margin
		var tx: float = (edge_x - center.x) / dir.x
		if tx > 0.0:
			t = min(t, tx)
	if abs(dir.y) > 0.0001:
		var edge_y: float = (vp_size.y - margin) if dir.y > 0.0 else margin
		var ty: float = (edge_y - center.y) / dir.y
		if ty > 0.0:
			t = min(t, ty)
	if t == INF:
		return

	var edge_pt := center + dir * t
	var col := Color(0.2, 0.9, 0.3, 0.9) if is_complete else Color(1.0, 0.55, 0.12, 0.9)

	var perp := Vector2(-dir.y, dir.x) * 8.0
	draw_colored_polygon(PackedVector2Array([
		edge_pt + dir * 14.0,
		edge_pt - dir * 4.0 + perp,
		edge_pt - dir * 4.0 - perp,
	]), col)
	draw_arc(edge_pt, 4.0, 0.0, TAU, 10, col, 2.0)

	if is_complete and not complete_plate.is_empty():
		var font := ThemeDB.fallback_font
		var label_pos := edge_pt + dir * 22.0 - Vector2(40, 7)
		draw_string(font, label_pos, complete_plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.2, 0.9, 0.3, 0.95))
