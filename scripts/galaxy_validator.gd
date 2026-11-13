extends RefCounted

const Rules = preload("res://scripts/order_rules.gd")
const State = preload("res://scripts/galaxy_state.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Celestials = preload("res://scripts/celestial_validator.gd")
const SpaceContent = preload("res://scripts/space_content_validator.gd")


static func validate(groups: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var systems: Dictionary = {}
	var planets: Dictionary = {}
	var route_index: Dictionary = {}
	for route: Dictionary in groups.get("routes", []):
		route_index[route.get("id", "")] = route
	var gate_routes: Dictionary = {}
	var body_ids: Dictionary = {}
	for system: Dictionary in groups.get("systems", []):
		var system_id: String = str(system.get("id", ""))
		systems[system_id] = system
		for message: String in SpaceContent.validate_system(system):
			errors.append(system_id + ": " + message)
		for message: String in Celestials.validate(system):
			errors.append(system_id + ": " + message)
		if not system.get("name") is String or not _point(system.get("map_pos")):
			errors.append(system_id + ": invalid system name or map_pos")
		var objects: Variant = system.get("objects")
		if not objects is Array:
			errors.append(system_id + ": objects must be an array")
			continue
		for object: Variant in objects:
			if object is Dictionary and object.get("type") in ["planet", "star", "station"]:
				var body_id: Variant = object.get("id")
				if not body_id is String or str(body_id).is_empty() or not object.get("name") is String or str(object["name"]).is_empty():
					errors.append(system_id + ": celestial body requires an id and name")
				elif body_ids.has(body_id):
					errors.append("Duplicate celestial id: " + str(body_id))
				else:
					body_ids[body_id] = true
			if not object is Dictionary or not _point(object.get("pos")):
				errors.append(system_id + ": invalid system object position")
			elif object.get("type") == "planet":
				var planet_id: Variant = object.get("id")
				if not planet_id is String or str(planet_id).is_empty() or not object.get("name") is String or str(object["name"]).is_empty():
					errors.append(system_id + ": planet requires an id and name")
				elif planets.has(planet_id):
					errors.append("Duplicate planet id: " + str(planet_id))
				else:
					planets[planet_id] = system_id
			elif object.get("type") == "gate":
				var route_id: String = str(object.get("to_route", ""))
				if route_index.get(route_id, {}).get("from") != system_id:
					errors.append(system_id + ": gate route must originate in its system")
				if gate_routes.has(route_id):
					errors.append("Duplicate gate for route: " + route_id)
				gate_routes[route_id] = true
				var pos: Vector2 = Motion.point(object["pos"])
				if Motion.bounded(pos) != pos or minf(minf(pos.x, Motion.BOUNDS.x - pos.x), minf(pos.y, Motion.BOUNDS.y - pos.y)) > 80.0 * Motion.MAP_SCALE:
					errors.append(system_id + ": wormholes must be near the system boundary")
		var refuel: Variant = system.get("refuel")
		if not refuel is Dictionary or not refuel.get("available") is bool or not Rules.whole_number(refuel.get("price_per_unit")) or refuel["price_per_unit"] < 0:
			errors.append(system_id + ": invalid refuel data")
	if not systems.is_empty() and planets.get(State.HUB_PLANET) != State.INITIAL_SYSTEM:
		errors.append("The hub planet must exist in the initial system: " + State.HUB_PLANET)
	for order: Dictionary in groups.get("orders", []):
		if order.get("source") == "shop":
			continue
		if planets.get(order.get("to_planet"), "") != order.get("to"):
			errors.append(str(order.get("id", "")) + ": to_planet must belong to the destination system")
	var routes: Array = groups.get("routes", [])
	for route: Dictionary in routes:
		_validate_route(route, errors)
		if not gate_routes.has(route.get("id")):
			errors.append(str(route.get("id", "")) + ": route requires a gate in its origin system")
	if not systems.is_empty() or not routes.is_empty():
		_check_return_paths(systems, routes, errors)
	return errors


static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Rules.finite_number(value[0]) and Rules.finite_number(value[1])


static func _validate_route(route: Dictionary, errors: Array[String]) -> void:
	var prefix: String = str(route.get("id", "")) + ": "
	if route.get("directed", true) != true:
		errors.append(prefix + "routes must be directed; define reverse edges separately")
	for field: String in ["known", "public"]:
		if not route.get(field) is bool:
			errors.append(prefix + field + " must be boolean")
	for field: String in ["days", "map_value"]:
		if not Rules.whole_number(route.get(field)) or route[field] < (1 if field == "days" else 0):
			errors.append(prefix + "invalid " + field)
	if not Rules.finite_number(route.get("hazard")) or route["hazard"] < 0 or route["hazard"] > 1:
		errors.append(prefix + "hazard must be between zero and one")
	var fuel: Variant = route.get("fuel")
	if not fuel is Dictionary:
		errors.append(prefix + "fuel must be an object")
		return
	for field: String in ["min", "max", "true"]:
		if not Rules.whole_number(fuel.get(field)) or fuel[field] <= 0:
			errors.append(prefix + "fuel costs must be positive integers")
			return
	if fuel["min"] > fuel["true"] or fuel["true"] > fuel["max"]:
		errors.append(prefix + "true fuel must be inside the min-max range")


static func _check_return_paths(systems: Dictionary, routes: Array, errors: Array[String]) -> void:
	if not systems.has(State.INITIAL_SYSTEM):
		errors.append("Galaxy is missing the hub system: " + State.INITIAL_SYSTEM)
		return
	var reachable: Dictionary = {State.INITIAL_SYSTEM: true}
	var pending: Array[String] = [State.INITIAL_SYSTEM]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		for route: Dictionary in routes:
			var origin: String = str(route.get("from", ""))
			if route.get("to") == current and systems.has(origin) and not reachable.has(origin):
				reachable[origin] = true
				pending.append(origin)
	for system_id: String in systems:
		if not reachable.has(system_id):
			errors.append(system_id + ": no directed return path to the hub")
