extends RefCounted

const CARGO_FUEL_FACTOR: float = 0.05
const BOOST_MULTIPLIER: float = 1.5


static func fuel_cost(base: float, mass: float, boost: bool = false) -> int:
	return ceili(base * (1.0 + CARGO_FUEL_FACTOR * mass) * (BOOST_MULTIPLIER if boost else 1.0))


static func estimate(route: Dictionary, mass: float, known: bool, boost: bool = false) -> int:
	var fuel: Dictionary = route["fuel"]
	var base: float = float(fuel["true"]) if known else (float(fuel["min"]) + float(fuel["max"])) / 2.0
	return fuel_cost(base, mass, boost)


static func shortest_path(origin: String, destination: String, routes: Array[Dictionary], known: Array, mass: float, boost: bool = false) -> Array[String]:
	if origin == destination:
		return []
	var distance: Dictionary = {origin: 0}
	var previous: Dictionary = {}
	var pending: Array[String] = [origin]
	while not pending.is_empty():
		var current: String = pending[0]
		for candidate: String in pending:
			if distance[candidate] < distance[current]:
				current = candidate
		pending.erase(current)
		if current == destination:
			break
		for route: Dictionary in routes:
			if route["from"] != current:
				continue
			var target: String = str(route["to"])
			var cost: int = int(distance[current]) + estimate(route, mass, route["id"] in known, boost)
			if cost < int(distance.get(target, 2147483647)):
				distance[target] = cost
				previous[target] = route
				if target not in pending:
					pending.append(target)
	if not previous.has(destination):
		return []
	var result: Array[String] = []
	var current: String = destination
	while current != origin:
		var route: Dictionary = previous[current]
		result.push_front(str(route["id"]))
		current = str(route["from"])
	return result
