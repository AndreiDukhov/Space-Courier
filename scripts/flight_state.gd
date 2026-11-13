extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Rules = preload("res://scripts/order_rules.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const Traffic = preload("res://scripts/traffic_state.gd")


static func initial(previous_npcs: Dictionary = {}) -> Dictionary:
	var npcs: Dictionary = {}
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if previous_npcs.has(npc["id"]):
			npcs[npc["id"]] = previous_npcs[npc["id"]].duplicate(true)
		else:
			npcs[npc["id"]] = {"pos": Motion.coordinates(Motion.point(npc["pos"])), "waypoint": 0, "weapons": Loadouts.roll(Loadouts.enemy_for_npc(str(npc["id"])))}
			npcs[npc["id"]].merge(Traffic.initial(npc))
	return {"pos": Motion.coordinates(Motion.SPAWN), "target": Motion.coordinates(Motion.SPAWN), "paused": false, "npcs": npcs, "encounter": "", "defeated_npcs": [], "autopilot": {}, "map_scale": Motion.MAP_SCALE}


static func migrate(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	var previous_scale: float = float(result.get("map_scale", 1.0))
	if not is_finite(previous_scale) or previous_scale <= 0.0:
		return result
	var factor: float = float(Motion.MAP_SCALE) / previous_scale
	for field: String in ["pos", "target"]:
		if result.get(field) is Array and result[field].size() == 2 and Rules.finite_number(result[field][0]) and Rules.finite_number(result[field][1]):
			result[field] = Motion.coordinates(Motion.point(result[field]) * factor)
	result["map_scale"] = Motion.MAP_SCALE
	if not result.has("autopilot"):
		result["autopilot"] = {}
	var entries: Variant = result.get("npcs")
	var defaults: Dictionary = initial()["npcs"]
	if entries is Dictionary:
		for entry: Variant in entries.values():
			if entry is Dictionary and entry.get("pos") is Array and entry["pos"].size() == 2 and Rules.finite_number(entry["pos"][0]) and Rules.finite_number(entry["pos"][1]):
				entry["pos"] = Motion.coordinates(Motion.point(entry["pos"]) * factor)
		for npc: Dictionary in DataLoader.get_records("npcs"):
			if not entries.has(npc["id"]):
				entries[npc["id"]] = defaults[npc["id"]]
			elif entries[npc["id"]] is Dictionary and entries[npc["id"]].size() == 3 and entries[npc["id"]].has_all(["pos", "waypoint", "weapons"]):
				var extra: Dictionary = Traffic.initial(npc)
				extra["status"] = "cruise"
				extra["destination"] = ""
				entries[npc["id"]].merge(extra)
	return result


static func reset_player(previous: Dictionary, position: Vector2 = Motion.SPAWN) -> Dictionary:
	var result: Dictionary = initial(previous.get("npcs", {}))
	result["pos"] = Motion.coordinates(Motion.bounded(position))
	result["target"] = result["pos"].duplicate()
	result["defeated_npcs"] = previous.get("defeated_npcs", []).duplicate()
	return result


static func expand_population(value: Dictionary) -> Dictionary:
	var entries: Variant = value.get("npcs")
	if not entries is Dictionary:
		return value
	var missing: Array[String] = []
	for npc: Dictionary in DataLoader.files.get("res://data/npcs/pirates.json", []):
		if not entries.has(npc["id"]):
			missing.append(str(npc["id"]))
	if missing.is_empty():
		return value
	var result: Dictionary = value.duplicate(true)
	var expanded: Dictionary = initial()["npcs"]
	for npc_id: String in missing:
		result["npcs"][npc_id] = expanded[npc_id]
	return result


static func upgrade_traffic(value: Dictionary) -> Dictionary:
	if not value.get("npcs") is Dictionary:
		return value
	var result: Dictionary = value.duplicate(true)
	for entry: Variant in result["npcs"].values():
		if entry is Dictionary and entry.size() == 8 and entry.has_all(["pos", "waypoint", "weapons", "status", "destination", "target", "timer", "cooldown"]):
			entry.merge({"partner": "", "pair_timer": 0.0})
	return result


static func normalize_numbers(value: Dictionary) -> void:
	value["map_scale"] = int(value["map_scale"])
	for field: String in ["pos", "target"]:
		value[field] = Motion.coordinates(Motion.point(value[field]))
	for npc: Dictionary in value["npcs"].values():
		npc["pos"] = Motion.coordinates(Motion.point(npc["pos"]))
		npc["waypoint"] = int(npc["waypoint"])
		for field: String in ["timer", "cooldown", "pair_timer"]:
			npc[field] = float(Vector2(float(npc[field]), 0).x)


static func valid_point(value: Variant) -> bool:
	if not value is Array or value.size() != 2 or not Rules.finite_number(value[0]) or not Rules.finite_number(value[1]):
		return false
	return Motion.point(value) == Motion.bounded(Motion.point(value))


static func valid_save(value: Variant, system_id: String) -> bool:
	if not value is Dictionary or value.size() != 8 or not value.has_all(["pos", "target", "paused", "npcs", "encounter", "defeated_npcs", "autopilot", "map_scale"]):
		return false
	if not Rules.whole_number(value["map_scale"]) or value["map_scale"] != Motion.MAP_SCALE:
		return false
	if not value["defeated_npcs"] is Array:
		return false
	var defeated: Dictionary = {}
	for npc_id: Variant in value["defeated_npcs"]:
		if not npc_id is String or not DataLoader.record_sources.has("npcs/" + str(npc_id)) or defeated.has(npc_id):
			return false
		defeated[npc_id] = true
	if not valid_point(value["pos"]) or not valid_point(value["target"]) or not value["paused"] is bool:
		return false
	var npcs: Variant = value["npcs"]
	if not npcs is Dictionary or npcs.size() != DataLoader.get_records("npcs").size():
		return false
	for npc_id: Variant in npcs:
		if not npc_id is String or not DataLoader.record_sources.has("npcs/" + str(npc_id)):
			return false
		var entry: Variant = npcs[npc_id]
		if not entry is Dictionary or entry.size() != 10 or not entry.has_all(["pos", "waypoint", "weapons"]):
			return false
		if not Traffic.valid(entry, DataLoader.get_record(npc_id), npcs):
			return false
		if not Loadouts.valid(Loadouts.enemy_for_npc(npc_id), entry["weapons"]):
			return false
		if not valid_point(entry["pos"]) or not Rules.whole_number(entry["waypoint"]):
			return false
		if entry["waypoint"] < 0 or entry["waypoint"] >= DataLoader.get_record(npc_id)["waypoints"].size():
			return false
	if not _valid_autopilot(value["autopilot"], system_id):
		return false
	var event_id: Variant = value["encounter"]
	if not event_id is String:
		return false
	if event_id.is_empty():
		return true
	if not DataLoader.record_sources.has("events/" + str(event_id)):
		return false
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["system"] == system_id and npc["event"] == event_id and npc["id"] not in value["defeated_npcs"] and npcs[npc["id"]]["status"] not in ["landed", "destroyed"]:
			return true
	var system: Dictionary = DataLoader.get_record(system_id)
	for object: Dictionary in system.get("objects", []):
		if object.get("type") == "event_marker" and object.get("event") == event_id:
			return true
	return event_id in system.get("event_pool", [])


static func _valid_autopilot(value: Variant, system_id: String) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if value.size() != 2 or not value.get("destination") is String or not value.get("routes") is Array or value["routes"].is_empty():
		return false
	var visited: Array[String] = [system_id]
	for route_id: Variant in value["routes"]:
		if not route_id is String:
			return false
		var route: Dictionary = DataLoader.get_record(route_id)
		if route.get("from") != system_id or route.get("to") in visited:
			return false
		system_id = str(route["to"])
		visited.append(system_id)
	return value["destination"] == system_id
