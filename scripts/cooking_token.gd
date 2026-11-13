extends Control

var item_id: String = "carrot"
var draggable: bool = true
var steps: Array[String] = []
var plated: bool = false
var entry_index: int = -1
var show_plate: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(84, 84)
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var scale: float = minf(size.x, size.y) / 84.0
	var boiled: bool = "boil" in steps
	var fried: bool = "fry" in steps
	if item_id == "noodles":
		_draw_noodles(center, scale, boiled, fried)
		return
	var color: Color = Color(0.88, 0.36, 0.08) if fried else (Color(1.0, 0.65, 0.28) if boiled else Color(1.0, 0.49, 0.12))
	if plated and show_plate:
		draw_set_transform(center, 0, Vector2(scale, scale))
		draw_ellipse(Vector2(0, 8), 38, 25, Color(0.88, 0.93, 0.93))
		draw_ellipse(Vector2(0, 8), 30, 18, Color(0.65, 0.77, 0.8))
		draw_set_transform(Vector2.ZERO)
	if "cut" in steps:
		for offset: Vector2 in [Vector2(-16, -9), Vector2(12, -9), Vector2(-16, 17), Vector2(12, 17)]:
			var point: Vector2 = center + offset * scale
			draw_circle(point, 12 * scale, color.darkened(0.2))
			draw_circle(point, 9 * scale, color)
			draw_circle(point, 3 * scale, Color(1.0, 0.78, 0.32))
			if fried:
				draw_line(point + Vector2(-6, -3) * scale, point + Vector2(6, 3) * scale, Color(0.32, 0.13, 0.05), 2 * scale, true)
	else:
		_draw_whole(center, scale, color)
		if fried:
			for y: float in [-10.0, 1.0, 12.0]:
				draw_line(center + Vector2(-9, y) * scale, center + Vector2(8, y - 3) * scale, Color(0.32, 0.13, 0.05), 3 * scale, true)
	if boiled:
		for x: float in [-17.0, 0.0, 17.0]:
			draw_polyline(PackedVector2Array([center + Vector2(x, -20) * scale, center + Vector2(x - 4, -29) * scale, center + Vector2(x + 2, -37) * scale]), Color(0.7, 0.93, 1.0), 2 * scale, true)


func _draw_whole(center: Vector2, scale: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([Vector2(-18, -18), Vector2(18, -18), Vector2(10, 4), Vector2(-9, 30)])
	for index: int in range(points.size()):
		points[index] = center + points[index] * scale
	draw_colored_polygon(points, color)
	if steps.is_empty():
		for offset: float in [-12.0, 0.0, 12.0]:
			draw_line(center + Vector2(0, -15) * scale, center + Vector2(offset, -35) * scale, Color(0.35, 0.8, 0.28), 5 * scale, true)
	draw_line(center + Vector2(-12, -8) * scale, center + Vector2(0, -6) * scale, Color(0.8, 0.28, 0.07), 2 * scale, true)


func _get_drag_data(_position: Vector2) -> Variant:
	if not draggable:
		return null
	var preview: Control = Control.new()
	var icon: Control = get_script().new()
	icon.size = Vector2(84, 84)
	icon.position = Vector2(-42, -42)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.item_id = item_id
	icon.steps.assign(steps)
	icon.plated = plated
	preview.add_child(icon)
	set_drag_preview(preview)
	return {"item": item_id, "entry": entry_index}


func _draw_noodles(center: Vector2, scale: float, boiled: bool, fried: bool) -> void:
	var colour: Color = Color(0.85, 0.54, 0.19) if fried else Color(1.0, 0.86, 0.48)
	for index: int in range(7):
		var points: PackedVector2Array = []
		for segment: int in range(11):
			var x: float = -28.0 + float(segment) * 5.6
			var y: float = -21.0 + float(index) * 7.0 + sin(float(segment) * 1.8 + float(index)) * 3.0
			points.append(center + Vector2(x, y) * scale)
		draw_polyline(points, colour, 3.0 * scale, true)
	if boiled:
		for x: float in [-18.0, 0.0, 18.0]:
			draw_line(center + Vector2(x, -27) * scale, center + Vector2(x + 4, -35) * scale, Color(0.75, 0.95, 1.0), 2.0 * scale, true)
