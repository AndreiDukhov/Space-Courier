extends RefCounted

const Slots = preload("res://scripts/time_slots.gd")
const Orders = preload("res://scripts/order_rules.gd")
const Galaxy = preload("res://scripts/galaxy_state.gd")
const Graph = preload("res://scripts/galaxy_graph.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const CombatMath = preload("res://scripts/combat_math.gd")
const CombatRoutes = preload("res://scripts/combat_routes.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Domestic = preload("res://scripts/domestic_state.gd")
const Meals = preload("res://scripts/meal_schedule.gd")
const Scenes = preload("res://scripts/scene_queue.gd")
const ShipLoadout = preload("res://scripts/ship_loadout.gd")
const STAT_NAMES: Array[String] = ["attitude", "mood", "arousal"]
const OPERATORS: Array[String] = ["==", "!=", ">", ">=", "<", "<="]
const CONDITION_FIELDS: Dictionary = {
	"stat": ["stat", "op", "value"],
	"flag": ["flag", "is"],
	"time": ["time"],
	"aboard": ["aboard", "is"],
	"at": ["at"],
	"others_absent": ["others_absent"],
	"rep": ["rep", "op", "value"], "item": ["item", "count"],
	"contact_block": ["contact_block", "is"]
}


static func validate(conditions: Array) -> Array[String]:
	var errors: Array[String] = []
	for condition: Variant in conditions:
		if not condition is Dictionary:
			errors.append("Condition must be an object")
			continue
		var kind: String = condition_kind(condition)
		if kind.is_empty():
			errors.append("Unsupported or ambiguous condition: %s" % JSON.stringify(condition))
			continue
		var expected: Array = CONDITION_FIELDS[kind]
		if condition.size() != expected.size() or not condition.has_all(expected):
			errors.append("Invalid fields for '%s' condition" % kind)
			continue
		match kind:
			"item":
				if not condition["item"] is String or str(condition["item"]).is_empty() or not Orders.whole_number(condition["count"]) or float(condition["count"]) < 1:
					errors.append("Item conditions require an id and a positive count")
			"stat":
				if not valid_stat_path(condition["stat"]) or condition["op"] not in OPERATORS or not is_number(condition["value"]):
					errors.append("Invalid stat comparison")
			"rep":
				if condition["rep"] not in Orders.REPUTATIONS or condition["op"] not in OPERATORS or not is_number(condition["value"]):
					errors.append("Invalid reputation comparison")
			"flag", "aboard", "contact_block":
				if not condition[kind] is String or str(condition[kind]).is_empty() or not condition["is"] is bool:
					errors.append("Invalid '%s' condition" % kind)
			"time":
				if not condition["time"] is Array or condition["time"].is_empty():
					errors.append("Time condition requires a nonempty array")
				else:
					for slot: Variant in condition["time"]:
						if not slot is String or slot not in Slots.NAMES:
							errors.append("Unknown time slot")
			"at":
				if not condition["at"] is String or str(condition["at"]).is_empty():
					errors.append("Location conditions require an id")
			"others_absent":
				if not condition["others_absent"] is Array:
					errors.append("Absent characters must be an array of ids")
				else:
					for heroine_id: Variant in condition["others_absent"]:
						if not heroine_id is String or str(heroine_id).is_empty():
							errors.append("Absent characters require nonempty ids")
	return errors


static func evaluate(conditions: Array) -> bool:
	if not validate(conditions).is_empty():
		return false
	for condition: Dictionary in conditions:
		if not _evaluate_one(condition):
			return false
	return true


static func evaluate_scene(scene: Dictionary) -> bool:
	if scene.is_empty():
		return false
	var heroine_id: String = Scenes.heroine(scene)
	var blocked: bool = bool(GameState.state.get("heroines", {}).get(heroine_id, {}).get("contact_block", false))
	var tags: Array = scene.get("tags", [])
	if "disclosure" in tags:
		if scene.get("id") not in GameState.state.get("pending_scenes", []):
			return false
	elif "reconciliation" in tags:
		for pending_id: String in GameState.state.get("pending_scenes", []):
			var pending: Dictionary = DataLoader.get_record(pending_id)
			if "disclosure" in pending.get("tags", []) and Scenes.heroine(pending) == heroine_id:
				return false
	elif blocked:
		return false
	if scene.has("location") and not evaluate([{"at": scene["location"]}]):
		return false
	return evaluate(scene.get("conditions", []))


static func can_enter(location_id: String) -> bool:
	if has_combat() or not GameState.state.get("kitchen", {}).is_empty():
		return false
	if not DataLoader.record_sources.has("locations/" + location_id):
		return false
	if GameState.state.get("current_system") != Galaxy.INITIAL_SYSTEM and DataLoader.get_record(location_id).get("area") == "hub":
		return false
	var current_id: String = str(GameState.state.get("location", ""))
	if location_id == current_id:
		return true
	var current: Dictionary = DataLoader.get_record(current_id)
	if location_id not in current.get("connects", []):
		return false
	return location_is_open(location_id)


static func location_is_open(location_id: String) -> bool:
	if not DataLoader.record_sources.has("locations/" + location_id):
		return false
	return evaluate(DataLoader.get_record(location_id).get("access", []))


static func is_present(heroine_id: String) -> bool:
	var heroine: Variant = GameState.state.get("heroines", {}).get(heroine_id)
	return heroine is Dictionary and heroine.get("loc") is String and heroine_visible(heroine_id) and evaluate([{"at": heroine["loc"]}])


static func heroine_visible(heroine_id: String) -> bool:
	if meal_is_due(heroine_id):
		return true
	for shop: Dictionary in DataLoader.get_records("shops"):
		if shop.get("owner") == heroine_id:
			return Clock.current_slot() in shop.get("open_slots", [])
	return true


static func can_wait() -> bool:
	if has_combat() or not GameState.state.get("kitchen", {}).is_empty():
		return false
	var location: Dictionary = DataLoader.get_record(str(GameState.state.get("location", "")))
	return "wait" in location.get("actions", [])


static func can_use_order_terminal() -> bool:
	if has_combat():
		return false
	var location: Dictionary = DataLoader.get_record(str(GameState.state.get("location", "")))
	return GameState.state.get("current_system") == Galaxy.INITIAL_SYSTEM and evaluate([{"at": "hub_office"}]) and "orders" in location.get("actions", [])


static func can_use_galaxy_map() -> bool:
	return not has_combat() and (GameState.state.get("location") == "hub_tech" or can_fly()) and GameState.state.get("flight", {}).get("encounter", "").is_empty()


static func can_return_to_hub() -> bool:
	return GameState.state.get("current_system") == Galaxy.INITIAL_SYSTEM


static func is_route_visible(route: Dictionary) -> bool:
	var systems: Dictionary = GameState.state.get("systems", {})
	return route.get("id") in GameState.state.get("known_routes", []) and systems.get(route.get("from"), "hidden") != "hidden" and systems.get(route.get("to"), "hidden") != "hidden"


static func is_destination_known(route_id: String) -> bool:
	return route_id in GameState.state.get("known_routes", [])


static func can_launch() -> bool:
	return not has_combat() and GameState.state.get("current_system") == Galaxy.INITIAL_SYSTEM and GameState.state.get("location") == "hub_tech" and "flight" in DataLoader.get_record("hub_tech").get("actions", [])


static func can_fly() -> bool:
	return GameState.state.get("location") == "ship_bridge" and not is_inside_ship()


static func is_inside_ship() -> bool:
	return GameState.state.get("location") == "ship_bridge" and GameState.state.get("flags", {}).get(GameState.SHIP_INTERIOR_FLAG, false)


static func can_visit_ship() -> bool:
	return can_fly() and not has_combat() and GameState.state.get("flight", {}).get("encounter", "").is_empty()


static func can_leave_ship() -> bool:
	return is_inside_ship() and not has_combat() and GameState.state.get("flight", {}).get("encounter", "").is_empty()


static func can_move_flight() -> bool:
	return can_tick_flight() and float(GameState.state.get("ship", {}).get("fuel", {}).get("current", 0.0)) > 0.0


static func can_tick_flight() -> bool:
	var flight: Dictionary = GameState.state.get("flight", {})
	return not has_combat() and can_fly() and not flight.get("paused", true) and flight.get("encounter", "").is_empty()


static func can_open_flight_map() -> bool:
	return can_use_galaxy_map() and GameState.state.get("flight", {}).get("encounter", "").is_empty()


static func can_pause_flight() -> bool:
	return not has_combat() and can_fly() and GameState.state.get("flight", {}).get("encounter", "").is_empty()


static func can_contact_npc(npc_id: String) -> bool:
	if not can_interact_npc(npc_id):
		return false
	var npc: Dictionary = DataLoader.get_record(npc_id)
	var entry: Dictionary = GameState.state.get("flight", {}).get("npcs", {}).get(npc_id, {})
	return (npc.get("role") == "pirate" or float(entry.get("cooldown", 0.0)) <= 0.0) and event_is_available(str(npc["event"]))


static func can_intercept_player(npc_id: String) -> bool:
	var npc: Dictionary = DataLoader.get_record(npc_id)
	var entry: Dictionary = GameState.state.get("flight", {}).get("npcs", {}).get(npc_id, {})
	if npc.get("role") != "pirate" or entry.get("status") != "chase" or entry.get("target") != "player":
		return false
	return float(entry.get("cooldown", 0.0)) <= 0.0 and can_tick_flight() and can_contact_npc(npc_id)


static func can_select_npc(npc_id: String) -> bool:
	if has_combat() or not can_fly() or not GameState.state.get("flight", {}).get("encounter", "").is_empty() or not npc_is_active(npc_id):
		return false
	var npc: Dictionary = DataLoader.get_record(npc_id)
	return npc["system"] == GameState.state.get("current_system")


static func can_interact_npc(npc_id: String) -> bool:
	return can_select_npc(npc_id) and is_near(GameState.state["flight"]["npcs"][npc_id]["pos"])


static func can_trade_npc(npc_id: String) -> bool:
	return can_interact_npc(npc_id) and DataLoader.get_record(npc_id).has("shop") and can_use_shop(str(DataLoader.get_record(npc_id)["shop"]))


static func can_autopilot_to(system_id: String, routes: Array[String]) -> bool:
	if not can_move_flight() or GameState.state.get("systems", {}).get(system_id, "hidden") == "hidden" or routes.is_empty():
		return false
	if not can_traverse_route(routes[0]):
		return false
	var current: String = str(GameState.state["current_system"])
	for route_id: String in routes:
		var route: Dictionary = DataLoader.get_record(route_id)
		if not is_destination_known(route_id) or route.get("from") != current:
			return false
		current = str(route["to"])
	return current == system_id


static func can_approach_npc(npc_id: String) -> bool:
	return can_move_flight() and npc_is_active(npc_id) and DataLoader.get_record(npc_id).get("system") == GameState.state.get("current_system")


static func event_is_available(event_id: String) -> bool:
	if not DataLoader.record_sources.has("events/" + event_id):
		return false
	return evaluate(DataLoader.get_record(event_id).get("conditions", []))


static func can_start_flight_event(event_id: String) -> bool:
	if not can_pause_flight() or not event_is_available(event_id):
		return false
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["event"] == event_id and can_contact_npc(str(npc["id"])):
			return true
	var system: Dictionary = DataLoader.get_record(str(GameState.state.get("current_system", "")))
	for object: Dictionary in system.get("objects", []):
		if object.get("type") == "event_marker" and object.get("event") == event_id and is_near(object["pos"]):
			return true
	return event_id in system.get("event_pool", []) and DataLoader.get_record(event_id).get("trigger") == "enter_system"


static func can_choose_flight_event(event_id: String, option_index: int) -> bool:
	if has_combat() or not can_fly() or GameState.state.get("flight", {}).get("encounter") != event_id or not DataLoader.record_sources.has("events/" + event_id):
		return false
	var options: Array = DataLoader.get_record(event_id).get("options", [])
	if option_index < 0 or option_index >= options.size():
		return false
	var cost: float = 0.0
	for effect: Dictionary in options[option_index].get("effects", []):
		if effect.has("money") and is_number(effect["money"]):
			cost += maxf(0.0, -float(effect["money"]))
	return float(GameState.state.get("money", 0)) >= cost or cost == 0.0


static func encounter_npc(event_id: String) -> String:
	var nearest: float = INF
	var result: String = ""
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["system"] != GameState.state.get("current_system") or npc["event"] != event_id or not npc_is_active(str(npc["id"])):
			continue
		var position: Array = GameState.state["flight"]["npcs"][npc["id"]]["pos"]
		var distance: float = Motion.point(position).distance_to(Motion.point(GameState.state["flight"]["pos"]))
		if distance <= Motion.INTERACTION_RADIUS and distance < nearest:
			nearest = distance
			result = str(npc["id"])
	return result


static func is_near(position: Array) -> bool:
	return can_fly() and Motion.point(GameState.state["flight"]["pos"]).distance_to(Motion.point(position)) <= Motion.INTERACTION_RADIUS


static func is_near_planet(planet_id: String) -> bool:
	var planet: Dictionary = space_object(planet_id)
	if not can_fly() or planet.get("type") != "planet":
		return false
	var range_from_center: float = Motion.INTERACTION_RADIUS + float(planet["radius"]) / Motion.WORLD_SCALE
	return Motion.point(GameState.state["flight"]["pos"]).distance_to(Motion.point(planet["pos"])) <= range_from_center


static func can_dock() -> bool:
	if has_combat() or not can_return_to_hub() or not can_fly() or not GameState.state.get("flight", {}).get("encounter", "").is_empty():
		return false
	for object: Dictionary in DataLoader.get_record(Galaxy.INITIAL_SYSTEM).get("objects", []):
		if object.get("type") == "planet" and object.get("id") == Galaxy.HUB_PLANET and is_near_planet(str(object["id"])):
			return true
	return false


static func can_traverse_route(route_id: String, boost: bool = false) -> bool:
	if not can_use_galaxy_map() or not DataLoader.record_sources.has("routes/" + route_id):
		return false
	var route: Dictionary = DataLoader.get_record(route_id)
	if route["from"] != GameState.state.get("current_system"):
		return false
	var known: bool = is_destination_known(route_id)
	var required: int = Graph.fuel_cost(float(route["fuel"]["true" if known else "max"]), OrderManager.active_mass(), boost)
	return float(GameState.state.get("ship", {}).get("fuel", {}).get("current", 0.0)) >= required


static func can_jump(route_id: String, boost: bool = false) -> bool:
	if not can_move_flight() or not can_traverse_route(route_id, boost):
		return false
	for object: Dictionary in DataLoader.get_record(str(GameState.state["current_system"])).get("objects", []):
		if object.get("type") == "gate" and object.get("to_route") == route_id and is_near(object["pos"]):
			return true
	return false


static func can_refuel() -> bool:
	var system: Dictionary = DataLoader.get_record(str(GameState.state.get("current_system", "")))
	var fuel: Dictionary = GameState.state.get("ship", {}).get("fuel", {})
	var missing: float = float(fuel.get("max", 0)) - float(fuel.get("current", 0.0))
	var local_access: bool = can_launch()
	for planet: Dictionary in system.get("objects", []):
		if planet.get("type") == "planet" and can_interact_planet(str(planet["id"])):
			local_access = true
	return local_access and system.get("refuel", {}).get("available", false) and missing > 0.0 and int(GameState.state.get("money", 0)) >= ceili(missing * int(system["refuel"]["price_per_unit"]))


static func can_sell_route(route_id: String) -> bool:
	return can_use_galaxy_map() and route_id in GameState.state.get("known_routes", []) and route_id not in GameState.state.get("public_routes", [])


static func can_request_tow() -> bool:
	if not can_use_galaxy_map():
		return false
	if float(GameState.state.get("ship", {}).get("fuel", {}).get("current", 0.0)) <= 0.0:
		return true
	if can_refuel():
		return false
	for route: Dictionary in DataLoader.get_records("routes"):
		if can_traverse_route(str(route["id"])):
			return false
	return true


static func npc_is_active(npc_id: String) -> bool:
	return DataLoader.record_sources.has("npcs/" + npc_id) and npc_id not in GameState.state.get("flight", {}).get("defeated_npcs", []) and GameState.state.get("flight", {}).get("npcs", {}).get(npc_id, {}).get("status", "cruise") not in ["landed", "destroyed"]


static func space_object(object_id: String, system_id: String = "") -> Dictionary:
	if system_id.is_empty():
		system_id = str(GameState.state.get("current_system", ""))
	for object: Dictionary in DataLoader.get_record(system_id).get("objects", []):
		if object.get("id") == object_id or object.get("to_route") == object_id:
			return object
	return {}


static func can_interact_planet(planet_id: String) -> bool:
	var planet: Dictionary = space_object(planet_id)
	return not has_combat() and can_fly() and GameState.state.get("flight", {}).get("encounter", "").is_empty() and planet.get("type") == "planet" and planet.get("inhabited", false) and is_near_planet(planet_id)


static func can_buy_planet_fuel(planet_id: String, amount: float) -> bool:
	if not is_finite(amount) or amount <= 0.0 or not can_interact_planet(planet_id):
		return false
	var system: Dictionary = DataLoader.get_record(str(GameState.state["current_system"]))
	var fuel: Dictionary = GameState.state["ship"]["fuel"]
	return system["refuel"]["available"] and amount <= float(fuel["max"]) - float(fuel["current"]) + 0.000001 and int(GameState.state["money"]) >= ceili(amount * float(system["refuel"]["price_per_unit"]))


static func can_choose_planet_dialogue(planet_id: String, index: int) -> bool:
	if not can_interact_planet(planet_id):
		return false
	var event_id: String = str(space_object(planet_id)["dialogue"])
	var options: Array = DataLoader.get_record(event_id).get("options", [])
	if not event_is_available(event_id) or index < 0 or index >= options.size():
		return false
	var cost: float = 0.0
	for effect: Dictionary in options[index]["effects"]:
		cost += maxf(0.0, -float(effect.get("money", 0)))
	return int(GameState.state["money"]) >= cost


static func can_pirate_target(pirate: Dictionary, entry: Dictionary, target_id: String, entries: Dictionary, acquiring: bool = true) -> bool:
	if pirate.get("role") != "pirate" or entry.get("status") in ["landed", "destroyed"] or float(entry.get("cooldown", 0.0)) > 0.0:
		return false
	var target_pos: Vector2
	if target_id == "player":
		if pirate["system"] != GameState.state.get("current_system") or not event_is_available(str(pirate["event"])):
			return false
		target_pos = Motion.point(GameState.state["flight"]["pos"])
	else:
		var target: Dictionary = DataLoader.get_record(target_id)
		if not entries.has(target_id) or target.get("role") != "civilian" or target.get("system") != pirate["system"] or entries[target_id].get("status") not in ["cruise", "landing"] or target_id in GameState.state["flight"]["defeated_npcs"]:
			return false
		for other_id: String in entries:
			if other_id != pirate["id"] and entries[other_id].get("target") == target_id:
				return false
		target_pos = Motion.point(entries[target_id]["pos"])
	return Motion.point(entry["pos"]).distance_to(target_pos) <= float(pirate["piracy"]["trigger_radius" if acquiring else "lose_radius"])


static func can_form_pirate_pair(npc: Dictionary, other: Dictionary, entries: Dictionary) -> bool:
	if npc["role"] != "pirate" or other["role"] != "pirate" or npc["system"] != other["system"] or npc["id"] == other["id"]:
		return false
	for actor: Dictionary in [npc, other]:
		var entry: Dictionary = entries[actor["id"]]
		if entry["status"] != "cruise" or entry["cooldown"] > 0 or not entry["partner"].is_empty() or entry["pair_timer"] > 0 or actor["id"] in GameState.state["flight"]["defeated_npcs"]:
			return false
	return Motion.point(entries[npc["id"]]["pos"]).distance_to(Motion.point(entries[other["id"]]["pos"])) <= minf(float(npc["pairing"]["radius"]), float(other["pairing"]["radius"]))


static func can_keep_pirate_pair(npc: Dictionary, entries: Dictionary) -> bool:
	var entry: Dictionary = entries[npc["id"]]
	var partner_id: String = str(entry["partner"])
	if partner_id.is_empty() or not entries.has(partner_id):
		return false
	var partner: Dictionary = entries[partner_id]
	if partner["partner"] != npc["id"] or entry["pair_timer"] <= 0 or partner["pair_timer"] <= 0:
		return false
	for actor_id: String in [str(npc["id"]), partner_id]:
		if actor_id in GameState.state["flight"]["defeated_npcs"] or entries[actor_id]["status"] not in ["cruise", "chase"] or entries[actor_id]["cooldown"] > 0:
			return false
	if entry["status"] == "chase" and partner["status"] == "chase" and entry["target"] != partner["target"]:
		return false
	return Motion.point(entry["pos"]).distance_to(Motion.point(partner["pos"])) <= float(npc["pairing"]["radius"])


static func can_police_target(npc: Dictionary, entry: Dictionary, target_id: String, entries: Dictionary, acquiring: bool = true) -> bool:
	if npc["role"] != "patrol" or entry["status"] not in ["cruise", "chase"] or entry["cooldown"] > 0:
		return false
	var target: Dictionary = DataLoader.get_record(target_id)
	if target.get("role") != "pirate" or target.get("system") != npc["system"] or not entries.has(target_id) or target_id in GameState.state["flight"]["defeated_npcs"]:
		return false
	if entries[target_id]["status"] not in ["cruise", "chase"]:
		return false
	return Motion.point(entry["pos"]).distance_to(Motion.point(entries[target_id]["pos"])) <= float(npc["policing"]["trigger_radius" if acquiring else "lose_radius"])


static func star_is_dangerous(position: Vector2) -> bool:
	for object: Dictionary in DataLoader.get_record(str(GameState.state.get("current_system", ""))).get("objects", []):
		if object.get("type") == "star" and position.distance_to(Motion.point(object["pos"])) < float(object["hazard"]["radius"]):
			return true
	return false


static func has_combat() -> bool:
	return not GameState.state.get("combat", {}).is_empty()


static func can_start_combat(enemy_id: String) -> bool:
	return can_fly() and not has_combat() and DataLoader.record_sources.has("enemies/" + enemy_id) and not CombatMath.player_weapon().is_empty()


static func can_act_combat() -> bool:
	return has_combat() and GameState.state["combat"].get("result") == "active"


static func can_move_combat(target: Vector2i) -> bool:
	return not combat_move_path(target).is_empty()


static func combat_move_path(target: Vector2i) -> Array[Vector2i]:
	if not can_act_combat():
		return []
	var combat: Dictionary = GameState.state["combat"]
	return CombatRoutes.path(combat["player"], target, combat["movement"]["player"], int(combat["move_points"]), CombatMath.movement_settings(true), CombatMath.cell(combat["opponent"]["pos"]))


static func can_move_vessel(vessel: Dictionary, target: Vector2i, turn: Dictionary, remaining: int, settings: Dictionary, occupied: Vector2i) -> bool:
	return not vessel_move_path(vessel, target, turn, remaining, settings, occupied).is_empty()


static func vessel_move_path(vessel: Dictionary, target: Vector2i, turn: Dictionary, remaining: int, settings: Dictionary, occupied: Vector2i) -> Array[Vector2i]:
	return CombatRoutes.path(vessel, target, turn, remaining, settings, occupied)


static func can_undo_combat_move() -> bool:
	return can_act_combat() and not GameState.state["combat"]["movement"]["player"]["history"].is_empty()


static func can_fire_weapon(attacker: Dictionary, target: Dictionary, weapon: Dictionary, ap: int, fired: Array = []) -> bool:
	if weapon.is_empty() or weapon.get("id") in fired:
		return false
	var origin: Vector2i = CombatMath.cell(attacker["pos"])
	var destination: Vector2i = CombatMath.cell(target["pos"])
	var distance: float = CombatMath.distance(origin, destination)
	return CombatMath.inside(destination) and ap >= int(weapon["ap_cost"]) and distance > 0 and distance <= float(weapon["range"]) and CombatMath.in_arc(origin, destination, int(attacker["facing"]), weapon)


static func can_shoot_combat(weapon_id: String, target: Vector2i) -> bool:
	if not can_act_combat():
		return false
	var combat: Dictionary = GameState.state["combat"]
	return weapon_id in GameState.state["ship"]["modules"] and DataLoader.get_record(weapon_id).get("slot") == "weapon" and can_fire_weapon(combat["player"], {"pos": CombatMath.coordinates(target)}, DataLoader.get_record(weapon_id), int(combat["ap"]), combat["fired"]["player"])


static func weapon_has_fired(actor: String, weapon_id: String) -> bool:
	return has_combat() and weapon_id in GameState.state["combat"]["fired"].get(actor, [])


static func can_shield_combat() -> bool:
	return can_use_combat_ability("shield_reboot")


static func can_use_combat_ability(ability_id: String) -> bool:
	if not can_act_combat() or not DataLoader.record_sources.has("abilities/" + ability_id):
		return false
	var ability: Dictionary = DataLoader.get_record(ability_id)
	var owner: String = str(ability["owner"])
	var combat: Dictionary = GameState.state["combat"]
	if not evaluate([{"aboard": owner, "is": true}]) or ability_id not in DataLoader.get_record(owner).get("abilities", []):
		return false
	var cost: int = CombatMath.ability_ap_cost(ability)
	if owner not in GameState.state["ship"]["crew_aboard"] or cost <= 0 or int(combat["ap"]) < cost or int(combat["cooldowns"].get(ability_id, 0)) > 0:
		return false
	if ability["effect"].has("shield_restore") and (not combat["shield_recharge"].is_empty() or float(combat["player"]["shield"]) >= CombatMath.player_shield_max()):
		return false
	return not ability["effect"].has("fuel") or float(GameState.state["ship"]["fuel"]["current"]) >= float(ability["effect"]["fuel"])


static func can_finish_combat() -> bool:
	return has_combat() and GameState.state["combat"].get("result") in ["victory", "defeat"]


static func can_accept_order(order_id: String) -> bool:
	if not can_use_order_terminal() or not DataLoader.record_sources.has("orders/" + order_id):
		return false
	if GameState.state.get("orders", {}).has(order_id):
		return false
	var order: Dictionary = DataLoader.get_record(order_id)
	if order.get("source") == "shop":
		return false
	if not evaluate(order.get("requires", [])):
		return false
	var capacity: float = float(GameState.state.get("ship", {}).get("cargo", {}).get("max_mass", 0))
	return OrderManager.active_mass() + float(order.get("cargo", {}).get("mass", 0)) <= capacity


static func can_settle_order(order_id: String, status: String, require_terminal: bool = true) -> bool:
	if DataLoader.get_record(order_id).get("source") == "shop":
		return false
	if status not in ["completed", "failed"] or OrderManager.status(order_id) != "active":
		return false
	if status == "completed":
		return can_deliver_order(order_id)
	return not require_terminal or can_use_order_terminal()


static func can_deliver_order(order_id: String) -> bool:
	if has_combat() or not can_fly() or not GameState.state.get("flight", {}).get("encounter", "").is_empty():
		return false
	var order: Dictionary = DataLoader.get_record(order_id)
	var planet_id: String = str(order.get("to_planet", ""))
	return is_delivery_destination(order_id, planet_id) and is_near_planet(planet_id)


static func is_delivery_destination(order_id: String, planet_id: String) -> bool:
	if OrderManager.status(order_id) != "active" or OrderManager.is_overdue(order_id):
		return false
	var order: Dictionary = DataLoader.get_record(order_id)
	return order.get("to") == GameState.state.get("current_system") and order.get("to_planet") == planet_id and space_object(planet_id).get("type") == "planet"


static func active_order_ids() -> Array[String]:
	var result: Array[String] = []
	for order_id: String in GameState.state.get("orders", {}):
		if OrderManager.status(order_id) == "active":
			result.append(order_id)
	return result


static func accepted_order_ids() -> Array[String]:
	var result: Array[String] = active_order_ids()
	for order_id: String in GameState.state.get("orders", {}):
		if OrderManager.status(order_id) in ["completed", "failed"]:
			result.append(order_id)
	return result


static func planet_has_active_delivery(planet_id: String) -> bool:
	for order_id: String in active_order_ids():
		if is_delivery_destination(order_id, planet_id):
			return true
	return false


static func domestic_available() -> bool:
	return not has_combat() and GameState.state.get("current_system") == Galaxy.INITIAL_SYSTEM and DataLoader.get_record(str(GameState.state.get("location", ""))).get("area") == "hub"


static func can_use_room_panels() -> bool:
	return not has_combat() and (domestic_available() or is_inside_ship())


static func can_open_domestic(tab: String) -> bool:
	match tab:
		"inventory": return can_use_room_panels()
		"kitchen": return can_open_kitchen()
		"shop": return domestic_available() and GameState.state.get("location") == "hub_shop"
	return false


static func can_open_kitchen() -> bool:
	return domestic_available() and GameState.state.get("location") == "hub_kitchen" and "kitchen" in DataLoader.get_record("hub_kitchen").get("actions", [])


static func can_use_hub_hotspot(layout_id: String) -> bool:
	if not domestic_available() or not DataLoader.record_sources.has("ui/" + layout_id):
		return false
	var layout: Dictionary = DataLoader.get_record(layout_id)
	if layout.get("location") != GameState.state.get("location"):
		return false
	if layout.get("zones", {}).has("cook"):
		return can_open_kitchen()
	if layout.get("zones", {}).has("ship"):
		return can_modify_ship()
	return can_use_order_terminal() or can_launch()


static func can_modify_ship() -> bool:
	return domestic_available() and GameState.state.get("location") == "hub_tech" and GameState.state.get("kitchen", {}).is_empty()


static func can_install_module(module_id: String, target_slot: String = "") -> bool:
	if not can_modify_ship() or not DataLoader.record_sources.has("modules/" + module_id):
		return false
	var module: Dictionary = DataLoader.get_record(module_id)
	var ship: Dictionary = GameState.state["ship"]
	var slot: String = ShipLoadout.slot_for(module)
	if not target_slot.is_empty() and slot != target_slot:
		return false
	if slot not in ShipLoadout.SLOTS or not evaluate(module.get("requires", [])) or module_id in ship["modules"]:
		return false
	return slot != "armor" or float(ShipLoadout.replacement_hull(ship, module)["current"]) > 0.0


static func can_use_shop(shop_id: String = "hub_shop_stock") -> bool:
	var shop: Dictionary = DataLoader.get_record(shop_id)
	if not shop.has("owner"):
		for planet: Dictionary in DataLoader.get_record(str(GameState.state.get("current_system", ""))).get("objects", []):
			if planet.get("shop") == shop_id and can_interact_planet(str(planet["id"])):
				return Clock.current_slot() in shop.get("open_slots", [])
		for npc: Dictionary in DataLoader.get_records("npcs"):
			if npc.get("shop") == shop_id and can_interact_npc(str(npc["id"])):
				return Clock.current_slot() in shop.get("open_slots", [])
		return false
	return domestic_available() and GameState.state.get("location") == "hub_shop" and Clock.current_slot() in shop.get("open_slots", []) and is_present(str(shop.get("owner", "")))


static func can_buy_item(shop_id: String, item_id: String) -> bool:
	if not can_use_shop(shop_id):
		return false
	var shop: Dictionary = DataLoader.get_record(shop_id)
	for entry: Dictionary in shop.get("items", []):
		if entry["item"] == item_id:
			var attitude: float = float(GameState.state["heroines"][shop["owner"]]["attitude"]) if shop.has("owner") else 0.0
			return attitude >= float(entry.get("min_attitude", 0)) and int(GameState.state["money"]) >= int(entry["price"]) and can_apply_inventory_effects([{"item": item_id, "add": 1}])
	return false


static func can_sell_item(shop_id: String, item_id: String) -> bool:
	return can_use_shop(shop_id) and DataLoader.get_record(item_id).get("type") in DataLoader.get_record(shop_id).get("buys", []) and Inventory.count(item_id, Inventory.entries(item_id)) > 0


static func can_apply_inventory_effects(effects: Array) -> bool:
	var ship: Dictionary = GameState.state.get("ship", {}).duplicate(true)
	var food: Array = GameState.state.get("inventory", []).duplicate(true)
	var changed: bool = false
	for effect: Dictionary in effects:
		if not effect.has("item"):
			continue
		var item_id: String = str(effect["item"])
		changed = true
		if not DataLoader.record_sources.has("items/" + item_id):
			return false
		var entries: Array = food if Inventory.is_food(item_id) else ship.get("cargo", {}).get("items", [])
		if Inventory.count(item_id, entries) + int(effect["add"]) < 0:
			return false
		Inventory.change(entries, item_id, int(effect["add"]), 1 if int(effect["add"]) > 0 and DataLoader.get_record(item_id).get("type") == "dish" else 0)
	if changed:
		for entry: Dictionary in GameState.state.get("kitchen", {}).get("entries", []):
			if Inventory.count(str(entry["item"]), food) < Domestic.reserved(str(entry["item"]), GameState.state["kitchen"]):
				return false
	return not changed or Inventory.total_mass(ship, GameState.state.get("orders", {})) <= float(ship.get("cargo", {}).get("max_mass", 0))


static func can_read_book(index: int) -> bool:
	var entries: Array = GameState.state.get("ship", {}).get("cargo", {}).get("items", [])
	return domestic_available() and index >= 0 and index < entries.size() and DataLoader.get_record(str(entries[index]["item"])).get("type") == "cookbook"


static func can_prepare_ingredient(recipe_id: String, item_id: String, zone: String, entry_index: int = -1) -> bool:
	if not domestic_available() or GameState.state.get("location") != "hub_kitchen" or recipe_id not in GameState.state.get("known_recipes", []):
		return false
	if zone not in Domestic.ZONES or entry_index < -1:
		return false
	var kitchen: Dictionary = GameState.state.get("kitchen", {})
	if not kitchen.is_empty() and kitchen["recipe"] != recipe_id:
		return false
	var entries: Array = kitchen.get("entries", [])
	if entry_index >= 0:
		if entry_index >= entries.size() or entries[entry_index]["item"] != item_id or entries[entry_index]["zone"] == zone:
			return false
		return zone != "plate" or not entries[entry_index]["steps"].is_empty()
	if zone == "plate" or DataLoader.get_record(item_id).get("type") != "ingredient":
		return false
	var reserved: int = Domestic.reserved(item_id, kitchen)
	for ingredient: Dictionary in DataLoader.get_record(recipe_id).get("ingredients", []):
		if ingredient["item"] == item_id:
			return reserved < int(ingredient["count"]) and reserved < Inventory.count(item_id, GameState.state["inventory"])
	return false


static func can_process_kitchen_entry(entry: Dictionary, zone: String) -> bool:
	return zone != "plate" and entry.get("zone") == zone and zone in DataLoader.get_record(str(entry.get("item", ""))).get("preparations", []) and zone not in entry.get("steps", [])


static func can_process_kitchen_zone(zone: String) -> bool:
	if not domestic_available() or GameState.state.get("location") != "hub_kitchen" or zone not in Domestic.ZONES:
		return false
	for entry: Dictionary in GameState.state.get("kitchen", {}).get("entries", []):
		if can_process_kitchen_entry(entry, zone):
			return true
	return false


static func can_finish_cooking() -> bool:
	var kitchen: Dictionary = GameState.state.get("kitchen", {})
	if not domestic_available() or GameState.state.get("location") != "hub_kitchen" or kitchen.is_empty():
		return false
	for entry: Dictionary in kitchen["entries"]:
		if entry["zone"] != "plate" or entry["steps"].is_empty():
			return false
	var ingredients: Array = DataLoader.get_record(str(kitchen["recipe"])).get("ingredients", [])
	if not evaluate(ingredients):
		return false
	for ingredient: Dictionary in ingredients:
		if Domestic.reserved(str(ingredient["item"]), kitchen) != int(ingredient["count"]):
			return false
	return true


static func can_use_food(index: int, heroine_id: String = "") -> bool:
	var food: Array = GameState.state.get("inventory", [])
	if not domestic_available() or not GameState.state.get("kitchen", {}).is_empty() or GameState.state.get("location") != "hub_kitchen" or index < 0 or index >= food.size() or DataLoader.get_record(str(food[index]["item"])).get("type") != "dish":
		return false
	if heroine_id.is_empty():
		return true
	return can_offer_meal(index, heroine_id, Clock.current_day())


static func can_talk(heroine_id: String) -> bool:
	return not has_combat() and GameState.state.get("kitchen", {}).is_empty() and is_present(heroine_id) and not GameState.state["heroines"][heroine_id].get("contact_block", false)


static func can_open_conversation(heroine_id: String) -> bool:
	if can_talk(heroine_id):
		return true
	if has_combat() or not GameState.state.get("kitchen", {}).is_empty() or not is_present(heroine_id):
		return false
	for scene: Dictionary in DataLoader.get_records("scenes"):
		if Scenes.heroine(scene) == heroine_id and ("disclosure" in scene.get("tags", []) or "reconciliation" in scene.get("tags", [])) and evaluate_scene(scene):
			return true
	return false


static func should_disclose(heroine_id: String) -> bool:
	var heroine: Dictionary = GameState.state.get("heroines", {}).get(heroine_id, {})
	return heroine.get("polygamy") == "forbids" and float(heroine.get("suspicion", 0)) >= 100 and not heroine.get("contact_block", false)


static func can_present_pending_scene(scene_id: String) -> bool:
	var scene: Dictionary = DataLoader.get_record(scene_id)
	return scene_id in GameState.state.get("pending_scenes", []) and domestic_available() and GameState.state.get("kitchen", {}).is_empty() and is_present(Scenes.heroine(scene)) and evaluate_scene(scene)


static func next_pending_scene() -> String:
	for scene_id: String in GameState.state.get("pending_scenes", []):
		if can_present_pending_scene(scene_id):
			return scene_id
	return ""


static func can_offer_meal(index: int, heroine_id: String, day: int) -> bool:
	var food: Array = GameState.state.get("inventory", [])
	if not domestic_available() or not can_talk(heroine_id) or index < 0 or index >= food.size() or DataLoader.get_record(str(food[index]["item"])).get("type") != "dish":
		return false
	return float(GameState.state["heroines"][heroine_id]["mood"]) >= 20.0 and int(GameState.state.get("served_days", {}).get(heroine_id, 0)) < day and not GameState.state.get("meal_invites", {}).has(heroine_id)


static func can_invite_to_meal(index: int, heroine_id: String) -> bool:
	var arrival: Dictionary = Meals.arrival(Clock.current_day(), Clock.current_slot())
	return GameState.state.get("location") != "hub_kitchen" and can_offer_meal(index, heroine_id, int(arrival["day"]))


static func meal_offer_status(heroine_id: String) -> String:
	if GameState.state.get("heroines", {}).get(heroine_id, {}).get("contact_block", false):
		return "contact_blocked"
	var invitation: Dictionary = GameState.state.get("meal_invites", {}).get(heroine_id, {})
	if not invitation.is_empty():
		return "eating" if Meals.is_due(invitation, Clock.current_day(), Clock.current_slot()) else "pending"
	if not GameState.state.get("kitchen", {}).is_empty():
		return "blocked"
	if float(GameState.state.get("heroines", {}).get(heroine_id, {}).get("mood", 0)) < 20:
		return "refusal"
	var day: int = Clock.current_day() if GameState.state.get("location") == "hub_kitchen" else int(Meals.arrival(Clock.current_day(), Clock.current_slot())["day"])
	return "daily_limit" if int(GameState.state.get("served_days", {}).get(heroine_id, 0)) >= day else ""


static func can_resolve_meal_invite(heroine_id: String) -> bool:
	return meal_is_due(heroine_id) and GameState.state.get("heroines", {}).get(heroine_id, {}).get("loc") == "hub_kitchen" and int(GameState.state.get("served_days", {}).get(heroine_id, 0)) < Clock.current_day()


static func meal_is_due(heroine_id: String) -> bool:
	return Meals.is_due(GameState.state.get("meal_invites", {}).get(heroine_id, {}), Clock.current_day(), Clock.current_slot())


static func meal_has_expired(heroine_id: String) -> bool:
	var entry: Dictionary = GameState.state.get("meal_invites", {}).get(heroine_id, {})
	return not entry.is_empty() and Meals.turn(int(entry["day"]), str(entry["time_slot"])) < Meals.turn(Clock.current_day(), Clock.current_slot())


static func can_accept_shop_quest(order_id: String) -> bool:
	var order: Dictionary = DataLoader.get_record(order_id)
	return can_use_shop() and order.get("source") == "shop" and not GameState.state.get("orders", {}).has(order_id) and evaluate(order.get("requires", []))


static func can_complete_shop_quest(order_id: String) -> bool:
	var order: Dictionary = DataLoader.get_record(order_id)
	return can_use_shop() and order.get("source") == "shop" and OrderManager.status(order_id) == "active" and evaluate(order.get("need_items", []))


static func condition_kind(condition: Dictionary) -> String:
	var kind: String = ""
	for candidate: String in CONDITION_FIELDS:
		if condition.has(candidate):
			if not kind.is_empty():
				return ""
			kind = candidate
	return kind


static func valid_stat_path(path: Variant) -> bool:
	if not path is String:
		return false
	var parts: PackedStringArray = path.split(".")
	return parts.size() == 2 and not parts[0].is_empty() and parts[1] in STAT_NAMES + ["suspicion"]


static func is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _evaluate_one(condition: Dictionary) -> bool:
	match condition_kind(condition):
		"contact_block":
			var heroine: Variant = GameState.state.get("heroines", {}).get(condition["contact_block"])
			return heroine is Dictionary and heroine.get("contact_block") == condition["is"]
		"item":
			return Inventory.count(str(condition["item"]), Inventory.entries(str(condition["item"]))) >= int(condition["count"])
		"flag":
			return GameState.state.get("flags", {}).get(condition["flag"], false) == condition["is"]
		"time":
			return Clock.current_slot() in condition["time"]
		"rep":
			var reputation: Variant = GameState.state.get("reputation", {}).get(condition["rep"])
			return is_number(reputation) and _compare(float(reputation), str(condition["op"]), float(condition["value"]))
		"at":
			return GameState.state.get("location", "") == condition["at"]
		"others_absent":
			var crew: Dictionary = GameState.state.get("heroines", {})
			for heroine_id: String in condition["others_absent"]:
				if not crew.has(heroine_id) or not crew[heroine_id] is Dictionary:
					return false
				if crew[heroine_id].get("loc", "") == GameState.state.get("location", ""):
					return false
			return true
		"aboard":
			var crew: Dictionary = GameState.state.get("heroines", {})
			return crew.has(condition["aboard"]) and crew[condition["aboard"]] is Dictionary and crew[condition["aboard"]].get("aboard", false) == condition["is"]
		"stat":
			var path: PackedStringArray = str(condition["stat"]).split(".")
			var crew: Dictionary = GameState.state.get("heroines", {})
			if not crew.has(path[0]) or not crew[path[0]] is Dictionary:
				return false
			var actual: Variant = crew[path[0]].get(path[1])
			if not is_number(actual):
				return false
			return _compare(float(actual), str(condition["op"]), float(condition["value"]))
	return false


static func _compare(actual: float, operator: String, expected: float) -> bool:
	match operator:
		"==": return actual == expected
		"!=": return actual != expected
		">": return actual > expected
		">=": return actual >= expected
		"<": return actual < expected
		"<=": return actual <= expected
	return false
