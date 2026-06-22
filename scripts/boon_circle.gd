extends Control
# Draws a circle split into 4 quarter arcs. Set filled_quarters (0-4) before queue_redraw().
var filled_quarters: int = 0
const RADIUS: float = 52.0

func _draw() -> void:
	var c := Vector2(RADIUS, RADIUS)
	# Dark background circle
	draw_circle(c, RADIUS, Color(0.06, 0.04, 0.12, 0.9))
	# Quarter arcs — each covers 90°
	for q in 4:
		var start_a := -PI * 0.5 + q * (PI * 0.5)
		var end_a   := start_a + PI * 0.5
		var col: Color
		if q < filled_quarters:
			col = Color(0.55, 0.0, 0.9, 0.95)   # filled — bright purple
		else:
			col = Color(0.22, 0.10, 0.30, 0.7)  # unfilled — dim
		# Filled sector (triangle fan)
		var pts := PackedVector2Array()
		pts.append(c)
		const SEGS: int = 16
		var step := (end_a - start_a) / float(SEGS)
		for i in range(SEGS + 1):
			var a := start_a + step * float(i)
			pts.append(c + Vector2(cos(a), sin(a)) * (RADIUS - 2.0))
		draw_colored_polygon(pts, col)
		# Dividing line between quarters
		var rim_pt := c + Vector2(cos(start_a), sin(start_a)) * RADIUS
		draw_line(c, rim_pt, Color(0, 0, 0, 0.8), 1.5)
	# Outer rim
	draw_arc(c, RADIUS - 0.5, 0.0, TAU, 64, Color(0.55, 0.15, 0.75, 0.85), 1.5)
	# Centre label
	var font := ThemeDB.fallback_font
	var fs := 8
	var s := "%d / 4" % filled_quarters
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-tw * 0.5, float(fs) * 0.4), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
