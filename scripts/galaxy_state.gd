extends RefCounted

const INITIAL_SYSTEM: String = "sys_earth"
const HUB_PLANET: String = "earth_1"
const STATUSES: Array[String] = ["hidden", "seen", "visited"]
const Rules = preload("res://scripts/order_rules.gd")


static func initial_systems() -> Dictionary:
	var result: Dictionary = {}
	for system: Dictionary in DataLoader.get_records("systems"):
		result[system["id"]] = "hidden"
	result[INITIAL_SYSTEM] = "visited"
	for route: Dictionary in DataLoader.get_records("routes"):
		if route["known"]:
			for endpoint: String in [str(route["from"]), str(route["to"])]:
				if result[endpoint] == "hidden":
					result[endpoint] = "seen"
	return result


static func initial_routes(field_name: String) -> Array[String]:
	var result: Array[String] = []
	for route: Dictionary in DataLoader.get_records("routes"):
		if route[field_name]:
			result.append(str(route["id"]))
	return result


static func valid_save(save: Dictionary) -> bool:
	var systems: Variant = save.get("systems")
	if not systems is Dictionary or systems.size() != DataLoader.get_records("systems").size():
		return false
	for system_id: String in systems:
		if not DataLoader.record_sources.has("systems/" + system_id) or systems[system_id] not in STATUSES:
			return false
	if not save.get("current_system") is String or systems.get(save["current_system"]) != "visited":
		return false
	if save["current_system"] != INITIAL_SYSTEM and DataLoader.get_record(str(save.get("location", ""))).get("area") != "ship":
		return false
	for field: String in ["known_routes", "public_routes"]:
		var routes: Variant = save.get(field)
		if not routes is Array:
			return false
		var seen: Dictionary = {}
		for route_id: Variant in routes:
			if not route_id is String or not DataLoader.record_sources.has("routes/" + str(route_id)) or seen.has(route_id):
				return false
			seen[route_id] = true
			var route: Dictionary = DataLoader.get_record(route_id)
			if field == "known_routes" and (systems.get(route["from"]) == "hidden" or systems.get(route["to"]) == "hidden"):
				return false
	var fuel: Variant = save.get("ship", {}).get("fuel")
	return fuel is Dictionary and Rules.finite_number(fuel.get("current")) and Rules.whole_number(fuel.get("max")) and fuel["max"] > 0 and fuel["current"] >= 0 and fuel["current"] <= fuel["max"]
