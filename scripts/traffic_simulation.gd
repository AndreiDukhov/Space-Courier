extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Patrol = preload("res://scripts/npc_motion.gd")
const Traffic = preload("res://scripts/traffic_state.gd")
const Geometry = preload("res://scripts/space_geometry.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Pairs = preload("res://scripts/pirate_pairs.gd")
const Police = preload("res://scripts/police_simulation.gd")
const ROBBERY_RADIUS: float = 24.0


static func step(delta: float) -> Dictionary:
	var system_id: String = str(GameState.state["current_system"])
	var entries: Dictionary = GameState.state["flight"]["npcs"].duplicate(true)
	var events: Array[Dictionary] = []
	var population: int = 0
	var local: Array[Dictionary] = []
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["system"] == system_id and npc["id"] not in GameState.state["flight"]["defeated_npcs"]:
			local.append(npc)
			if npc["role"] == "civilian" and entries[npc["id"]]["status"] in ["cruise", "landing"]:
				population += 1
	for npc: Dictionary in local:
		var entry: Dictionary = entries[npc["id"]]
		entry["cooldown"] = maxf(0.0, float(entry["cooldown"]) - delta)
		if npc["role"] == "civilian":
			population += _civilian(npc, entry, population, delta, events)
		elif entry["status"] == "destroyed":
			entry["timer"] = maxf(0.0, float(entry["timer"]) - delta)
			if entry["timer"] <= 0:
				entry["status"] = "cruise"
				entry["pos"] = npc["pos"].duplicate()
				entry["waypoint"] = 0
				entry["cooldown"] = float(npc["piracy"]["cooldown"] if npc["role"] == "pirate" else npc["policing"]["cooldown"])
	Pairs.step(local, entries, delta)
	for npc: Dictionary in local:
		if npc["role"] == "pirate" and entries[npc["id"]]["status"] != "destroyed":
			_pirate(npc, entries, delta, events)
	for npc: Dictionary in local:
		if npc["role"] == "patrol" and entries[npc["id"]]["status"] != "destroyed":
			if not Police.step(npc, local, entries, delta, events):
				_patrol(npc, entries[npc["id"]], delta)
	cleanup(local, entries)
	for npc: Dictionary in local:
		for field: String in ["timer", "cooldown", "pair_timer"]:
			entries[npc["id"]][field] = float(Vector2(float(entries[npc["id"]][field]), 0).x)
	return {"npcs": entries, "events": events}


static func _civilian(npc: Dictionary, entry: Dictionary, population: int, delta: float, events: Array[Dictionary]) -> int:
	var config: Dictionary = DataLoader.get_record(str(npc["system"]))["traffic"]
	entry["timer"] = maxf(0.0, float(entry["timer"]) - delta)
	if entry["status"] == "destroyed":
		if entry["timer"] <= 0.0:
			var ports: Array[Dictionary] = Traffic.planets(str(npc["system"]))
			var port: Dictionary = ports[randi_range(0, ports.size() - 1)]
			entry["status"] = "landed"
			entry["destination"] = port["id"]
			entry["pos"] = port["pos"].duplicate()
			entry["timer"] = randf_range(float(config["spawn_delay"][0]), float(config["spawn_delay"][1]))
		return 0
	if entry["status"] == "landed":
		if entry["timer"] <= 0.0:
			if population < int(config["max_active"]) and (population < int(config["min_active"]) or randf() < 0.65):
				entry["status"] = "cruise"
				entry["destination"] = ""
				entry["timer"] = randf_range(35.0, 75.0)
				entry["waypoint"] = randi_range(0, npc["waypoints"].size() - 1)
				events.append({"kind": "takeoff", "pos": entry["pos"].duplicate(), "npc": npc["id"]})
				return 1
			entry["timer"] = randf_range(float(config["spawn_delay"][0]), float(config["spawn_delay"][1]))
		return 0
	if entry["status"] == "cruise" and entry["timer"] <= 0.0:
		if population > int(config["min_active"]) or randf() < 0.3:
			var planets: Array[Dictionary] = Traffic.planets(str(npc["system"]))
			var planet: Dictionary = planets[randi_range(0, planets.size() - 1)]
			entry["status"] = "landing"
			entry["destination"] = planet["id"]
		else:
			entry["timer"] = randf_range(12.0, 24.0)
	if entry["status"] == "landing":
		var planet: Dictionary = Conditions.space_object(str(entry["destination"]), str(npc["system"]))
		var goal: Vector2 = Motion.point(planet["pos"])
		entry["pos"] = Motion.coordinates(_move(npc, entry, goal, delta))
		if Motion.point(entry["pos"]).distance_to(goal) <= 3.0:
			entry["pos"] = planet["pos"].duplicate()
			entry["status"] = "landed"
			entry["timer"] = randf_range(float(config["spawn_delay"][0]), float(config["spawn_delay"][1]))
			events.append({"kind": "landing", "pos": entry["pos"].duplicate(), "npc": npc["id"]})
			return -1
	else:
		_patrol(npc, entry, delta)
	return 0


static func _patrol(npc: Dictionary, entry: Dictionary, delta: float) -> void:
	var origin: Vector2 = Motion.point(entry["pos"])
	var target: Vector2 = Motion.point(npc["waypoints"][int(entry["waypoint"])])
	var safe: Vector2 = Geometry.safe_target(origin, target, str(npc["system"]))
	if safe.distance_to(target) > 0.1:
		entry["pos"] = Motion.coordinates(Motion.advance(origin, safe, float(npc["speed"]), delta))
	else:
		var moved: Dictionary = Patrol.advance(origin, int(entry["waypoint"]), npc["waypoints"], float(npc["speed"]), delta)
		entry["pos"] = moved["pos"]
		entry["waypoint"] = moved["waypoint"]


static func _move(npc: Dictionary, entry: Dictionary, target: Vector2, delta: float) -> Vector2:
	var origin: Vector2 = Motion.point(entry["pos"])
	return Patrol.toward(origin, target, str(npc["system"]), float(npc["speed"]), delta)


static func _pirate(npc: Dictionary, entries: Dictionary, delta: float, events: Array[Dictionary]) -> void:
	var entry: Dictionary = entries[npc["id"]]
	if entry["status"] == "chase" and not Conditions.can_pirate_target(npc, entry, str(entry["target"]), entries, false):
		_release(npc, entry)
	if entry["status"] != "chase" and float(entry["cooldown"]) <= 0.0:
		var best: String = ""
		var nearest: float = INF
		var candidates: Array[String] = ["player"]
		for target: Dictionary in DataLoader.get_records("npcs"):
			if target["system"] == npc["system"] and target["role"] == "civilian":
				candidates.append(str(target["id"]))
		for candidate: String in candidates:
			if not Conditions.can_pirate_target(npc, entry, candidate, entries):
				continue
			var position: Vector2 = Motion.point(GameState.state["flight"]["pos"] if candidate == "player" else entries[candidate]["pos"])
			var distance: float = Motion.point(entry["pos"]).distance_to(position)
			if distance < nearest:
				nearest = distance
				best = candidate
		if not best.is_empty():
			entry["status"] = "chase"
			entry["target"] = best
			entry["timer"] = 0.0
			events.append({"kind": "pursuit", "pos": entry["pos"].duplicate(), "npc": npc["id"]})
	if entry["status"] != "chase":
		if Pairs.is_follower(npc, entry):
			entry["pos"] = Motion.coordinates(_move(npc, entry, Pairs.follow_target(npc, entries), delta))
		else:
			_patrol(npc, entry, delta)
		return
	var target_id: String = str(entry["target"])
	var target: Vector2 = Motion.point(GameState.state["flight"]["pos"] if target_id == "player" else entries[target_id]["pos"])
	var goal: Vector2 = Pairs.follow_target(npc, entries) if Pairs.is_follower(npc, entry) and entries[entry["partner"]]["target"] == target_id else target
	entry["pos"] = Motion.coordinates(_move(npc, entry, goal, delta))
	if target_id == "player":
		return
	if Motion.point(entry["pos"]).distance_to(target) <= ROBBERY_RADIUS:
		entry["timer"] = float(entry["timer"]) + delta
		if float(entry["timer"]) >= float(npc["piracy"]["robbery_seconds"]):
			var victim: Dictionary = entries[target_id]
			if randf() < float(npc["piracy"]["destroy_chance"]):
				victim["status"] = "destroyed"
				victim["target"] = ""
				victim["destination"] = ""
				victim["timer"] = randf_range(75.0, 120.0)
				events.append({"kind": "destroyed", "pos": victim["pos"].duplicate(), "npc": target_id})
			else:
				events.append({"kind": "paid", "pos": victim["pos"].duplicate(), "npc": target_id})
			_release(npc, entry)
	else:
		entry["timer"] = 0.0


static func _release(npc: Dictionary, entry: Dictionary) -> void:
	entry["status"] = "cruise"
	entry["target"] = ""
	entry["timer"] = 0.0
	entry["cooldown"] = float(npc["piracy"]["cooldown"])


static func cleanup(local: Array[Dictionary], entries: Dictionary) -> void:
	for npc: Dictionary in local:
		var entry: Dictionary = entries[npc["id"]]
		if entry["status"] != "chase":
			continue
		if npc["role"] == "pirate" and not Conditions.can_pirate_target(npc, entry, str(entry["target"]), entries, false):
			_release(npc, entry)
		elif npc["role"] == "patrol" and not Conditions.can_police_target(npc, entry, str(entry["target"]), entries, false):
			Police.release(npc, entry)
	Pairs.cleanup(local, entries)
