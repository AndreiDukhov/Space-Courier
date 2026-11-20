extends RefCounted

const State = preload("res://scripts/ambient_battle_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Pairs = preload("res://scripts/pirate_pairs.gd")


static func begin(attacker: String, defender: String, entries: Dictionary, battles: Array, events: Array[Dictionary]) -> void:
	if not Conditions.can_start_ambient_battle(attacker, defender, entries, battles):
		return
	var sides: Array = [Conditions.ambient_battle_side(attacker, entries), Conditions.ambient_battle_side(defender, entries)]
	var battle: Dictionary = {"id": "battle_" + attacker + "_" + defender, "system": DataLoader.get_record(attacker)["system"], "sides": sides, "remaining": float(DataLoader.get_record("ambient_battle_rules")["duration"])}
	battles.append(battle)
	for index: int in range(2):
		for npc_id: String in sides[index]:
			entries[npc_id]["status"] = "battle"
			entries[npc_id]["target"] = sides[1 - index][0]
			entries[npc_id]["timer"] = 0.0
	events.append({"kind": "battle", "pos": entries[attacker]["pos"].duplicate(), "npc": attacker})


static func advance(battles: Array, entries: Dictionary, system_id: String, delta: float, events: Array[Dictionary]) -> Array:
	var remaining: Array = []
	for battle: Dictionary in battles:
		if battle["system"] != system_id:
			remaining.append(battle)
			continue
		battle["remaining"] = float(Vector2(maxf(0.0, float(battle["remaining"]) - delta), 0).x)
		if battle["remaining"] > 0:
			remaining.append(battle)
		else:
			_resolve(battle, entries, events)
	return remaining


static func _resolve(battle: Dictionary, entries: Dictionary, events: Array[Dictionary]) -> void:
	var attacker: String = str(battle["sides"][0][0])
	var defender: String = str(battle["sides"][1][0])
	var npc: Dictionary = DataLoader.get_record(attacker)
	var victim: String = ""
	var respawn: float = 95.0
	if npc["role"] == "patrol":
		victim = defender if randf() < float(npc["policing"]["pirate_loss_chance"]) else attacker
		respawn = float(npc["policing"]["respawn_seconds"])
	elif npc["role"] == "pirate" and randf() < float(npc["piracy"]["destroy_chance"]):
		victim = defender
		respawn = randf_range(75.0, 120.0)
	else:
		events.append({"kind": "paid", "pos": entries[defender]["pos"].duplicate(), "npc": defender})
	resume(battle, entries)
	if not victim.is_empty():
		Pairs.release(victim, entries)
		entries[victim].merge({"status": "destroyed", "target": "", "destination": "", "timer": float(Vector2(respawn, 0).x), "cooldown": 0.0}, true)
		events.append({"kind": "destroyed", "pos": entries[victim]["pos"].duplicate(), "npc": victim})


static func resume(battle: Dictionary, entries: Dictionary) -> void:
	for npc_id: String in State.members(battle):
		var npc: Dictionary = DataLoader.get_record(npc_id)
		var entry: Dictionary = entries[npc_id]
		entry["status"] = "landing" if npc["role"] == "civilian" and not entry["destination"].is_empty() else "cruise"
		entry["target"] = ""
		entry["timer"] = float(Vector2(randf_range(35.0, 75.0), 0).x) if npc["role"] == "civilian" else 0.0
		entry["cooldown"] = float(npc.get("piracy", npc.get("policing", {})).get("cooldown", 0))


static func finish_player(combat: Dictionary, entries: Dictionary, battles: Array) -> Array:
	var battle: Dictionary = State.find(str(combat.get("battle_id", "")), battles)
	if battle.is_empty():
		return battles
	resume(battle, entries)
	var result: Array = []
	for other: Dictionary in battles:
		if other["id"] != battle["id"]:
			result.append(other)
	return result
