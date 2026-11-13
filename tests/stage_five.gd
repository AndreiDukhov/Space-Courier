extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Graph = preload("res://scripts/galaxy_graph.gd")
const Navigation = preload("res://scripts/galaxy_navigation.gd")
const Validator = preload("res://scripts/data_validator.gd")
const Service = preload("res://scripts/hub_service.gd")
const Text = preload("res://scripts/ui_text.gd")
const SAVE_PATH: String = "res://.godot/stage-five-save-test.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All galaxy and order records load without errors")
	_check_orders()
	_check_graph()
	_check_discovery()
	_check_travel()
	_check_economy()
	_check_validation()
	_check_persistence()
	await _check_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 5 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _workshop() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true, "pirate_test_bribed": true})
	for npc: Dictionary in GameState.state["flight"]["npcs"].values():
		npc["cooldown"] = 10000.0
	_check(Service.travel("hub_tech") == OK, "The map test begins in the workshop")


func _travel(route_id: String, boost: bool = false) -> Error:
	if not Conditions.can_traverse_route(route_id, boost):
		return ERR_UNAVAILABLE
	if Conditions.can_launch():
		EffectApplier.launch_flight()
	var system: Dictionary = DataLoader.get_record(str(GameState.state["current_system"]))
	for object: Dictionary in system["objects"]:
		if object.get("type") == "gate" and object.get("to_route") == route_id:
			# Place the fixture at the gate to isolate interstellar fuel checks.
			GameState.state["flight"]["pos"] = [float(object["pos"][0]), float(object["pos"][1])]
			GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	return EffectApplier.jump_route(route_id, boost)


func _check_orders() -> void:
	for order: Dictionary in DataLoader.get_records("orders"):
		if order.get("source") == "shop":
			continue
		_check(order["description"].begins_with("текст"), "Order descriptions contain only test placeholder text")
		var planet_ids: Array[String] = []
		for object: Dictionary in DataLoader.get_record(str(order["to"]))["objects"]:
			if object["type"] == "planet":
				planet_ids.append(str(object["id"]))
		_check(order["to_planet"] in planet_ids, "Every delivery address resolves to a planet in its own system")


func _check_graph() -> void:
	var routes: Array[Dictionary] = [
		{"id": "ab", "from": "a", "to": "b", "fuel": {"min": 1, "max": 3, "true": 3}},
		{"id": "bc", "from": "b", "to": "c", "fuel": {"min": 1, "max": 3, "true": 3}},
		{"id": "ac", "from": "a", "to": "c", "fuel": {"min": 3, "max": 7, "true": 4}}
	]
	_check(Graph.shortest_path("a", "c", routes, [], 0) == ["ab", "bc"], "Dijkstra uses the midpoint while fuel is unknown")
	_check(Graph.shortest_path("a", "c", routes, ["ab", "bc", "ac"], 0) == ["ac"], "Dijkstra uses measured fuel after discovery")
	_check(Graph.shortest_path("c", "a", routes, [], 0).is_empty(), "Directed edges never create an implicit return route")
	_check(Graph.shortest_path("a", "a", routes, [], 0).is_empty(), "A path to the current system has no legs")
	_check(Graph.shortest_path("a", "missing", routes, [], 0).is_empty(), "An unreachable destination has no path")
	_check(Graph.fuel_cost(4, 2) == 5 and Graph.fuel_cost(4, 2, true) == 7, "Cargo and boost multiply before rounding up")
	_check(Graph.estimate(routes[2], 0, false) == 5 and Graph.estimate(routes[2], 0, true) == 4, "A hidden true value cannot affect an expected fuel estimate")


func _check_discovery() -> void:
	_workshop()
	_check(GameState.state["current_system"] == "sys_earth" and GameState.state["systems"]["sys_earth"] == "visited", "A new game begins in the visited hub system")
	_check(GameState.state["systems"]["sys_alpha"] == "hidden" and GameState.state["systems"]["sys_beta"] == "hidden", "Untraversed gates do not reveal destination icons")
	_check(GameState.state["systems"]["sys_colony_3"] == "hidden" and GameState.state["systems"]["sys_far"] == "hidden", "Distant systems remain hidden")
	_check(Navigation.visible_routes().is_empty() and not Conditions.is_route_visible(DataLoader.get_record("r_alpha_earth")), "Seen systems do not expose their outgoing routes")
	_check(GameState.state["known_routes"].is_empty() and GameState.state["public_routes"] == ["r_earth_alpha"], "Public route existence does not reveal true fuel costs")
	_check(Navigation.plan("sys_alpha").is_empty() and Navigation.plan("sys_colony_3").is_empty(), "Planning uses only visible directed connections")
	Service.travel("hub_office")
	_check(OrderManager.accept("ord_private_01") == OK and GameState.state["systems"]["sys_colony_3"] == "seen", "Accepting an order reveals its destination system")
	Service.travel("hub_tech")
	_check(Navigation.plan("sys_colony_3").is_empty(), "A revealed order destination does not disclose unknown connections")
	_check(Navigation.return_warning("sys_alpha", Navigation.plan("sys_alpha")) == "ui_map_return_unknown", "A destination without known exits warns about its return path")
	_check(EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}, {"unlock_route": "r_alpha_colony"}]) == OK, "Route discovery uses the shared effect language")
	_check("r_alpha_colony" in GameState.state["known_routes"] and Navigation.plan("sys_colony_3") == ["r_earth_alpha", "r_alpha_colony"], "An unlocked connection can extend a planned journey")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.apply_effects([{"money": 1}, {"unlock_route": "missing"}]) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Unknown route effects reject an entire batch before mutation")


