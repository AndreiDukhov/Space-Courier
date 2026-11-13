extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Rules = preload("res://scripts/order_rules.gd")
const STATUSES: Array[String] = ["cruise", "landing", "landed", "chase", "destroyed"]
const FIELDS: Array[String] = ["status", "destination", "target", "timer", "cooldown", "partner", "pair_timer"]


static func planets(system_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object: Dictionary in DataLoader.get_record(system_id).get("objects", []):
		if object.get("type") == "planet" and object.get("inhabited", false):
			result.append(object)
	return result


static func initial(npc: Dictionary) -> Dictionary:
	var planet_id: String = ""
	for planet: Dictionary in planets(str(npc["system"])):
		if Motion.point(planet["pos"]).distance_to(Motion.point(npc["pos"])) < 1.0:
			planet_id = str(planet["id"])
	var delays: Array = DataLoader.get_record(str(npc["system"]))["traffic"]["spawn_delay"]
	var timer: float = randf_range(float(delays[0]), float(delays[1])) if not planet_id.is_empty() else randf_range(35.0, 75.0)
	return {"status": "landed" if not planet_id.is_empty() else "cruise", "destination": planet_id, "target": "", "timer": float(Vector2(timer, 0).x), "cooldown": 0.0, "partner": "", "pair_timer": 0.0}


static func valid(entry: Dictionary, npc: Dictionary, all_npcs: Dictionary) -> bool:
	if not entry.has_all(FIELDS) or entry["status"] not in STATUSES or not entry["destination"] is String or not entry["target"] is String:
		return false
	for field: String in ["timer", "cooldown", "pair_timer"]:
		if not Rules.finite_number(entry[field]) or float(entry[field]) < 0.0:
			return false
	if not entry["partner"] is String:
		return false
	if npc["role"] != "pirate" and (not entry["partner"].is_empty() or entry["pair_timer"] != 0):
		return false
	if not entry["partner"].is_empty():
		var partner: Variant = all_npcs.get(entry["partner"])
		var blueprint: Dictionary = DataLoader.get_record(str(entry["partner"]))
		if not partner is Dictionary or blueprint.get("role") != "pirate" or blueprint.get("system") != npc["system"] or entry["partner"] == npc["id"]:
			return false
		if partner.get("partner") != npc["id"] or partner.get("status") == "destroyed" or entry["status"] == "destroyed" or entry["pair_timer"] <= 0:
			return false
	var planet_ids: Array[String] = []
	for planet: Dictionary in planets(str(npc["system"])):
		planet_ids.append(str(planet["id"]))
	if not entry["destination"].is_empty() and entry["destination"] not in planet_ids:
		return false
	if entry["status"] in ["landed", "landing"] and (npc["role"] != "civilian" or entry["destination"].is_empty()):
		return false
	if entry["status"] == "landed":
		for planet: Dictionary in planets(str(npc["system"])):
			if planet["id"] == entry["destination"] and Motion.point(entry["pos"]).distance_to(Motion.point(planet["pos"])) > 1.0:
				return false
	if entry["status"] != "chase":
		return entry["target"].is_empty()
	if npc["role"] not in ["pirate", "patrol"] or entry["target"].is_empty():
		return false
	if entry["target"] == "player":
		return npc["role"] == "pirate"
	var victim: Dictionary = DataLoader.get_record(str(entry["target"]))
	var role: String = "pirate" if npc["role"] == "patrol" else "civilian"
	var statuses: Array = ["cruise", "chase"] if npc["role"] == "patrol" else ["cruise", "landing"]
	var victim_entry: Variant = all_npcs.get(entry["target"])
	return victim_entry is Dictionary and victim.get("system") == npc["system"] and victim.get("role") == role and victim_entry.get("status") in statuses
