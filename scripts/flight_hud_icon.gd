extends Control

var kind: String = "fuel"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_set_transform(size * 0.5, 0, Vector2.ONE * minf(size.x, size.y) / 32.0)
	var ink: Color = Color("b7d5dd")
	match kind:
		"fuel":
			ink = Color("e4bf75")
			draw_rect(Rect2(-10, -11, 14, 23), ink, false, 2)
			draw_rect(Rect2(-7, -8, 8, 6), ink, false, 1.5)
			draw_polyline(PackedVector2Array([Vector2(4, -3), Vector2(10, 1), Vector2(10, 8), Vector2(13, 8), Vector2(13, -7), Vector2(9, -11)]), ink, 2, true)
			draw_line(Vector2(-13, 13), Vector2(7, 13), ink, 2, true)
		"hull":
			draw_polyline(PackedVector2Array([Vector2(0, -13), Vector2(11, -9), Vector2(10, 5), Vector2(0, 13), Vector2(-10, 5), Vector2(-11, -9), Vector2(0, -13)]), ink, 2, true)
			draw_polyline(PackedVector2Array([Vector2(-5, 2), Vector2(0, -6), Vector2(5, 2), Vector2(0, 0), Vector2(-5, 2)]), ink, 1.5, true)
		"credits":
			ink = Color("cdbb8c")
			draw_arc(Vector2.ZERO, 11, 0, TAU, 40, ink, 1.5, true)
			draw_polyline(PackedVector2Array([Vector2(5, -5), Vector2(1, -7), Vector2(-5, -3), Vector2(-5, 4), Vector2(1, 7), Vector2(5, 5)]), ink, 2, true)
		"map":
			draw_polyline(PackedVector2Array([Vector2(-11, 6), Vector2(-2, -10), Vector2(11, 4), Vector2(-11, 6)]), ink, 1.5, true)
			for point: Vector2 in [Vector2(-11, 6), Vector2(-2, -10), Vector2(11, 4)]:
				draw_circle(point, 3, ink)
		"pause":
			draw_rect(Rect2(-8, -10, 5, 20), ink)
			draw_rect(Rect2(3, -10, 5, 20), ink)
		"play":
			draw_colored_polygon(PackedVector2Array([Vector2(-7, -11), Vector2(10, 0), Vector2(-7, 11)]), ink)
		"ship":
			draw_polyline(PackedVector2Array([Vector2(0, -13), Vector2(11, 10), Vector2(0, 5), Vector2(-11, 10), Vector2(0, -13)]), ink, 2, true)
			draw_line(Vector2(-3, 9), Vector2(-3, 14), ink, 1.5)
			draw_line(Vector2(3, 9), Vector2(3, 14), ink, 1.5)
