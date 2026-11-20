extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const NpcMotion = preload("res://scripts/npc_motion.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Battles = preload("res://scripts/ambient_battles.gd")


static func step(npc: Dictionary, local: Array[Dictionary], entries: Dictionary, delta: float, events: Array[Dictionary], battles: Array) -> bool:
	var entry: Dictionary = entries[npc["id"]]
	if entry["status"] == "chase" and not Conditions.can_police_target(npc, entry, str(entry["target"]), entries, false):
		release(npc, entry)
	if entry["status"] == "cruise" and entry["cooldown"] <= 0:
		var best: String = ""
		var nearest: float = INF
		for target: Dictionary in local:
			if Conditions.can_police_target(npc, entry, str(target["id"]), entries):
				var distance: float = Motion.point(entry["pos"]).distance_to(Motion.point(entries[target["id"]]["pos"]))
				if distance < nearest:
					nearest = distance
					best = str(target["id"])
		if not best.is_empty():
			entry["status"] = "chase"
			entry["target"] = best
			entry["timer"] = 0.0
			events.append({"kind": "pursuit", "pos": entry["pos"].duplicate(), "npc": npc["id"]})
	if entry["status"] != "chase":
		return false
	var target_id: String = str(entry["target"])
	var target: Dictionary = entries[target_id]
	var goal: Vector2 = Motion.point(target["pos"])
	entry["pos"] = Motion.coordinates(NpcMotion.toward(Motion.point(entry["pos"]), goal, str(npc["system"]), float(npc["speed"]), delta))
	if Motion.point(entry["pos"]).distance_to(goal) > float(npc["policing"]["engage_radius"]):
		entry["timer"] = 0.0
		return true
	entry["timer"] = float(entry["timer"]) + delta
	if entry["timer"] >= float(npc["policing"]["resolve_seconds"]):
		Battles.begin(str(npc["id"]), target_id, entries, battles, events)
	return true


static func release(npc: Dictionary, entry: Dictionary) -> void:
	entry["status"] = "cruise"
	entry["target"] = ""
	entry["timer"] = 0.0
	entry["cooldown"] = float(npc["policing"]["cooldown"])
