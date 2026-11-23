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
	draw_colored_polygon(polygon, Color(0.55, 0.85, 1.0, 0.15 if pressed else 0.08))
	var outline: PackedVector2Array = polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, Color(0.65, 0.9, 1.0, 0.55), 1.5, true)
