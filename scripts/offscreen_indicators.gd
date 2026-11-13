extends Control

const Motion = preload("res://scripts/flight_motion.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const MARGIN: float = 8.0
const GAP: float = 6.0
const QUEST_COLOR: Color = Color(0.25, 0.95, 0.45)
const DEFAULT_COLOR: Color = Color(0.4, 0.85, 1.0)

var camera: Camera3D
var reserved_rect: Rect2 = Rect2()
var _objects: Dictionary = {}
var _rows: Dictionary = {}
var _directions: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(sync)
	rebuild()


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_objects.clear()
	_rows.clear()
	_directions.clear()
	for object: Dictionary in DataLoader.get_record(str(GameState.state.get("current_system", ""))).get("objects", []):
		if object.get("type") not in ["planet", "station"]:
			continue
		var object_id: String = str(object["id"])
		_objects[object_id] = object
		var row: PanelContainer = PanelContainer.new()
		row.name = object_id
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", Style.box(Color(0.02, 0.04, 0.07, 0.86), 6))
		add_child(row)
		_rows[object_id] = row
		var contents: HBoxContainer = HBoxContainer.new()
		contents.name = "Content"
		contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.add_theme_constant_override("separation", 5)
		row.add_child(contents)
		var arrow: Control = Control.new()
		arrow.name = "Arrow"
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.custom_minimum_size = Vector2(20, 26)
		arrow.draw.connect(_draw_arrow.bind(arrow, object_id))
		contents.add_child(arrow)
		var label: Label = Label.new()
		label.name = "Name"
		label.text = str(object["name"])
		label.custom_minimum_size.x = 126
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.add_child(label)
	sync.call_deferred()


func sync() -> void:
	if not is_inside_tree() or camera == null or size.x < 200 or size.y < 100:
		return
	var edges: Array = [[], [], [], []]
	var center: Vector2 = size * 0.5
	for object_id: String in _rows:
		var row: PanelContainer = _rows[object_id]
		var projected: Vector2 = camera.unproject_position(Motion.world_position(_objects[object_id]["pos"], 0.3))
		row.visible = not Rect2(Vector2.ZERO, size).has_point(projected)
		if not row.visible:
			continue
		var direction: Vector2 = (projected - center).normalized()
		_directions[object_id] = direction
		row.get_node("Content/Name").add_theme_color_override("font_color", QUEST_COLOR if Conditions.planet_has_active_delivery(object_id) else Color(0.75, 0.88, 1.0))
		var half: Vector2 = (size - row.size) * 0.5 - Vector2.ONE * MARGIN
		var horizontal: float = half.x / maxf(absf(direction.x), 0.0001)
		var vertical: float = half.y / maxf(absf(direction.y), 0.0001)
		row.position = center + direction * minf(horizontal, vertical) - row.size * 0.5
		var edge: int = 0 if direction.x < 0 else 1
		if vertical <= horizontal:
			edge = 2 if direction.y < 0 else 3
		edges[edge].append(row)
		row.get_node("Content/Arrow").queue_redraw()
	for edge: int in range(edges.size()):
		_arrange_edge(edges[edge], edge)


func _arrange_edge(rows: Array, edge: int) -> void:
	var axis: int = 1 if edge < 2 else 0
	rows.sort_custom(func(a: Control, b: Control) -> bool: return a.position[axis] < b.position[axis])
	var next: float = MARGIN
	if reserved_rect.has_area() and edge == 1:
		next = maxf(next, reserved_rect.end.y + GAP)
	for row: Control in rows:
		row.position[axis] = maxf(row.position[axis], next)
		next = row.position[axis] + row.size[axis] + GAP
	next = size[axis] - MARGIN
	if reserved_rect.has_area() and edge == 2:
		next = minf(next, reserved_rect.position.x - GAP)
	for index: int in range(rows.size() - 1, -1, -1):
		var row: Control = rows[index]
		row.position[axis] = minf(row.position[axis], next - row.size[axis])
		next = row.position[axis] - GAP


func _draw_arrow(arrow: Control, object_id: String) -> void:
	var direction: Vector2 = _directions.get(object_id, Vector2.UP)
	var center: Vector2 = arrow.size * 0.5
	var side: Vector2 = direction.orthogonal() * 5.0
	var color: Color = QUEST_COLOR if Conditions.planet_has_active_delivery(object_id) else DEFAULT_COLOR
	arrow.draw_colored_polygon(PackedVector2Array([center + direction * 9.0, center - direction * 5.0 + side, center - direction * 5.0 - side]), color)
