extends Control

var kind: String = "turret"


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var scale: float = minf(size.x, size.y) / 64.0
	draw_set_transform(centre, 0.0, Vector2.ONE * scale)
	var metal: Color = Color(0.65, 0.76, 0.82)
	var glow: Color = Color(0.35, 0.95, 0.85)
	match kind:
		"armor":
			draw_rect(Rect2(-23, -26, 46, 52), metal.darkened(0.3))
			draw_rect(Rect2(-17, -20, 34, 40), metal)
			for point: Vector2 in [Vector2(-17, -20), Vector2(17, -20), Vector2(-17, 20), Vector2(17, 20)]:
				draw_circle(point, 3, glow)
		"turret":
			draw_circle(Vector2(0, 9), 19, Color(0.13, 0.23, 0.3))
			draw_circle(Vector2(0, 9), 15, metal)
			draw_rect(Rect2(-5, -26, 10, 38), metal.darkened(0.25))
			draw_rect(Rect2(-7, -28, 14, 6), glow)
		"course":
			draw_colored_polygon(PackedVector2Array([Vector2(-19, 23), Vector2(0, -14), Vector2(19, 23)]), metal.darkened(0.3))
			for x: float in [-8.0, 8.0]:
				draw_rect(Rect2(x - 3, -28, 6, 45), metal)
				draw_line(Vector2(x, -28), Vector2(x, -17), glow, 3)
		"broadside":
			draw_rect(Rect2(-11, -24, 22, 48), metal.darkened(0.3))
			for y: float in [-13.0, 1.0, 15.0]:
				draw_line(Vector2(-27, y), Vector2(27, y), metal, 6)
				draw_circle(Vector2(-28, y), 3, glow)
				draw_circle(Vector2(28, y), 3, glow)
		"burn":
			draw_colored_polygon(PackedVector2Array([Vector2(-18, 8), Vector2(0, -27), Vector2(18, 8)]), metal)
			for x: float in [-9.0, 0.0, 9.0]:
				draw_line(Vector2(x, 10), Vector2(x, 29 - absf(x)), Color(1.0, 0.55, 0.15), 5)
		"shield":
			var points: PackedVector2Array = [Vector2(-22, -20), Vector2(0, -28), Vector2(22, -20), Vector2(17, 12), Vector2(0, 28), Vector2(-17, 12), Vector2(-22, -20)]
			draw_polyline(points, Color(0.3, 0.65, 1.0), 4, true)
			draw_line(Vector2(-11, 0), Vector2(11, 0), glow, 4)
			draw_line(Vector2(0, -11), Vector2(0, 11), glow, 4)
		"evasion":
			draw_polyline(PackedVector2Array([Vector2(-22, 24), Vector2(-22, -3), Vector2(18, -3), Vector2(18, -24)]), glow, 5, true)
			draw_colored_polygon(PackedVector2Array([Vector2(7, -14), Vector2(18, -29), Vector2(29, -14)]), metal)
