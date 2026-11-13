extends RefCounted

const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")

static var _context: String = ""
static var _graph: AStar2D
static var _paths: Dictionary = {}


static func path(vessel: Dictionary, target: Vector2i, turn: Dictionary, remaining: int, settings: Dictionary, occupied: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var origin: Vector2i = Math.cell(vessel["pos"])
	if not Math.inside(target) or not Movement.cone_contains(origin, target, Math.cell(turn["origin"]), int(vessel["facing"]), remaining, settings, int(turn["facing"]), true):
		return result
	var context: String = JSON.stringify([vessel["pos"], vessel["facing"], turn["origin"], turn["facing"], remaining, settings, Math.coordinates(occupied)])
	if context != _context:
		_build(vessel, turn, remaining, settings, occupied)
		_context = context
	if _paths.has(target):
		return _paths[target].duplicate()
	var facing: int = Movement.next_facing(origin, target, int(vessel["facing"]), settings)
	var previous: Vector2i = target - Movement.DIRECTIONS[facing]
	if Math.inside(previous) and _graph.has_point(_id(previous)) and _graph.has_point(_id(target)) and _graph.are_points_connected(_id(previous), _id(target)):
		_graph.set_point_disabled(_id(target), true)
		var points: PackedInt64Array = _graph.get_id_path(_id(origin), _id(previous))
		_graph.set_point_disabled(_id(target), false)
		for point: int in points:
			result.append(_cell(point))
		if not result.is_empty():
			result.append(target)
	if result.is_empty() and _graph.has_point(_id(target)):
		for point: int in _graph.get_id_path(_id(origin), _id(target)):
			result.append(_cell(point))
	_paths[target] = result
	return result.duplicate()


static func arrival_facing(points: Array[Vector2i]) -> int:
	if points.size() < 2:
		return -1
	return Movement.facing_toward(Vector2(points[-1] - points[-2]))


static func trace(turn: Dictionary, position: Array, settings: Dictionary, occupied: Vector2i, first: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var history: Array = turn["history"]
	for index: int in range(history.size()):
		var start: Array = history[index]["pos"]
		var destination: Array = history[index + 1]["pos"] if index + 1 < history.size() else position
		if index >= first:
			var leg: Array[Vector2i] = path({"pos": start, "facing": int(history[index]["facing"])}, Math.cell(destination), turn, int(history[index]["move_points"]), settings, occupied)
			if leg.is_empty():
				return []
			if result.is_empty():
				result.append(leg[0])
			result.append_array(leg.slice(1))
	return result


static func _build(vessel: Dictionary, turn: Dictionary, remaining: int, settings: Dictionary, occupied: Vector2i) -> void:
	_graph = AStar2D.new()
	_paths.clear()
	var origin: Vector2i = Math.cell(vessel["pos"])
	for y: int in range(maxi(0, origin.y - remaining), mini(Math.HEIGHT, origin.y + remaining + 1)):
		for x: int in range(maxi(0, origin.x - remaining), mini(Math.WIDTH, origin.x + remaining + 1)):
			var cell: Vector2i = Vector2i(x, y)
			if cell == occupied:
				continue
			if cell == origin or Movement.cone_contains(origin, cell, Math.cell(turn["origin"]), int(vessel["facing"]), remaining, settings, int(turn["facing"]), true):
				_graph.add_point(_id(cell), Vector2(cell))
	var blocked: Array[Vector2i] = [occupied]
	for point: int in _graph.get_point_ids():
		var cell: Vector2i = _cell(point)
		for index: int in range(4):
			var next: Vector2i = cell + Movement.DIRECTIONS[index]
			if Math.inside(next) and _graph.has_point(_id(next)) and Movement.clear_segment(cell, next, blocked):
				_graph.connect_points(point, _id(next))


static func _id(cell: Vector2i) -> int:
	return cell.y * Math.WIDTH + cell.x


static func _cell(point: int) -> Vector2i:
	return Vector2i(point % Math.WIDTH, point / Math.WIDTH)
