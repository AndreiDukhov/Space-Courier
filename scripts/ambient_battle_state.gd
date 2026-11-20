extends RefCounted

const Rules = preload("res://scripts/order_rules.gd")


static func find(battle_id: String, battles: Array) -> Dictionary:
	for battle: Dictionary in battles:
		if battle["id"] == battle_id:
			return battle
	return {}


static func for_npc(npc_id: String, battles: Array) -> Dictionary:
	for battle: Dictionary in battles:
		for side: Array in battle["sides"]:
			if npc_id in side:
				return battle
	return {}


static func members(battle: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for side: Array in battle["sides"]:
		result.append_array(side)
	return result


static func valid(battles: Variant, entries: Dictionary, defeated: Array) -> bool:
	if not battles is Array:
		return false
	var ids: Dictionary = {}
	var participants: Dictionary = {}
	for battle: Variant in battles:
		if not battle is Dictionary or battle.size() != 4 or not battle.has_all(["id", "system", "sides", "remaining"]):
			return false
		if not battle["id"] is String or battle["id"].is_empty() or ids.has(battle["id"]) or not battle["system"] is String or not DataLoader.record_sources.has("systems/" + str(battle["system"])):
			return false
		ids[battle["id"]] = true
		if not Rules.finite_number(battle["remaining"]) or battle["remaining"] <= 0 or battle["remaining"] > float(DataLoader.get_record("ambient_battle_rules")["duration"]):
			return false
		if not battle["sides"] is Array or battle["sides"].size() != 2:
			return false
		for side: Variant in battle["sides"]:
			if not side is Array or side.is_empty() or side.size() > 2:
				return false
			for npc_id: Variant in side:
				if not npc_id is String or participants.has(npc_id) or npc_id in defeated or not entries.has(npc_id):
					return false
				if DataLoader.get_record(npc_id).get("system") != battle["system"] or entries[npc_id].get("status") != "battle":
					return false
				participants[npc_id] = true
		for index: int in range(2):
			for npc_id: String in battle["sides"][index]:
				if entries[npc_id].get("target") not in battle["sides"][1 - index]:
					return false
	for npc_id: String in entries:
		if entries[npc_id].get("status") == "battle" and not participants.has(npc_id):
			return false
	return true
