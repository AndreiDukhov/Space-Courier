extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	for y: int in range(1, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.7, 0.9, 1.0, 0.012), 1)
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x * 0.62, 0), Vector2(size.x * 0.25, size.y * 0.22), Vector2(0, size.y * 0.31)]), Color(0.7, 0.85, 0.9, 0.018))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.65, 0.85, 0.87, 0.1), false, 1)