func _check_travel() -> void:
	_workshop()
	var snapshot: Dictionary = GameState.serialize()
	_check(_travel("r_alpha_earth") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "A jump must begin in the current system")
	Service.travel("hub_office")
	_check(OrderManager.accept("ord_private_01") == OK, "The fuel test carries an actual order")
	Service.travel("hub_tech")
	var one_route: Array[String] = ["r_earth_alpha"]
	_check(Navigation.path_cost(one_route, "min") == 4 and Navigation.path_cost(one_route, "max") == 7, "The displayed fuel range includes cargo mass")
	GameState.state["ship"]["fuel"]["current"] = 6
	snapshot = GameState.serialize()
	_check(not Conditions.can_jump("r_earth_alpha") and _travel("r_earth_alpha") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "An unknown route requires its displayed upper bound without leaking the true cost")
	GameState.state["ship"]["fuel"]["current"] = 30
	_check(_travel("r_earth_alpha") == OK, "An available route can be traversed")
	_check(GameState.state["current_system"] == "sys_alpha" and GameState.state["location"] == "ship_bridge", "Travel leaves the hub building behind")
	_check(GameState.state["ship"]["fuel"]["current"] == 25 and Clock.current_day() == 2 and Clock.current_slot() == "morning", "Travel spends true cargo-adjusted fuel and whole game days")
	_check(GameState.state["systems"]["sys_alpha"] == "visited" and GameState.state["systems"]["sys_far"] == "hidden", "Arrival keeps untraversed gate destinations hidden")
	_check("r_earth_alpha" in GameState.state["known_routes"] and "r_alpha_earth" not in GameState.state["known_routes"], "Only the traversed direction reveals its actual cost")
	_check(Navigation.path_cost(one_route, "min") == 5 and Navigation.path_cost(one_route, "max") == 5, "A measured route displays one exact fuel cost")
	_check(not Conditions.can_return_to_hub() and not Conditions.can_enter("hub_office") and not Conditions.can_use_order_terminal(), "Remote travel cannot reopen a room in the hub building")
	_check(_travel("r_alpha_earth") == OK and GameState.state["location"] == "ship_bridge" and Conditions.can_return_to_hub(), "A separate reverse route returns to the home system without docking")
	_check(GameState.state["ship"]["fuel"]["current"] == 19 and Clock.current_day() == 3, "The reverse route has its own cargo-adjusted cost and duration")
	_check(GameState.state["known_routes"].size() == 2 and _travel("r_earth_alpha") == OK and GameState.state["known_routes"].size() == 2, "Repeated travel does not duplicate discovered routes")
	_check(OrderManager.status("ord_private_01") == "failed" and GameState.state["money"] == 880 and OrderManager.active_mass() == 0, "Jump days expire orders through the existing failure system")
	_workshop()
	_check(_travel("r_earth_alpha", true) == OK and GameState.state["ship"]["fuel"]["current"] == 24, "Boost spends fifty percent more fuel")
	_check(Navigation.return_warning("sys_earth", Navigation.plan("sys_earth")) == "", "The current home destination has no extra unknown return leg")
	EffectApplier.apply_effects([{"unlock_route": "r_alpha_earth"}])
	GameState.state["ship"]["fuel"]["current"] = 1
	_check(Navigation.return_warning("sys_earth", Navigation.plan("sys_earth")) == "ui_map_return_fuel", "Planning warns when even the return budget may exceed available fuel")


