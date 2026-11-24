extends Button

var polygon: PackedVector2Array = PackedVector2Array():
	set(value):
		polygon = value
		queue_redraw()


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point) if polygon.is_empty() else Geometry2D.is_point_in_polygon(point, polygon)


func _draw() -> void:
	if polygon.is_empty() or (get_draw_mode() == BaseButton.DRAW_NORMAL and not has_focus()):
		return
	var pressed: bool = get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]
	draw_colored_polygon(polygon, Color(1.0, 0.81, 0.48, 0.12 if pressed else 0.065))
	var outline: PackedVector2Array = polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, Color(1.0, 0.73, 0.3, 0.045), 9.0, true)
	draw_polyline(outline, Color(1.0, 0.82, 0.5, 0.12), 4.0, true)
	draw_polyline(outline, Color(1.0, 0.9, 0.7, 0.7), 1.2, true)
