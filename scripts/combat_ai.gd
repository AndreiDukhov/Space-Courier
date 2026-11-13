extends RefCounted

const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Routes = preload("res://scripts/combat_routes.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")


static func plan(vessel: Dictionary, turn: Dictionary, remaining: int, settings: Dictionary, target: Dictionary, weapons: Array[Dictionary], ap: int = Math.ACTION_POINTS, fired: Array = []) -> Array[Vector2i]:
	var ordered: Array[Dictionary] = Math.strongest_first(weapons)
	var origin: Vector2i = Math.cell(vessel["pos"])
	var target_cell: Vector2i = Math.cell(target["pos"])
	var states: Array[Dictionary] = [{"pos": origin, "facing": int(vessel["facing"]), "previous": -1, "spent": 0}]
	var buckets: Array = []
	for _cost: int in range(remaining + 1):
		buckets.append([])
	buckets[0].append(0)
	var costs: Dictionary = {Vector3i(origin.x, origin.y, int(vessel["facing"])): 0}
	var best: int = 0
	var best_score: Array[float] = _score(vessel, target, ordered, ap, fired, 0)
	var best_moving: int = -1
	var moving_score: Array[float] = []
	var best_turning: int = -1
	var turning_score: Array[float] = []
	var initial_distance: float = Math.distance(origin, target_cell)
	for spent: int in range(remaining + 1):
		for index: int in buckets[spent]:
			var state: Dictionary = states[index]
			var position: Vector2i = state["pos"]
			var key: Vector3i = Vector3i(position.x, position.y, int(state["facing"]))
			if costs[key] != spent:
				continue
			var current: Dictionary = {"pos": Math.coordinates(position), "facing": int(state["facing"])}
			var score: Array[float] = _score(current, target, ordered, ap, fired, spent)
			if _better(score, best_score):
				best = index
				best_score = score
			var distance: float = Math.distance(position, target_cell)
			if spent > 0 and distance < initial_distance - 0.00001 and (best_moving < 0 or _better(score, moving_score)):
				best_moving = index
				moving_score = score
			if spent > 0:
				var error: float = absf(Movement.heading(int(state["facing"])).angle_to(Vector2(target_cell - position)))
				var turn_score: Array[float] = [0.0, -error, -distance, -float(spent)]
				if best_turning < 0 or _better(turn_score, turning_score):
					best_turning = index
					turning_score = turn_score
			var budget: int = remaining - spent
			for z: int in range(maxi(0, position.y - budget), mini(Math.HEIGHT, position.y + budget + 1)):
				for x: int in range(maxi(0, position.x - budget), mini(Math.WIDTH, position.x + budget + 1)):
					var cell: Vector2i = Vector2i(x, z)
					var route: Array[Vector2i] = Conditions.vessel_move_path(current, cell, turn, budget, settings, target_cell)
					if route.is_empty():
						continue
					var facing: int = Routes.arrival_facing(route)
					var next_cost: int = spent + Movement.cost(position, cell)
					var next_key: Vector3i = Vector3i(x, z, facing)
					if costs.has(next_key) and int(costs[next_key]) <= next_cost:
						continue
					costs[next_key] = next_cost
					states.append({"pos": cell, "facing": facing, "previous": index, "spent": next_cost})
					buckets[next_cost].append(states.size() - 1)
	if best_score[0] == 0.0:
		if best_moving >= 0:
			best = best_moving
		elif best_turning >= 0:
			best = best_turning
	var result: Array[Vector2i] = []
	while int(states[best]["previous"]) >= 0:
		result.push_front(states[best]["pos"])
		best = int(states[best]["previous"])
	return result


static func firing_order(vessel: Dictionary, target: Dictionary, weapons: Array[Dictionary], ap: int, fired: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon: Dictionary in Math.strongest_first(weapons):
		if Conditions.can_fire_weapon(vessel, target, weapon, ap, fired):
			result.append(weapon)
			ap -= int(weapon["ap_cost"])
	return result


static func _score(vessel: Dictionary, target: Dictionary, weapons: Array[Dictionary], ap: int, fired: Array, spent: int) -> Array[float]:
	var origin: Vector2i = Math.cell(vessel["pos"])
	var destination: Vector2i = Math.cell(target["pos"])
	var order: Array[Dictionary] = firing_order(vessel, target, weapons, ap, fired)
	var distance: float = Math.distance(origin, destination)
	var free_bow: bool = Math.inside(origin + Movement.DIRECTIONS[int(vessel["facing"])])
	if not order.is_empty():
		var expected: float = 0.0
		for weapon: Dictionary in order:
			expected += Math.weapon_power(weapon) * Math.accuracy(weapon, distance)
		return [Math.weapon_power(order[0]), expected, 1.0 if free_bow else 0.0, -float(spent)]
	var angle: float = absf(Movement.heading(int(vessel["facing"])).angle_to(Vector2(destination - origin)))
	return [0.0, -distance, -angle, -float(spent)]


static func _better(score: Array[float], previous: Array[float]) -> bool:
	for index: int in range(score.size()):
		if not is_equal_approx(score[index], previous[index]):
			return score[index] > previous[index]
	return false
