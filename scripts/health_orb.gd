extends Control

var current_hp: int = 100
var max_hp: int = 100
const RADIUS: float = 24.0

func _draw() -> void:
	var c := Vector2(RADIUS, RADIUS)
	draw_circle(c, RADIUS, Color(0.05, 0.02, 0.02, 0.90))
	var ratio := clampf(float(current_hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
	if ratio > 0.0:
		var pts := PackedVector2Array()
		pts.append(c)
		const SEGS: int = 48
		var start_a := -PI * 0.5
		var end_a := start_a + TAU * ratio
		var step_a := (end_a - start_a) / float(SEGS)
		for i in range(SEGS + 1):
			var a := start_a + step_a * float(i)
			pts.append(c + Vector2(cos(a), sin(a)) * (RADIUS - 2.0))
		var fill_col := Color(0.9, 0.15, 0.15, 1.0) if ratio > 0.25 else Color(1.0, 0.4, 0.0, 1.0)
		draw_colored_polygon(pts, fill_col)
	draw_arc(c, RADIUS - 0.5, 0.0, TAU, 64, Color(0.55, 0.15, 0.15, 0.85), 1.5)
	var font := ThemeDB.fallback_font
	var fs := 7
	var s := str(current_hp)
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-tw * 0.5, float(fs) * 0.4), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 1.0, 1.0))