func _check_economy() -> void:
	_workshop()
	_check(not Conditions.can_refuel() and not Conditions.can_sell_route("r_alpha_earth"), "A full tank and an unmeasured route have no economy action")
	_check(_travel("r_earth_alpha") == OK and not Conditions.can_refuel(), "Refuelling requires approaching a planet after arrival")
	GameState.state["flight"]["pos"] = [1080.0, 840.0]
	GameState.state["flight"]["target"] = [1080.0, 840.0]
	_check(EffectApplier.refuel_ship() == OK, "An inhabited planet provides local fuel service")
	_check(GameState.state["money"] == 880 and GameState.state["ship"]["fuel"]["current"] == 30, "Refuelling pays missing units at the system's JSON price")
	_check(_travel("r_alpha_earth") == OK and Conditions.can_sell_route("r_alpha_earth"), "A privately measured reverse route can be sold")
	var before_sale: int = int(GameState.state["money"])
	_check(EffectApplier.sell_route("r_alpha_earth") == OK and GameState.state["money"] == before_sale + 60, "Selling a chart pays map_value")
	var snapshot: Dictionary = GameState.serialize()
	_check("r_alpha_earth" in GameState.state["public_routes"] and EffectApplier.sell_route("r_alpha_earth") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Publication is saved and cannot pay out twice")
	GameState.state["money"] = 0
	snapshot = GameState.serialize()
	_check(EffectApplier.refuel_ship() == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Refuelling cannot silently overdraw money")
	_workshop()
	_check(_travel("r_earth_beta") == OK, "The rescue test reaches a different system")
	_check(not Conditions.can_refuel(), "Fuel service cannot be used remotely from deep space")
	GameState.state["ship"]["fuel"]["current"] = 1
	_check(Conditions.can_request_tow(), "A ship with too little fuel for every exit can also request rescue")
	GameState.state["ship"]["fuel"]["current"] = 0
	GameState.state["money"] = 0
	_check(Conditions.can_request_tow() and EffectApplier.request_tow() == OK, "A zero-fuel ship has a rescue action")
	_check(GameState.state["current_system"] == "sys_earth" and GameState.state["location"] == "ship_bridge" and GameState.state["money"] == -EffectApplier.TOW_FEE and GameState.state["ship"]["fuel"]["current"] == 30, "The test tow returns the ship with debt instead of ending the game")
	snapshot = GameState.serialize()
	_check(EffectApplier.request_tow() == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Rescue cannot be repeatedly invoked after recovery")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["routes"][0]["fuel"]["true"] = 999
	_check("true fuel must be inside" in "\n".join(Validator.validate(groups, {})), "Invalid true fuel bounds are reported at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["routes"][0]["to"] = "missing"
	_check("unknown systems id 'missing'" in "\n".join(Validator.validate(groups, {})), "Broken route endpoints are reported by id")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["routes"][0]["days"] = 0.5
	_check("invalid days" in "\n".join(Validator.validate(groups, {})), "Fractional journey days are rejected")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["routes"][0]["directed"] = false
	_check("routes must be directed" in "\n".join(Validator.validate(groups, {})), "Reverse routes require independent records")
	groups = DataLoader.records_by_group.duplicate(true)
	for i: int in range(groups["routes"].size() - 1, -1, -1):
		if groups["routes"][i]["from"] == "sys_far":
			groups["routes"].remove_at(i)
	_check("sys_far: no directed return path to the hub" in "\n".join(Validator.validate(groups, {})), "A stranded system fails startup graph validation")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["to_planet"] = "earth_1"
	_check("to_planet must belong" in "\n".join(Validator.validate(groups, {})), "An existing planet in the wrong system is rejected")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["description"] = 42
	_check("description must be a nonempty string" in "\n".join(Validator.validate(groups, {})), "Order descriptions must be displayable text")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["systems"][1]["objects"][0]["id"] = "earth_1"
	_check("Duplicate planet id" in "\n".join(Validator.validate(groups, {})), "Planet ids are unique across system files")


func _check_persistence() -> void:
	_workshop()
	_check(_travel("r_earth_alpha") == OK and _travel("r_alpha_earth") == OK and EffectApplier.sell_route("r_alpha_earth") == OK, "Persistence stores travel and chart publication")
	_check(_travel("r_earth_alpha") == OK, "The snapshot is saved away from the hub")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "A galaxy snapshot serializes successfully")
	_workshop()
	var load_result: Error = GameState.load_game(SAVE_PATH)
	_check(load_result == OK and GameState.serialize() == snapshot, "System, fog, fuel and route publication restore exactly")
	for replacement: Dictionary in [
		{"current_system": "missing"}, {"current_system": "sys_far"},
		{"known_routes": ["missing"]}, {"known_routes": ["r_earth_alpha", "r_earth_alpha"]},
		{"public_routes": ["missing"]}, {"systems": {}}, {"systems": {"sys_earth": "unknown"}}, {"location": "hub_office"}
	]:
		var invalid: Dictionary = snapshot.duplicate(true)
		for key: String in replacement:
			invalid[key] = replacement[key]
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Malformed galaxy snapshots cannot replace running state")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["ship"]["fuel"]["current"] = -1
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Negative saved fuel is rejected")
	invalid = snapshot.duplicate(true)
	invalid["ship"]["fuel"]["current"] = 31
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Saved fuel cannot exceed capacity")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The verification save is removed")


func _check_view() -> void:
	_workshop()
	var hub_scene: PackedScene = load("res://scenes/hub.tscn")
	var hub: Control = hub_scene.instantiate()
	add_child(hub)
	await get_tree().process_frame
	_check(hub.get_node("TechHotspot").visible, "The workshop exposes its computer")
	Service.travel("hub_office")
	hub.get_node("OfficeHotspot/Computer").pressed.emit()
	var terminal: Control = hub.get_node("%TerminalContent").get_child(0)
	var card: Control = terminal.get_node("%Orders/ord_private_01")
	_check(card.find_child("Payment", true, false).text == Text.get_text("ui_order_payment", {"amount": 600}), "Payment is visible before accepting an order")
	_check("TODO Колония-3" in card.find_child("Destination", true, false).text and "TODO Планета-3" in card.find_child("Destination", true, false).text, "The order card shows its system and exact planet name")
	_check(card.tooltip_text == DataLoader.get_record("ord_private_01")["description"] and "{" not in card.tooltip_text, "Hovering an order shows placeholder prose instead of JSON")
	_check("{" not in card.find_child("Accept", true, false).tooltip_text and "Принять" in card.find_child("Accept", true, false).tooltip_text, "Action buttons also have readable hints")
	await _capture("orders")
	if "--capture-galaxy" in OS.get_cmdline_user_args():
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		var hover_target: Control = terminal.get_node("%Orders/ord_crime_01")
		motion.position = hover_target.get_global_rect().position + Vector2(25, 82)
		get_viewport().push_input(motion)
		await get_tree().create_timer(0.8).timeout
		await _capture("tooltip")
	hub.get_node("%CloseTerminal").pressed.emit()
	Service.travel("hub_tech")
	hub.get_node("TechHotspot/Computer").pressed.emit()
	hub.get_node("%TerminalContent/ComputerMenu/Map").pressed.emit()
	await get_tree().process_frame
	var map: Control = hub.get_node("GalaxyMap")
	_check(map.get_node("%Chart").has_node("sys_earth") and not map.get_node("%Chart").has_node("sys_alpha"), "The global map conceals uncharted systems")
	_check(map.get_node("%Routes").get_child_count() == 0, "Unknown wormhole destinations are absent from the global route list")
	_check(map.get_node("%Jump").text == Text.get_text("ui_flight_launch"), "The map offers local flight instead of a direct jump")
	await _capture("unknown")
	_check(_travel("r_earth_alpha") == OK, "The map observes travel through a physical gate")
	_check("Топливо: 4" in map.get_node("%Routes/r_earth_alpha/Fuel").text, "The measured route appears after traversal")
	_check(map.get_node("%Chart").has_node("sys_alpha") and not map.get_node("%Chart").has_node("sys_far"), "Arrival reveals the actual destination only")
	await _capture("measured")
	map.get_node("%Chart/sys_earth").pressed.emit()
	_check(_travel("r_alpha_earth") == OK, "The reverse wormhole can be traversed independently")
	_check(GameState.state["current_system"] == "sys_earth" and not map.get_node("%Close").disabled, "Traversing the reverse route enables returning to the hub")
	_check(map.get_node("%Routes/r_alpha_earth").has_node("Sell"), "An unpublished measured route offers chart sale")
	map.get_node("%Routes/r_alpha_earth/Sell").pressed.emit()
	_check(not map.get_node("%Routes/r_alpha_earth").has_node("Sell") and "r_alpha_earth" in GameState.state["public_routes"], "Selling a route refreshes the chart's public status")
	EffectApplier.set_flight_target(Vector2(900, 660))
	EffectApplier.advance_flight(100.0)
	_check(EffectApplier.dock_at_hub() == OK, "Returning to the office requires docking near its planet")
	map.get_node("%Close").pressed.emit()
	await get_tree().process_frame
	_check(not hub.has_node("GalaxyMap") and GameState.state["location"] == "hub_office", "Closing the map restores the office interface")
	hub.queue_free()
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-galaxy" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "The galaxy view is rendered")
	_check(image.save_png("res://.godot/stage-five-" + suffix + ".png") == OK, "The galaxy screenshot is saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
