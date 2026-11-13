extends Control

signal system_selected(system_id: String)

const Navigation = preload("res://scripts/galaxy_navigation.gd")
const Widgets = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var selected_system: String = ""


func _ready() -> void:
	resized.connect(refresh)
	refresh()


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for system: Dictionary in DataLoader.get_records("systems"):
		var system_id: String = str(system["id"])
		var status: String = str(GameState.state.get("systems", {}).get(system_id, "hidden"))
		if status == "hidden":
			continue
		var button: Button = Button.new()
		button.name = system_id
		button.text = str(system["name"]) + "\n" + Text.get_text("ui_map_" + status)
		button.tooltip_text = str(system["name"])
		var compact: bool = size.x < 700.0
		button.custom_minimum_size = Vector2(96, 46) if compact else Vector2(134, 54)
		button.position = point_for(system) - button.custom_minimum_size / 2.0
		button.add_theme_font_size_override("font_size", 11 if compact else 13)
		var border: Color = Color(0.35, 0.95, 0.85) if system_id == GameState.state.get("current_system") else Color(0.4, 0.5, 0.65)
		if system_id == selected_system:
			border = Color(1.0, 0.8, 0.35)
		button.add_theme_stylebox_override("normal", Widgets.box(Color(0.04, 0.08, 0.14), 14, border, 2))
		button.add_theme_stylebox_override("hover", Widgets.box(Color(0.08, 0.2, 0.25), 14, Color.WHITE, 2))
		button.pressed.connect(system_selected.emit.bind(system_id))
		add_child(button)
	queue_redraw()


func point_for(system: Dictionary) -> Vector2:
	var point: Array = system["map_pos"]
	var padding: Vector2 = Vector2(52, 45) if size.x < 700.0 else Vector2(80, 60)
	return padding + Vector2(float(point[0]) / 1000.0, float(point[1]) / 650.0) * (size - padding * 2.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.08))
	for x: int in range(0, int(size.x), 48):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.07, 0.11, 0.16))
	for y: int in range(0, int(size.y), 48):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.07, 0.11, 0.16))
	for route: Dictionary in Navigation.visible_routes():
		var origin: Vector2 = point_for(DataLoader.get_record(str(route["from"])))
		var target: Vector2 = point_for(DataLoader.get_record(str(route["to"])))
		var direction: Vector2 = (target - origin).normalized()
		var offset: Vector2 = direction.orthogonal() * 8.0
		origin += offset
		target += offset
		var color: Color = Color(0.25, 0.8, 0.72) if route["id"] in GameState.state.get("known_routes", []) else Color(0.7, 0.55, 0.3)
		if route["id"] in GameState.state.get("known_routes", []):
			draw_line(origin, target, color, 2.0, true)
		else:
			draw_dashed_line(origin, target, color, 2.0, 7.0)
		var arrow: Vector2 = origin.lerp(target, 0.6)
		draw_line(arrow, arrow - direction.rotated(0.5) * 12.0, color, 2.0, true)
		draw_line(arrow, arrow - direction.rotated(-0.5) * 12.0, color, 2.0, true)
	for x: int in range(0, int(size.x), 96):
		for y: int in range(0, int(size.y), 96):
			var cell: Vector2 = Vector2(x + 48, y + 48)
			var visible: bool = false
			for system: Dictionary in DataLoader.get_records("systems"):
				if GameState.state.get("systems", {}).get(system["id"], "hidden") != "hidden" and point_for(system).distance_to(cell) < 150.0:
					visible = true
			if not visible:
				draw_rect(Rect2(Vector2(x, y), Vector2(96, 96)), Color(0.13, 0.15, 0.2, 0.7))
