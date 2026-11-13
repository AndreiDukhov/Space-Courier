extends Control

var layer: String = "base"
var face: String = "neutral"
var blush: int = 0
var color: Color = Color(0.3, 0.6, 0.7)


func _draw() -> void:
	var factor: float = minf(size.x / 80.0, size.y / 100.0)
	var origin: Vector2 = (size - Vector2(80, 100) * factor) * 0.5
	draw_set_transform(origin, 0, Vector2(factor, factor))
	match layer:
		"base":
			draw_rect(Rect2(12, 62, 56, 36), color.darkened(0.2))
			draw_rect(Rect2(31, 55, 18, 14), color.lightened(0.38))
			draw_circle(Vector2(40, 34), 25, color.lightened(0.5))
			draw_arc(Vector2(40, 30), 24, PI, TAU, 20, color.darkened(0.45), 10, true)
			if color.v > 0.3:
				draw_rect(Rect2(29, 70, 22, 5), color.lightened(0.3))
		"face":
			var ink: Color = Color(0.06, 0.09, 0.13)
			if face == "happy":
				draw_arc(Vector2(29, 34), 5, PI, TAU, 10, ink, 2, true)
				draw_arc(Vector2(51, 34), 5, PI, TAU, 10, ink, 2, true)
				draw_arc(Vector2(40, 42), 8, 0.0, PI, 12, ink, 2, true)
			else:
				draw_circle(Vector2(29, 34), 2.4, ink)
				draw_circle(Vector2(51, 34), 2.4, ink)
				if face == "annoyed":
					draw_line(Vector2(24, 25), Vector2(34, 29), ink, 2, true)
					draw_line(Vector2(46, 29), Vector2(56, 25), ink, 2, true)
					draw_line(Vector2(35, 47), Vector2(45, 47), ink, 2, true)
				elif face == "sad":
					draw_line(Vector2(24, 28), Vector2(34, 24), ink, 2, true)
					draw_line(Vector2(46, 24), Vector2(56, 28), ink, 2, true)
					draw_arc(Vector2(40, 53), 8, PI, TAU, 12, ink, 2, true)
				else:
					draw_line(Vector2(35, 46), Vector2(45, 46), ink, 2, true)
		"blush":
			if blush > 0:
				var tint: Color = Color(0.95, 0.27, 0.36, 0.3 if blush == 1 else 0.65)
				draw_ellipse(Vector2(23, 43), 8, 4, tint)
				draw_ellipse(Vector2(57, 43), 8, 4, tint)
