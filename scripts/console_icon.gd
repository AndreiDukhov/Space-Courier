extends Control

var kind: String = "parts"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var ink: Color = Color("85b7bc")
	draw_set_transform(centre, 0, Vector2.ONE * minf(size.x, size.y) / 60.0)
	draw_circle(Vector2.ZERO, 28, Color("0a1b25"))
	draw_arc(Vector2.ZERO, 28, 0, TAU, 64, Color("365c67"), 1, true)
	match kind:
		"map":
			var paper: PackedVector2Array = PackedVector2Array([Vector2(-19, -11), Vector2(-6, -16), Vector2(6, -11), Vector2(19, -16), Vector2(19, 12), Vector2(6, 17), Vector2(-6, 12), Vector2(-19, 17), Vector2(-19, -11)])
			draw_colored_polygon(paper, Color("15323e"))
			draw_polyline(paper, ink, 1.7, true)
			draw_line(Vector2(-6, -16), Vector2(-6, 12), ink, 1.0, true)
			draw_line(Vector2(6, -11), Vector2(6, 17), ink, 1.0, true)
			for point: Vector2 in [Vector2(-14, 8), Vector2(-9, 5), Vector2(-4, 6), Vector2(1, 4), Vector2(7, 2)]:
				draw_circle(point, 1.2, Color("d5b77d"))
			draw_circle(Vector2(11, -4), 3.5, Color("d5b77d"))
			draw_colored_polygon(PackedVector2Array([Vector2(8.4, -2), Vector2(13.6, -2), Vector2(11, 3)]), Color("d5b77d"))
			draw_circle(Vector2(11, -4), 1.3, Color("15323e"))
		"launch":
			draw_polyline(PackedVector2Array([Vector2(-11, 12), Vector2(0, -17), Vector2(11, 12), Vector2(0, 7), Vector2(-11, 12)]), ink, 2, true)
			draw_line(Vector2(0, 13), Vector2(0, 20), Color("d8ae70"), 2, true)
		_:
			draw_arc(Vector2(7, -7), 9, -0.4, 4.9, 24, ink, 3, true)
			draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(-14, 14), Vector2(-11, 18), Vector2(5, 2)]), ink, 3, true)
