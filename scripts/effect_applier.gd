extends Node

signal location_changed(location_id: String)
signal orders_changed
signal galaxy_changed
signal flight_changed
signal combat_changed
signal domestic_changed
signal relationships_changed
signal scenes_changed
signal traffic_changed
signal ship_changed
signal space_effect(kind: String, position: Vector2, npc_id: String)

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Orders = preload("res://scripts/order_rules.gd")
const Galaxy = preload("res://scripts/galaxy_state.gd")
const Graph = preload("res://scripts/galaxy_graph.gd")
const Flight = preload("res://scripts/flight_state.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Spawn = preload("res://scripts/flight_spawn.gd")
const NpcMotion = preload("res://scripts/npc_motion.gd")
const TrafficSimulation = preload("res://scripts/traffic_simulation.gd")
const SpaceGeometry = preload("res://scripts/space_geometry.gd")
const Navigation = preload("res://scripts/galaxy_navigation.gd")
const CombatMath = preload("res://scripts/combat_math.gd")
const CombatState = preload("res://scripts/combat_state.gd")
const CombatMovement = preload("res://scripts/combat_movement.gd")
const CombatRoutes = preload("res://scripts/combat_routes.gd")
const CombatAI = preload("res://scripts/combat_ai.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Cooking = preload("res://scripts/cooking_math.gd")
const Meals = preload("res://scripts/meal_schedule.gd")
const Scenes = preload("res://scripts/scene_queue.gd")
const ShipLoadout = preload("res://scripts/ship_loadout.gd")
const TOW_FEE: int = 400
const TOW_DAYS: int = 1
const STAT_MIN: float = 0.0
const STAT_MAX: float = 100.0
const HIGH_MOOD: float = 70.0
const LOW_MOOD: float = 30.0
const FAVORABLE_MULTIPLIER: float = 1.25
const UNFAVORABLE_MULTIPLIER: float = 0.75
const AROUSAL_DECAY: float = 25.0
const ACTION_TAG_STRENGTH: float = 1.0
const EFFECT_FIELDS: Dictionary = {
	"stat": ["stat", "add"], "flag": ["flag", "set"],
	"money": ["money"], "fuel": ["fuel"], "advance_time": ["advance_time"],
	"rep": ["rep", "add"], "unlock_route": ["unlock_route"], "start_combat": ["start_combat"],
	"item": ["item", "add"], "buff": ["buff", "days"], "learn_recipes": ["learn_recipes"], "unlock_scene": ["unlock_scene"],
	"contact_block": ["contact_block", "set"]
}


func _ready() -> void:
	Clock.time_changed.connect(_on_time_changed)


static func validate(effects: Array) -> Array[String]:
	var errors: Array[String] = []
	for effect: Variant in effects:
		if not effect is Dictionary:
			errors.append("Effect must be an object")
			continue
		var kind: String = _effect_kind(effect)
		if kind.is_empty():
			errors.append("Unsupported or ambiguous effect: %s" % JSON.stringify(effect))
			continue
		var expected: Array = EFFECT_FIELDS[kind]
		if effect.size() != expected.size() or not effect.has_all(expected):
			errors.append("Invalid fields for '%s' effect" % kind)
			continue
		match kind:
			"contact_block":
				if not effect["contact_block"] is String or str(effect["contact_block"]).is_empty() or not effect["set"] is bool:
					errors.append("Invalid contact_block effect")
			"item":
				if not effect["item"] is String or str(effect["item"]).is_empty() or not Orders.whole_number(effect["add"]):
					errors.append("Item effect requires an id and an integer delta")
			"buff":
				if effect["buff"] != "steady_hands" or not Orders.whole_number(effect["days"]) or float(effect["days"]) < 1:
					errors.append("Unsupported buff or invalid duration")
			"learn_recipes":
				if not effect["learn_recipes"] is Array or effect["learn_recipes"].is_empty():
					errors.append("learn_recipes requires recipe ids")
				else:
					for recipe_id: Variant in effect["learn_recipes"]:
						if not recipe_id is String or recipe_id.is_empty():
							errors.append("learn_recipes requires nonempty ids")
			"stat":
				if not Conditions.valid_stat_path(effect["stat"]) or not Conditions.is_number(effect["add"]):
					errors.append("Invalid stat effect")
				elif str(effect["stat"]).ends_with(".suspicion") and not Orders.whole_number(effect["add"]):
					errors.append("Suspicion deltas must be integers")
			"flag":
				if not effect["flag"] is String or str(effect["flag"]).is_empty() or not effect["set"] is bool:
					errors.append("Invalid flag effect")
			"rep":
				if effect["rep"] not in Orders.REPUTATIONS or not Orders.whole_number(effect["add"]):
					errors.append("Invalid reputation effect")
			"unlock_route", "start_combat", "unlock_scene":
				if not effect[kind] is String or str(effect[kind]).is_empty():
					errors.append(kind + " requires an id")
			"fuel":
				if not Conditions.is_number(effect["fuel"]):
					errors.append("Fuel effect requires a finite number")
			_:
				var amount: Variant = effect[kind]
				if not Conditions.is_number(amount) or floor(float(amount)) != float(amount):
					errors.append("'%s' effect requires an integer" % kind)
				elif kind == "advance_time" and amount < 0:
					errors.append("Time cannot advance by a negative amount")
	return errors


func apply_effects(effects: Array) -> Error:
	if not validate(effects).is_empty() or not _targets_exist(effects):
		return ERR_INVALID_DATA
	if not Conditions.can_apply_inventory_effects(effects):
		return ERR_UNAVAILABLE
	var combat_starts: int = 0
	for effect: Dictionary in effects:
		if effect.has("start_combat"):
			combat_starts += 1
			if not Conditions.can_start_combat(str(effect["start_combat"])):
				return ERR_UNAVAILABLE
	if combat_starts > 1:
		return ERR_INVALID_DATA
	var route_unlocked: bool = false
	var relationships_touched: bool = false
	for effect: Dictionary in effects:
		match _effect_kind(effect):
			"contact_block":
				GameState.state["heroines"][effect["contact_block"]]["contact_block"] = effect["set"]
				relationships_touched = true
			"item":
				var item_id: String = str(effect["item"])
				Inventory.change(Inventory.entries(item_id), item_id, int(effect["add"]), 1 if int(effect["add"]) > 0 and DataLoader.get_record(item_id).get("type") == "dish" else 0)
			"buff": GameState.state["buffs"][effect["buff"]] = maxi(int(GameState.state["buffs"].get(effect["buff"], 0)), Clock.current_day() + int(effect["days"]))
			"learn_recipes":
				for recipe_id: String in effect["learn_recipes"]:
					if recipe_id not in GameState.state["known_recipes"]:
						GameState.state["known_recipes"].append(recipe_id)
			"unlock_scene": GameState.state["flags"][str(effect["unlock_scene"]) + "_unlocked"] = true
			"stat":
				_apply_stat(str(effect["stat"]), float(effect["add"]))
				relationships_touched = true
			"flag": GameState.state["flags"][effect["flag"]] = effect["set"]
			"money": GameState.state["money"] = int(GameState.state["money"]) + int(effect["money"])
			"fuel":
				var fuel: Dictionary = GameState.state["ship"]["fuel"]
				fuel["current"] = snappedf(clampf(float(fuel["current"]) + float(effect["fuel"]), 0.0, float(fuel["max"])), 1.0 / 1073741824.0)
			"advance_time": Clock.advance_slots(int(effect["advance_time"]))
			"rep":
				var reputation_id: String = str(effect["rep"])
				GameState.state["reputation"][reputation_id] = clampi(int(GameState.state["reputation"][reputation_id]) + int(effect["add"]), Orders.MIN_REPUTATION, Orders.MAX_REPUTATION)
			"unlock_route":
				_unlock_route(str(effect["unlock_route"]))
				route_unlocked = true
			"start_combat": _begin_combat(str(effect["start_combat"]))
	if route_unlocked:
		galaxy_changed.emit()
	var disclosed: bool = _resolve_disclosures()
	if relationships_touched or disclosed:
		relationships_changed.emit()
	return OK


func _resolve_disclosures() -> bool:
	var changed: bool = false
	var queued: bool = false
	for heroine_id: String in GameState.state.get("heroines", {}):
		if not Conditions.should_disclose(heroine_id):
			continue
		var heroine: Dictionary = GameState.state["heroines"][heroine_id]
		heroine["attitude"] = clampf(float(heroine["attitude"]) - 40.0, STAT_MIN, STAT_MAX)
		heroine["contact_block"] = true
		changed = true
		var scene_id: String = Scenes.find_for(heroine_id, "disclosure")
		if not scene_id.is_empty() and scene_id not in GameState.state["pending_scenes"]:
			GameState.state["pending_scenes"].append(scene_id)
			queued = true
	if queued:
		scenes_changed.emit()
	return changed


func complete_scene(scene_id: String) -> void:
	if scene_id in GameState.state.get("pending_scenes", []):
		GameState.state["pending_scenes"].erase(scene_id)
		scenes_changed.emit()


func accept_order(order_id: String) -> Error:
	if not Conditions.can_accept_order(order_id):
		return ERR_UNAVAILABLE
	GameState.state["orders"][order_id] = {"status": "active", "accepted_day": Clock.current_day()}
	_reveal_system(str(DataLoader.get_record(order_id)["to"]))
	orders_changed.emit()
	galaxy_changed.emit()
	return OK


func jump_route(route_id: String, boost: bool = false) -> Error:
	if not Conditions.can_jump(route_id, boost):
		return ERR_UNAVAILABLE
	var route: Dictionary = DataLoader.get_record(route_id)
	var cost: int = Graph.fuel_cost(float(route["fuel"]["true"]), OrderManager.active_mass(), boost)
	apply_effects([{"fuel": -cost}])
	_unlock_route(route_id)
	_visit_system(str(route["to"]), Spawn.arrival(str(route["from"]), str(route["to"])))
	apply_effects([{"advance_time": int(route["days"]) * Clock.TIME_SLOTS.size()}])
	for event_id: String in DataLoader.get_record(str(route["to"])).get("event_pool", []):
		if DataLoader.get_record(event_id).get("trigger") == "enter_system" and start_flight_event(event_id) == OK:
			break
	galaxy_changed.emit()
	location_changed.emit(str(GameState.state["location"]))
	return OK


func launch_flight() -> Error:
	if not Conditions.can_launch():
		return ERR_UNAVAILABLE
	GameState.state["flags"].erase(GameState.SHIP_INTERIOR_FLAG)
	GameState.state["location"] = "ship_bridge"
	GameState.state["flight"] = Flight.reset_player(GameState.state["flight"], Spawn.hub_departure())
	location_changed.emit("ship_bridge")
	flight_changed.emit()
	return OK


func install_module(module_id: String, target_slot: String = "") -> Error:
	if not Conditions.can_install_module(module_id, target_slot):
		return ERR_UNAVAILABLE
	var ship: Dictionary = GameState.state["ship"]
	var module: Dictionary = DataLoader.get_record(module_id)
	var slot: String = ShipLoadout.slot_for(module)
	var previous: Dictionary = ShipLoadout.installed(ship, slot)
	if slot == "armor":
		ship["hull"] = ShipLoadout.replacement_hull(ship, module)
	if not previous.is_empty():
		ship["modules"][ship["modules"].find(previous["id"])] = module_id
	else:
		ship["modules"].append(module_id)
	ship_changed.emit()
	return OK


func visit_ship() -> Error:
	if not Conditions.can_visit_ship():
		return ERR_UNAVAILABLE
	GameState.state["flags"][GameState.SHIP_INTERIOR_FLAG] = true
	location_changed.emit(str(GameState.state["location"]))
	return OK


func leave_ship() -> Error:
	if not Conditions.can_leave_ship():
		return ERR_UNAVAILABLE
	GameState.state["flags"].erase(GameState.SHIP_INTERIOR_FLAG)
	location_changed.emit(str(GameState.state["location"]))
	return OK


func dock_at_hub() -> Error:
	if not Conditions.can_dock():
		return ERR_UNAVAILABLE
	GameState.state["location"] = "hub_office"
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	GameState.state["flight"]["paused"] = false
	location_changed.emit("hub_office")
	flight_changed.emit()
	return OK


func set_flight_target(position: Vector2) -> Error:
	if not Conditions.can_move_flight() or not is_finite(position.x) or not is_finite(position.y):
		return ERR_UNAVAILABLE
	GameState.state["flight"]["target"] = Motion.coordinates(Motion.bounded(position))
	GameState.state["flight"]["autopilot"] = {}
	flight_changed.emit()
	return OK


func advance_flight(delta: float, boost: bool = false) -> void:
	if not Conditions.can_tick_flight() or not is_finite(delta) or delta <= 0.0:
		return
	var remaining: float = minf(delta, 300.0)
	while remaining > 0.000001 and Conditions.can_tick_flight():
		var step: float = minf(remaining, 0.1)
		_tick_flight(step, boost)
		remaining -= step
	flight_changed.emit()


func _tick_flight(delta: float, boost: bool) -> void:
	_advance_autopilot()
	if not Conditions.can_tick_flight():
		return
	var flight: Dictionary = GameState.state["flight"]
	var previous: Dictionary = flight.duplicate(true)
	var origin: Vector2 = Motion.point(flight["pos"])
	var speed: float = ShipLoadout.speed(GameState.state["ship"]) * (Motion.BOOST_SPEED_MULTIPLIER if boost else 1.0)
	var fuel_per_distance: float = Motion.LOCAL_FUEL_PER_DISTANCE * (Motion.BOOST_FUEL_MULTIPLIER if boost else 1.0)
	if Conditions.can_move_flight():
		var next: Vector2 = Motion.advance(origin, Motion.point(flight["target"]), speed, delta)
		var available: float = float(GameState.state["ship"]["fuel"]["current"])
		var requested: float = origin.distance_to(next)
		var budget: float = available / fuel_per_distance
		var distance: float = minf(requested, budget)
		if distance > 0.0:
			next = origin.move_toward(next, distance)
			flight["pos"] = Motion.coordinates(next)
			var cost: float = available if budget <= requested else distance * fuel_per_distance
			apply_effects([{"fuel": -cost}])
	_apply_star_damage(origin, Motion.point(flight["pos"]), delta, speed)
	if not Conditions.can_fly():
		return
	var simulation: Dictionary = TrafficSimulation.step(delta)
	flight["npcs"] = simulation["npcs"]
	for event: Dictionary in simulation["events"]:
		if event["kind"] == "pursuit" and flight["npcs"][event["npc"]]["target"] == "player" and not flight["autopilot"].is_empty():
			stop_autopilot()
		space_effect.emit(str(event["kind"]), Motion.point(event["pos"]), str(event["npc"]))
	if not simulation["events"].is_empty():
		traffic_changed.emit()
	_check_proximity_events(previous)
	if float(GameState.state["ship"]["fuel"]["current"]) <= 0.0:
		flight["autopilot"] = {}


func toggle_flight_pause() -> Error:
	if not Conditions.can_pause_flight():
		return ERR_UNAVAILABLE
	GameState.state["flight"]["paused"] = not GameState.state["flight"]["paused"]
	flight_changed.emit()
	return OK


func pause_at_npc(npc_id: String) -> Error:
	if not Conditions.can_interact_npc(npc_id):
		return ERR_UNAVAILABLE
	var flight: Dictionary = GameState.state["flight"]
	flight["paused"] = true
	flight_changed.emit()
	return OK


func start_flight_event(event_id: String) -> Error:
	if not Conditions.can_start_flight_event(event_id):
		return ERR_UNAVAILABLE
	var chance: float = float(DataLoader.get_record(event_id)["chance"])
	if chance <= 0.0 or (chance < 1.0 and randf() >= chance):
		return ERR_UNAVAILABLE
	GameState.state["flight"]["encounter"] = event_id
	GameState.state["flight"]["autopilot"] = {}
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	flight_changed.emit()
	return OK


func approach_npc(npc_id: String) -> Error:
	if not Conditions.can_approach_npc(npc_id):
		return ERR_UNAVAILABLE
	return set_flight_target(Motion.point(GameState.state["flight"]["npcs"][npc_id]["pos"]))


func choose_flight_event(event_id: String, option_index: int) -> Error:
	if not Conditions.can_choose_flight_event(event_id, option_index):
		return ERR_UNAVAILABLE
	var option: Dictionary = DataLoader.get_record(event_id)["options"][option_index]
	var effects: Array = option["effects"].duplicate(true)
	effects.append_array(action_tag_effects(option["tags"]))
	if not validate(effects).is_empty() or not _targets_exist(effects):
		return ERR_INVALID_DATA
	var source_npc: String = Conditions.encounter_npc(event_id)
	var result: Error = apply_effects(effects)
	if result == OK:
		GameState.state["flight"]["encounter"] = ""
		if not source_npc.is_empty() and not Conditions.has_combat():
			var entry: Dictionary = GameState.state["flight"]["npcs"][source_npc]
			entry["status"] = "cruise"
			entry["target"] = ""
			entry["timer"] = 35.0
			entry["cooldown"] = float(DataLoader.get_record(source_npc).get("piracy", {}).get("cooldown", 15.0))
	flight_changed.emit()
	galaxy_changed.emit()
	return result


func _check_proximity_events(previous: Dictionary) -> void:
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if Conditions.can_intercept_player(str(npc["id"])) and start_flight_event(str(npc["event"])) == OK:
			return
	var system: Dictionary = DataLoader.get_record(str(GameState.state["current_system"]))
	for object: Dictionary in system.get("objects", []):
		if object.get("type") == "event_marker" and Conditions.is_near(object["pos"]):
			if Motion.point(previous["pos"]).distance_to(Motion.point(object["pos"])) > Motion.INTERACTION_RADIUS:
				if start_flight_event(str(object["event"])) == OK:
					return


func refuel_ship() -> Error:
	if not Conditions.can_refuel():
		return ERR_UNAVAILABLE
	var system: Dictionary = DataLoader.get_record(str(GameState.state["current_system"]))
	var fuel: Dictionary = GameState.state["ship"]["fuel"]
	var missing: float = float(fuel["max"]) - float(fuel["current"])
	var result: Error = apply_effects([{"money": -ceili(missing * int(system["refuel"]["price_per_unit"]))}, {"fuel": missing}])
	galaxy_changed.emit()
	return result


func buy_planet_fuel(planet_id: String, amount: float) -> Error:
	if not Conditions.can_buy_planet_fuel(planet_id, amount):
		return ERR_UNAVAILABLE
	var price: int = int(DataLoader.get_record(str(GameState.state["current_system"]))["refuel"]["price_per_unit"])
	var result: Error = apply_effects([{"money": -ceili(amount * price)}, {"fuel": amount}])
	flight_changed.emit()
	return result


func choose_planet_dialogue(planet_id: String, option_index: int) -> Error:
	if not Conditions.can_choose_planet_dialogue(planet_id, option_index):
		return ERR_UNAVAILABLE
	var event: Dictionary = DataLoader.get_record(str(Conditions.space_object(planet_id)["dialogue"]))
	var option: Dictionary = event["options"][option_index]
	var effects: Array = option["effects"].duplicate(true)
	effects.append_array(action_tag_effects(option["tags"]))
	return apply_effects(effects)


func stop_autopilot() -> void:
	GameState.state["flight"]["autopilot"] = {}
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	flight_changed.emit()


func start_autopilot(destination: String) -> Error:
	var path: Array[String] = Navigation.plan(destination)
	if not Conditions.can_autopilot_to(destination, path):
		return ERR_UNAVAILABLE
	GameState.state["flight"]["autopilot"] = {"destination": destination, "routes": path}
	_advance_autopilot()
	flight_changed.emit()
	return OK


func _advance_autopilot() -> void:
	var flight: Dictionary = GameState.state["flight"]
	var plan: Dictionary = flight["autopilot"]
	if plan.is_empty():
		return
	if Conditions.star_is_dangerous(Motion.point(flight["pos"])):
		stop_autopilot()
		return
	var route_id: String = str(plan["routes"][0])
	if not Conditions.can_traverse_route(route_id):
		stop_autopilot()
		return
	if Conditions.can_jump(route_id):
		var remaining: Array = plan["routes"].duplicate()
		remaining.pop_front()
		var destination: String = str(plan["destination"])
		if jump_route(route_id) == OK and not remaining.is_empty() and GameState.state["flight"]["encounter"].is_empty():
			GameState.state["flight"]["autopilot"] = {"destination": destination, "routes": remaining}
		return
	var gate: Dictionary = Conditions.space_object(route_id)
	if gate.is_empty():
		stop_autopilot()
		return
	flight["target"] = Motion.coordinates(SpaceGeometry.safe_target(Motion.point(flight["pos"]), Motion.point(gate["pos"]), str(GameState.state["current_system"])))


func _apply_star_damage(origin: Vector2, target: Vector2, delta: float, speed: float) -> void:
	var star: Dictionary = SpaceGeometry.star(str(GameState.state["current_system"]))
	if star.is_empty():
		return
	var moving_time: float = minf(delta, origin.distance_to(target) / speed)
	var exposure: float = SpaceGeometry.segment_exposure(origin, target, Motion.point(star["pos"]), float(star["hazard"]["radius"])) * moving_time
	if Conditions.star_is_dangerous(target):
		exposure += delta - moving_time
	if exposure <= 0.0:
		return
	GameState.state["flight"]["autopilot"] = {}
	var hull: Dictionary = GameState.state["ship"]["hull"]
	hull["current"] = float(Vector2(maxf(0.0, float(hull["current"]) - exposure * float(star["hazard"]["damage_per_second"])), 0).x)
	space_effect.emit("star_damage", target, "player")
	if float(hull["current"]) <= 0.0:
		_visit_system(Galaxy.INITIAL_SYSTEM)
		GameState.state["location"] = "hub_office"
		hull["current"] = float(hull["max"])
		apply_effects([{"money": -TOW_FEE}, {"fuel": int(GameState.state["ship"]["fuel"]["max"])}, {"advance_time": TOW_DAYS * Clock.TIME_SLOTS.size()}])
		galaxy_changed.emit()
		location_changed.emit("hub_office")


func sell_route(route_id: String) -> Error:
	if not Conditions.can_sell_route(route_id):
		return ERR_UNAVAILABLE
	GameState.state["public_routes"].append(route_id)
	var result: Error = apply_effects([{"money": int(DataLoader.get_record(route_id)["map_value"])}])
	galaxy_changed.emit()
	return result


func request_tow() -> Error:
	if not Conditions.can_request_tow():
		return ERR_UNAVAILABLE
	_visit_system(Galaxy.INITIAL_SYSTEM)
	var result: Error = apply_effects([{"money": -TOW_FEE}, {"fuel": int(GameState.state["ship"]["fuel"]["max"])}, {"advance_time": TOW_DAYS * Clock.TIME_SLOTS.size()}])
	galaxy_changed.emit()
	location_changed.emit(str(GameState.state["location"]))
	return result


func _reveal_system(system_id: String) -> void:
	if GameState.state["systems"].get(system_id) == "hidden":
		GameState.state["systems"][system_id] = "seen"


func _unlock_route(route_id: String) -> void:
	if route_id not in GameState.state["known_routes"]:
		GameState.state["known_routes"].append(route_id)
	var route: Dictionary = DataLoader.get_record(route_id)
	_reveal_system(str(route["from"]))
	_reveal_system(str(route["to"]))


func _visit_system(system_id: String, position: Vector2 = Motion.SPAWN) -> void:
	GameState.state["current_system"] = system_id
	GameState.state["systems"][system_id] = "visited"
	GameState.state["location"] = "ship_bridge"
	GameState.state["flight"] = Flight.reset_player(GameState.state["flight"], position)


func settle_order(order_id: String, status: String, require_terminal: bool = true) -> Error:
	if not Conditions.can_settle_order(order_id, status, require_terminal):
		return ERR_UNAVAILABLE
	var order: Dictionary = DataLoader.get_record(order_id)
	var effects: Array = order.get("reward" if status == "completed" else "failure", []).duplicate(true)
	if status == "completed":
		effects.append_array(action_tag_effects(order.get("action_tags", [])))
	if not validate(effects).is_empty() or not _targets_exist(effects):
		return ERR_INVALID_DATA
	GameState.state["orders"][order_id]["status"] = status
	var result: Error = apply_effects(effects)
	if result != OK:
		GameState.state["orders"][order_id]["status"] = "active"
		return result
	orders_changed.emit()
	return OK


func deliver_order(order_id: String) -> Error:
	if not Conditions.can_deliver_order(order_id):
		return ERR_UNAVAILABLE
	var result: Error = settle_order(order_id, "completed", false)
	if result == OK:
		flight_changed.emit()
	return result


func action_tag_effects(tags: Array) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	for heroine: Dictionary in DataLoader.get_records("heroines"):
		var heroine_id: String = str(heroine["id"])
		if not Conditions.evaluate([{"aboard": heroine_id, "is": true}]) and not Conditions.is_present(heroine_id):
			continue
		var weights: Dictionary = heroine.get("tag_weights", {})
		for tag: String in tags:
			if weights.has(tag):
				effects.append({"stat": heroine_id + ".attitude", "add": float(weights[tag]) * ACTION_TAG_STRENGTH})
	return effects


func scene_end_effects(scene: Dictionary) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	var participants: Dictionary = {}
	var crew: Dictionary = GameState.state.get("heroines", {})
	for line: Dictionary in scene.get("lines", []):
		var speaker: String = str(line.get("who", ""))
		if crew.has(speaker):
			participants[speaker] = true
	for heroine_id: String in participants:
		effects.append({"stat": heroine_id + ".arousal", "add": -STAT_MAX})
	return effects


func move_player(location_id: String) -> Error:
	if not Conditions.can_enter(location_id):
		return ERR_UNAVAILABLE
	if GameState.state["location"] != location_id:
		GameState.state["location"] = location_id
		location_changed.emit(location_id)
	return OK


func apply_schedule(placements: Dictionary) -> Error:
	var crew: Dictionary = GameState.state.get("heroines", {})
	if placements.size() != crew.size():
		return ERR_INVALID_DATA
	for heroine_id: String in placements:
		if not crew.has(heroine_id) or not placements[heroine_id] is String:
			return ERR_INVALID_DATA
		if not DataLoader.record_sources.has("locations/" + str(placements[heroine_id])):
			return ERR_INVALID_DATA
	for heroine_id: String in placements:
		crew[heroine_id]["loc"] = placements[heroine_id]
	return OK


static func _effect_kind(effect: Dictionary) -> String:
	var kind: String = ""
	for candidate: String in EFFECT_FIELDS:
		if effect.has(candidate):
			if not kind.is_empty():
				return ""
			kind = candidate
	return kind


func _targets_exist(effects: Array) -> bool:
	var crew: Dictionary = GameState.state.get("heroines", {})
	for effect: Dictionary in effects:
		match _effect_kind(effect):
			"contact_block":
				if not crew.has(effect["contact_block"]) or not crew[effect["contact_block"]].get("contact_block") is bool:
					return false
			"item":
				if not DataLoader.record_sources.has("items/" + str(effect["item"])):
					return false
			"learn_recipes":
				for recipe_id: String in effect["learn_recipes"]:
					if not DataLoader.record_sources.has("recipes/" + recipe_id):
						return false
			"unlock_scene":
				if not DataLoader.record_sources.has("scenes/" + str(effect["unlock_scene"])):
					return false
			"stat":
				var path: PackedStringArray = str(effect["stat"]).split(".")
				if not crew.has(path[0]) or not crew[path[0]] is Dictionary:
					return false
				for stat_name: String in Conditions.STAT_NAMES:
					if not Conditions.is_number(crew[path[0]].get(stat_name)):
						return false
				if path[1] == "arousal":
					var blueprint: Dictionary = DataLoader.get_record(path[0])
					var thresholds: Variant = blueprint.get("thresholds")
					if not thresholds is Dictionary or not Conditions.is_number(thresholds.get("touch")):
						return false
				elif path[1] == "suspicion" and not Orders.whole_number(crew[path[0]].get("suspicion")):
					return false
			"flag":
				if not GameState.state.get("flags") is Dictionary:
					return false
			"money":
				if not Conditions.is_number(GameState.state.get("money")):
					return false
			"rep":
				if not GameState.state.get("reputation") is Dictionary or not Orders.whole_number(GameState.state["reputation"].get(effect["rep"])):
					return false
			"fuel":
				var fuel: Variant = GameState.state.get("ship", {}).get("fuel")
				if not fuel is Dictionary or not Conditions.is_number(fuel.get("current")) or not Conditions.is_number(fuel.get("max")):
					return false
			"unlock_route":
				if not DataLoader.record_sources.has("routes/" + str(effect["unlock_route"])):
					return false
			"start_combat":
				if not DataLoader.record_sources.has("enemies/" + str(effect["start_combat"])):
					return false
	return true


func _begin_combat(enemy_id: String) -> void:
	var event_id: String = str(GameState.state["flight"]["encounter"])
	var source_npc: String = Conditions.encounter_npc(event_id)
	GameState.state["combat"] = CombatState.initial(enemy_id, source_npc)
	GameState.state["flight"]["encounter"] = ""
	combat_changed.emit()


func move_combat(target: Vector2i) -> Error:
	var route: Array[Vector2i] = Conditions.combat_move_path(target)
	if route.is_empty():
		return ERR_UNAVAILABLE
	var combat: Dictionary = GameState.state["combat"]
	var vessel: Dictionary = combat["player"]
	var turn: Dictionary = combat["movement"]["player"]
	var origin: Vector2i = CombatMath.cell(vessel["pos"])
	turn["history"].append({"pos": vessel["pos"].duplicate(), "move_points": int(combat["move_points"]), "facing": int(vessel["facing"])})
	combat["move_points"] = int(combat["move_points"]) - CombatMovement.cost(origin, target)
	vessel["facing"] = CombatRoutes.arrival_facing(route)
	vessel["pos"] = CombatMath.coordinates(target)
	combat_changed.emit()
	return OK


func undo_combat_move() -> Error:
	if not Conditions.can_undo_combat_move():
		return ERR_UNAVAILABLE
	var combat: Dictionary = GameState.state["combat"]
	var turn: Dictionary = combat["movement"]["player"]
	var previous: Dictionary = turn["history"].pop_back()
	combat["move_points"] = int(combat["move_points"]) + CombatMovement.cost(CombatMath.cell(combat["player"]["pos"]), CombatMath.cell(previous["pos"]))
	combat["player"]["pos"] = previous["pos"].duplicate()
	combat["player"]["facing"] = int(previous["facing"])
	combat_changed.emit()
	return OK


func shoot_combat(weapon_id: String, target: Vector2i) -> Error:
	if not Conditions.can_shoot_combat(weapon_id, target):
		return ERR_UNAVAILABLE
	var combat: Dictionary = GameState.state["combat"]
	var weapon: Dictionary = DataLoader.get_record(weapon_id)
	combat["ap"] = int(combat["ap"]) - int(weapon["ap_cost"])
	combat["shots"] = []
	_fire_combat(weapon, true, target)
	if combat["opponent"]["hull"] <= 0:
		combat["result"] = "victory"
		var loot: Dictionary = DataLoader.get_record(str(combat["enemy"]))["loot"]
		combat["loot"] = {"money": randi_range(int(loot["money"][0]), int(loot["money"][1])), "fuel": randi_range(int(loot["fuel"][0]), int(loot["fuel"][1]))}
	combat_changed.emit()
	return OK


func shield_combat() -> Error:
	return use_combat_ability("shield_reboot")


func use_combat_ability(ability_id: String) -> Error:
	if not Conditions.can_use_combat_ability(ability_id):
		return ERR_UNAVAILABLE
	var ability: Dictionary = DataLoader.get_record(ability_id)
	var combat: Dictionary = GameState.state["combat"]
	var effect: Dictionary = ability["effect"]
	var scale: float = CombatMath.mood_multiplier(ability)
	combat["ap"] = int(combat["ap"]) - CombatMath.ability_ap_cost(ability)
	combat["cooldowns"][ability_id] = int(ability["cooldown"])
	if effect.has("self_evasion"):
		combat["evasion"] = {"value": float(Vector2(clampf(float(effect["self_evasion"]) * scale, 0.0, 1.0), 0).x), "rounds": int(effect["duration"])}
	if effect.has("move_points"):
		combat["move_points"] = int(combat["move_points"]) + ceili(float(effect["move_points"]) * scale)
		apply_effects([{"fuel": -float(effect["fuel"])}])
	if effect.has("shield_restore"):
		combat["shield_recharge"] = {"amount": float(effect["shield_restore"]), "round": int(combat["round"]) + int(effect["delay"])}
	combat_changed.emit()
	return OK


func end_combat_turn() -> Error:
	if not Conditions.can_act_combat():
		return ERR_UNAVAILABLE
	var combat: Dictionary = GameState.state["combat"]
	var enemy: Dictionary = DataLoader.get_record(str(combat["enemy"]))
	var opponent: Dictionary = combat["opponent"]
	var weapons: Array[Dictionary] = CombatMath.enemy_weapons()
	var movement: int = int(enemy["speed"])
	var turn: Dictionary = CombatState.new_turn(opponent)
	combat["movement"]["opponent"] = turn
	combat["fired"]["opponent"] = []
	combat["shots"] = []
	var path: Array[Vector2i] = CombatAI.plan(opponent, turn, movement, enemy["movement"], combat["player"], weapons)
	for next: Vector2i in path:
		var origin: Vector2i = CombatMath.cell(opponent["pos"])
		var route: Array[Vector2i] = Conditions.vessel_move_path(opponent, next, turn, movement, enemy["movement"], CombatMath.cell(combat["player"]["pos"]))
		if route.is_empty():
			break
		turn["history"].append({"pos": opponent["pos"].duplicate(), "move_points": movement, "facing": int(opponent["facing"])})
		movement -= CombatMovement.cost(origin, next)
		opponent["facing"] = CombatRoutes.arrival_facing(route)
		opponent["pos"] = CombatMath.coordinates(next)
	var enemy_ap: int = CombatMath.ACTION_POINTS
	for weapon: Dictionary in CombatAI.firing_order(opponent, combat["player"], weapons, enemy_ap):
		if float(GameState.state["ship"]["hull"]["current"]) <= 0:
			break
		if not Conditions.can_fire_weapon(opponent, combat["player"], weapon, enemy_ap, combat["fired"]["opponent"]):
			continue
		_fire_combat(weapon, false, CombatMath.cell(combat["player"]["pos"]))
		enemy_ap -= int(weapon["ap_cost"])
	if float(GameState.state["ship"]["hull"]["current"]) <= 0:
		combat["result"] = "defeat"
		combat["shield_recharge"] = {}
	else:
		combat["round"] = int(combat["round"]) + 1
		if not combat["shield_recharge"].is_empty() and int(combat["shield_recharge"]["round"]) <= int(combat["round"]):
			combat["player"]["shield"] = minf(CombatMath.player_shield_max(), float(combat["player"]["shield"]) + float(combat["shield_recharge"]["amount"]))
			combat["shield_recharge"] = {}
		combat["ap"] = CombatMath.ACTION_POINTS
		combat["fired"]["player"] = []
		combat["move_points"] = CombatMath.movement_budget()
		combat["movement"]["player"] = CombatState.new_turn(combat["player"])
		for ability_id: String in combat["cooldowns"]:
			combat["cooldowns"][ability_id] = maxi(0, int(combat["cooldowns"][ability_id]) - 1)
		combat["evasion"]["rounds"] = maxi(0, int(combat["evasion"]["rounds"]) - 1)
		if combat["evasion"]["rounds"] == 0:
			combat["evasion"]["value"] = 0.0
	combat_changed.emit()
	return OK


func _fire_combat(weapon: Dictionary, player_fires: bool, target_cell: Vector2i) -> void:
	var combat: Dictionary = GameState.state["combat"]
	var attacker: Dictionary = combat["player"] if player_fires else combat["opponent"]
	var target: Dictionary = combat["opponent"] if player_fires else combat["player"]
	var shot: Dictionary = {"shooter": "player" if player_fires else "opponent", "weapon": str(weapon["id"]), "target": CombatMath.coordinates(target_cell), "result": "miss", "damage": 0.0}
	combat["last_shot"] = shot
	combat["fired"][shot["shooter"]].append(str(weapon["id"]))
	var visual: Dictionary = shot.duplicate(true)
	visual["origin"] = attacker["pos"].duplicate()
	combat["shots"].append(visual)
	var chance: float = CombatMath.shot_chance(attacker, target_cell, weapon, player_fires)
	if randf() >= chance or target_cell != CombatMath.cell(target["pos"]):
		return
	var amount: float = float(randi_range(int(weapon["dmg"][0]), int(weapon["dmg"][1])))
	shot["result"] = "hit"
	if randf() < float(weapon["critical"]["chance"]):
		shot["result"] = "critical"
		amount *= float(weapon["critical"]["multiplier"])
	var hull: float = float(target["hull"]) if player_fires else float(GameState.state["ship"]["hull"]["current"])
	var shield: float = float(target["shield"])
	var damage: Dictionary = CombatMath.damage(hull, shield, amount, str(weapon["type"]))
	shot["damage"] = hull + shield - float(damage["hull"]) - float(damage["shield"])
	visual["result"] = shot["result"]
	visual["damage"] = shot["damage"]
	target["shield"] = damage["shield"]
	if player_fires:
		target["hull"] = damage["hull"]
	else:
		GameState.state["ship"]["hull"]["current"] = damage["hull"]


func finish_combat() -> Error:
	if not Conditions.can_finish_combat():
		return ERR_UNAVAILABLE
	var combat: Dictionary = GameState.state["combat"].duplicate(true)
	GameState.state["combat"] = {}
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	GameState.state["flight"]["paused"] = false
	if combat["result"] == "victory":
		apply_effects([{"money": int(combat["loot"]["money"])}, {"fuel": int(combat["loot"]["fuel"])}])
		if not str(combat["source_npc"]).is_empty():
			GameState.state["flight"]["defeated_npcs"].append(str(combat["source_npc"]))
			TrafficSimulation.cleanup(DataLoader.get_records("npcs"), GameState.state["flight"]["npcs"])
	else:
		GameState.state["ship"]["hull"]["current"] = float(GameState.state["ship"]["hull"]["max"])
		_visit_system(Galaxy.INITIAL_SYSTEM)
		GameState.state["location"] = "hub_office"
		apply_effects([{"money": -TOW_FEE}, {"fuel": int(GameState.state["ship"]["fuel"]["max"])}, {"advance_time": TOW_DAYS * Clock.TIME_SLOTS.size()}])
	combat_changed.emit()
	flight_changed.emit()
	galaxy_changed.emit()
	location_changed.emit(str(GameState.state["location"]))
	return OK


func _apply_stat(stat_path: String, amount: float) -> void:
	var path: PackedStringArray = stat_path.split(".")
	var heroine: Dictionary = GameState.state["heroines"][path[0]]
	if path[1] == "suspicion":
		heroine["suspicion"] = clampi(int(heroine["suspicion"]) + int(amount), 0, 100)
		return
	if path[1] == "attitude":
		var mood: float = float(heroine["mood"])
		if mood >= HIGH_MOOD:
			amount *= FAVORABLE_MULTIPLIER if amount > 0.0 else UNFAVORABLE_MULTIPLIER
		elif mood <= LOW_MOOD:
			amount *= UNFAVORABLE_MULTIPLIER if amount > 0.0 else FAVORABLE_MULTIPLIER
	elif path[1] == "arousal" and amount > 0.0:
		var threshold: float = float(DataLoader.get_record(path[0])["thresholds"]["touch"])
		if float(heroine["attitude"]) < threshold:
			return
	heroine[path[1]] = clampf(float(heroine[path[1]]) + amount, STAT_MIN, STAT_MAX)


func _on_time_changed(_day: int, _time_slot: String) -> void:
	for heroine_id: String in GameState.state.get("meal_invites", {}).keys():
		if Conditions.meal_has_expired(heroine_id):
			GameState.state["meal_invites"].erase(heroine_id)
	for buff_id: String in GameState.state.get("buffs", {}).keys():
		if int(GameState.state["buffs"][buff_id]) <= _day:
			GameState.state["buffs"].erase(buff_id)
	var effects: Array[Dictionary] = []
	for heroine_id: String in GameState.state.get("heroines", {}):
		effects.append({"stat": heroine_id + ".arousal", "add": -AROUSAL_DECAY})
	if apply_effects(effects) != OK:
		push_error("EffectApplier: could not apply time decay")


func buy_item(shop_id: String, item_id: String) -> Error:
	if not Conditions.can_buy_item(shop_id, item_id):
		return ERR_UNAVAILABLE
	for entry: Dictionary in DataLoader.get_record(shop_id)["items"]:
		if entry["item"] == item_id:
			var result: Error = apply_effects([{"money": -int(entry["price"])}, {"item": item_id, "add": 1}])
			domestic_changed.emit()
			return result
	return ERR_INVALID_PARAMETER


func sell_item(shop_id: String, item_id: String) -> Error:
	if not Conditions.can_sell_item(shop_id, item_id):
		return ERR_UNAVAILABLE
	var price: int = floori(float(DataLoader.get_record(item_id)["sell_price"]) * float(DataLoader.get_record(shop_id)["sell_ratio"]))
	var result: Error = apply_effects([{"item": item_id, "add": -1}, {"money": price}])
	domestic_changed.emit()
	return result


func read_book(index: int) -> Error:
	if not Conditions.can_read_book(index):
		return ERR_UNAVAILABLE
	var item_id: String = str(GameState.state["ship"]["cargo"]["items"][index]["item"])
	var result: Error = apply_effects([{"item": item_id, "add": -1}, {"learn_recipes": DataLoader.get_record(item_id)["teaches"]}])
	domestic_changed.emit()
	return result


func prepare_ingredient(recipe_id: String, item_id: String, zone: String, entry_index: int = -1) -> Error:
	if not Conditions.can_prepare_ingredient(recipe_id, item_id, zone, entry_index):
		return ERR_UNAVAILABLE
	if GameState.state["kitchen"].is_empty():
		GameState.state["kitchen"] = {"recipe": recipe_id, "entries": []}
	var entries: Array = GameState.state["kitchen"]["entries"]
	if entry_index < 0:
		entries.append({"item": item_id, "steps": [], "zone": zone})
	else:
		entries[entry_index]["zone"] = zone
	domestic_changed.emit()
	return OK


func process_kitchen_zone(zone: String) -> Error:
	if not Conditions.can_process_kitchen_zone(zone):
		return ERR_UNAVAILABLE
	for entry: Dictionary in GameState.state["kitchen"]["entries"]:
		if Conditions.can_process_kitchen_entry(entry, zone):
			entry["steps"].append(zone)
	domestic_changed.emit()
	return OK


func cancel_cooking() -> void:
	GameState.state["kitchen"] = {}
	domestic_changed.emit()


func finish_cooking() -> Error:
	if not Conditions.can_finish_cooking():
		return ERR_UNAVAILABLE
	var recipe: Dictionary = DataLoader.get_record(str(GameState.state["kitchen"]["recipe"]))
	var quality: int = Cooking.quality(int(GameState.state["cooking_skill"]))
	for ingredient: Dictionary in recipe["ingredients"]:
		Inventory.change(GameState.state["inventory"], str(ingredient["item"]), -int(ingredient["count"]))
	Inventory.change(GameState.state["inventory"], str(recipe["dish"]), 1, quality)
	GameState.state["cooking_skill"] = int(GameState.state["cooking_skill"]) + 1
	GameState.state["kitchen"] = {}
	apply_effects([{"advance_time": int(recipe["slots"])}])
	domestic_changed.emit()
	return OK


func use_food(index: int, heroine_id: String = "") -> Error:
	if not Conditions.can_use_food(index, heroine_id):
		return ERR_UNAVAILABLE
	var entry: Dictionary = GameState.state["inventory"][index].duplicate(true)
	var result: Error = _apply_serving(entry, heroine_id) if not heroine_id.is_empty() else apply_effects(Inventory.recipe_for_dish(str(entry["item"]))["self_effects"])
	if result == OK:
		Inventory.change(GameState.state["inventory"], str(entry["item"]), -1, int(entry["quality"]))
	domestic_changed.emit()
	return result


func _apply_serving(entry: Dictionary, heroine_id: String) -> Error:
	var recipe: Dictionary = Inventory.recipe_for_dish(str(entry["item"]))
	var effects: Array = recipe["serve_effects"].duplicate(true)
	var taste: float = Cooking.taste(recipe["tags"], DataLoader.get_record(heroine_id).get("food", {}))
	for effect: Dictionary in effects:
		if effect.has("stat"):
			effect["stat"] = str(effect["stat"]).replace("{target}", heroine_id)
			effect["add"] = Cooking.gain(float(effect["add"]), int(entry["quality"]), taste)
	var result: Error = apply_effects(effects)
	if result != OK:
		return result
	GameState.state["served_days"][heroine_id] = Clock.current_day()
	for observer_id: String in GameState.state["heroines"]:
		var observer: Dictionary = GameState.state["heroines"][observer_id]
		if observer_id != heroine_id and observer.get("loc") == "hub_kitchen" and Conditions.heroine_visible(observer_id) and observer["polygamy"] == "forbids":
			observer["suspicion"] = clampi(int(observer["suspicion"]) + 5, 0, 100)
	if _resolve_disclosures():
		relationships_changed.emit()
	return OK


func invite_to_meal(index: int, heroine_id: String) -> Error:
	if not Conditions.can_invite_to_meal(index, heroine_id):
		return ERR_UNAVAILABLE
	var entry: Dictionary = GameState.state["inventory"][index].duplicate(true)
	var arrival: Dictionary = Meals.arrival(Clock.current_day(), Clock.current_slot())
	Inventory.change(GameState.state["inventory"], str(entry["item"]), -1, int(entry["quality"]))
	GameState.state["meal_invites"][heroine_id] = {"item": entry["item"], "quality": int(entry["quality"]), "day": arrival["day"], "time_slot": arrival["time_slot"]}
	domestic_changed.emit()
	return OK


func resolve_meal_invites() -> void:
	for heroine_id: String in GameState.state.get("meal_invites", {}):
		if Conditions.can_resolve_meal_invite(heroine_id):
			if _apply_serving(GameState.state["meal_invites"][heroine_id], heroine_id) != OK:
				push_error("EffectApplier: could not serve reserved meal to " + heroine_id)


func accept_shop_quest(order_id: String) -> Error:
	if not Conditions.can_accept_shop_quest(order_id):
		return ERR_UNAVAILABLE
	GameState.state["orders"][order_id] = {"status": "active", "accepted_day": Clock.current_day()}
	domestic_changed.emit()
	return OK


func complete_shop_quest(order_id: String) -> Error:
	if not Conditions.can_complete_shop_quest(order_id):
		return ERR_UNAVAILABLE
	var order: Dictionary = DataLoader.get_record(order_id)
	var effects: Array = []
	for entry: Dictionary in order.get("need_items", []):
		effects.append({"item": entry["item"], "add": -int(entry["count"])})
	effects.append_array(order["reward"].duplicate(true))
	if order.has("labor_slots"):
		effects.append({"advance_time": int(order["labor_slots"])})
	var result: Error = apply_effects(effects)
	if result == OK:
		GameState.state["orders"][order_id]["status"] = "completed"
	domestic_changed.emit()
	return result
