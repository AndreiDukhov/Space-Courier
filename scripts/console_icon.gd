extends Control

var kind: String = "parts"


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var ink: Color = Color("85b7bc")
	draw_set_transform(centre, 0, Vector2.ONE * minf(size.x, size.y) / 60.0)
	draw_circle(Vector2.ZERO, 28, Color("0a1b25"))
	draw_arc(Vector2.ZERO, 28, 0, TAU, 64, Color("365c67"), 1, true)
	match kind:
		"map":
			for point: Vector2 in [Vector2(-13, 9), Vector2(-3, -12), Vector2(15, 4)]:
				draw_circle(point, 4, ink)
			draw_polyline(PackedVector2Array([Vector2(-13, 9), Vector2(-3, -12), Vector2(15, 4), Vector2(-13, 9)]), ink, 1.5, true)
		"launch":
			draw_polyline(PackedVector2Array([Vector2(-11, 12), Vector2(0, -17), Vector2(11, 12), Vector2(0, 7), Vector2(-11, 12)]), ink, 2, true)
			draw_line(Vector2(0, 13), Vector2(0, 20), Color("d8ae70"), 2, true)
		_:
			draw_arc(Vector2(7, -7), 9, -0.4, 4.9, 24, ink, 3, true)
			draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(-14, 14), Vector2(-11, 18), Vector2(5, 2)]), ink, 3, true)
