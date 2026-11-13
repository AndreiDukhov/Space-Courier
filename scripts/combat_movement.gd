extends RefCounted

const BOARD_SIZE: Vector2i = Vector2i(32, 24)
const EDGE_ASSIST_DISTANCE: float = 3.0
const MAX_EDGE_TURN_BONUS: int = 3
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]


static func heading(facing: int) -> Vector2:
	return Vector2(DIRECTIONS[posmod(facing, 8)]).normalized()


static func facing_toward(direction: Vector2) -> int:
	if direction.is_zero_approx():
		return 0
	return posmod(roundi(atan2(direction.x, -direction.y) / (PI / 4.0)), 8)


static func cost(origin: Vector2i, target: Vector2i) -> int:
	return ceili(Vector2(origin).distance_to(Vector2(target)))


static func cone_contains(origin: Vector2i, target: Vector2i, turn_origin: Vector2i, facing: int, remaining: int, movement: Dictionary, initial_facing: int = -1, assist_edges: bool = false) -> bool:
	if origin == target or cost(origin, target) > remaining:
		return false
	var bonus: int = edge_turn_bonus(origin, facing) if assist_edges else 0
	if bonus == 0:
		return _in_cone(origin, target, turn_origin, facing, movement, initial_facing, 1.0)
	var desired: int = facing_toward(Vector2(target - origin))
	var difference: int = absi(posmod(desired - facing + 4, 8) - 4)
	if difference > turn_steps(origin, facing, movement):
		return false
	var inertia_scale: float = 1.0 - float(bonus) / float(MAX_EDGE_TURN_BONUS)
	return _in_cone(origin, target, turn_origin, desired, movement, initial_facing if initial_facing >= 0 else facing, inertia_scale)


static func _in_cone(origin: Vector2i, target: Vector2i, turn_origin: Vector2i, facing: int, movement: Dictionary, initial_facing: int, inertia_scale: float) -> bool:
	var forward: Vector2 = heading(facing)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var delta: Vector2 = Vector2(target - origin)
	var f: float = delta.dot(forward)
	var l: float = delta.dot(right)
	if f < 1.0 - 0.00001:
		return false
	var level: int = int(movement["maneuver_level"])
	var slope: float = minf(float(movement["cone_slope_max"]), float(movement["cone_slope_base"]) + float(movement["cone_slope_per_level"]) * level)
	var inertia: float = maxf(float(movement["inertia_min"]), float(movement["inertia_base"]) - float(movement["inertia_per_level"]) * level) * inertia_scale
	var initial_heading: Vector2 = heading(initial_facing if initial_facing >= 0 else facing)
	var lateral_shift: float = Vector2(origin - turn_origin).dot(Vector2(-initial_heading.y, initial_heading.x))
	var width: float = float(movement["cone_base"]) + slope * f
	var left_width: float = maxf(0.0, width - inertia * maxf(lateral_shift, 0.0))
	var right_width: float = maxf(0.0, width - inertia * maxf(-lateral_shift, 0.0))
	return l >= -left_width - 0.00001 and l <= right_width + 0.00001


static func next_facing(origin: Vector2i, target: Vector2i, facing: int, movement: Dictionary) -> int:
	if origin == target:
		return facing
	var desired: int = facing_toward(Vector2(target - origin))
	var difference: int = posmod(desired - facing + 4, 8) - 4
	var steps: int = turn_steps(origin, facing, movement)
	return posmod(facing + clampi(difference, -steps, steps), 8)


static func turn_steps(origin: Vector2i, facing: int, movement: Dictionary) -> int:
	var normal: int = int(movement["turn_steps_base"]) + floori(float(movement["maneuver_level"]) / 2.0)
	return mini(4, normal + edge_turn_bonus(origin, facing))


static func edge_turn_bonus(origin: Vector2i, facing: int) -> int:
	var forward: Vector2 = heading(facing)
	var clearance: float = INF
	for axis: int in range(2):
		if forward[axis] > 0.00001:
			clearance = minf(clearance, float(BOARD_SIZE[axis] - 1 - origin[axis]) / forward[axis])
		elif forward[axis] < -0.00001:
			clearance = minf(clearance, float(origin[axis]) / -forward[axis])
	if clearance > EDGE_ASSIST_DISTANCE:
		return 0
	return clampi(floori(EDGE_ASSIST_DISTANCE - clearance) + 1, 1, MAX_EDGE_TURN_BONUS)


static func clear_segment(origin: Vector2i, target: Vector2i, occupied: Array[Vector2i]) -> bool:
	for cell: Vector2i in occupied:
		if _intersects_cell(Vector2(origin), Vector2(target), Vector2(cell)):
			return false
	return true


static func _intersects_cell(origin: Vector2, target: Vector2, center: Vector2) -> bool:
	var direction: Vector2 = target - origin
	var entry: float = 0.0
	var leave: float = 1.0
	for axis: int in range(2):
		var low: float = center[axis] - 0.5
		var high: float = center[axis] + 0.5
		if is_zero_approx(direction[axis]):
			if origin[axis] < low or origin[axis] > high:
				return false
		else:
			var a: float = (low - origin[axis]) / direction[axis]
			var b: float = (high - origin[axis]) / direction[axis]
			entry = maxf(entry, minf(a, b))
			leave = minf(leave, maxf(a, b))
			if entry > leave:
				return false
	return true
