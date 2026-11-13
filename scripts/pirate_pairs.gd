extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")


static func step(local: Array[Dictionary], entries: Dictionary, delta: float) -> void:
	for npc: Dictionary in local:
		var entry: Dictionary = entries[npc["id"]]
		entry["pair_timer"] = maxf(0.0, float(entry["pair_timer"]) - delta)
	cleanup(local, entries)
	for npc: Dictionary in local:
		var entry: Dictionary = entries[npc["id"]]
		if npc["role"] != "pirate" or not entry["partner"].is_empty() or entry["pair_timer"] > 0 or entry["cooldown"] > 0 or entry["status"] != "cruise":
			continue
		var nearest: float = INF
		var partner: Dictionary = {}
		if randf() < float(npc["pairing"]["chance"]):
			for other: Dictionary in local:
				if Conditions.can_form_pirate_pair(npc, other, entries):
					var distance: float = Motion.point(entry["pos"]).distance_to(Motion.point(entries[other["id"]]["pos"]))
					if distance < nearest:
						nearest = distance
						partner = other
		if partner.is_empty():
			entry["pair_timer"] = float(npc["pairing"]["cooldown"])
		else:
			var duration: float = minf(float(npc["pairing"]["duration"]), float(partner["pairing"]["duration"]))
			entry["partner"] = partner["id"]
			entry["pair_timer"] = duration
			entries[partner["id"]]["partner"] = npc["id"]
			entries[partner["id"]]["pair_timer"] = duration


static func cleanup(local: Array[Dictionary], entries: Dictionary) -> void:
	for npc: Dictionary in local:
		if not entries[npc["id"]]["partner"].is_empty() and not Conditions.can_keep_pirate_pair(npc, entries):
			release(str(npc["id"]), entries)


static func release(npc_id: String, entries: Dictionary) -> void:
	var entry: Dictionary = entries[npc_id]
	var partner_id: String = str(entry["partner"])
	entry["partner"] = ""
	entry["pair_timer"] = float(DataLoader.get_record(npc_id).get("pairing", {}).get("cooldown", 0))
	if entries.has(partner_id) and entries[partner_id]["partner"] == npc_id:
		entries[partner_id]["partner"] = ""
		entries[partner_id]["pair_timer"] = float(DataLoader.get_record(partner_id)["pairing"]["cooldown"])


static func is_follower(npc: Dictionary, entry: Dictionary) -> bool:
	return not entry["partner"].is_empty() and str(npc["id"]) > str(entry["partner"])


static func follow_target(npc: Dictionary, entries: Dictionary) -> Vector2:
	var leader: Dictionary = entries[entries[npc["id"]]["partner"]]
	var blueprint: Dictionary = DataLoader.get_record(str(entries[npc["id"]]["partner"]))
	var goal: Vector2 = Motion.point(blueprint["waypoints"][int(leader["waypoint"])])
	if leader["status"] == "chase":
		goal = Motion.point(GameState.state["flight"]["pos"] if leader["target"] == "player" else entries[leader["target"]]["pos"])
	var heading: Vector2 = (goal - Motion.point(leader["pos"])).normalized()
	if heading.is_zero_approx():
		heading = Vector2.RIGHT
	var spacing: float = float(npc["pairing"]["spacing"])
	return Motion.bounded(Motion.point(leader["pos"]) + heading.orthogonal() * spacing - heading * spacing * 0.4)
