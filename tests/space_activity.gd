extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Geometry = preload("res://scripts/space_geometry.gd")
const Validator = preload("res://scripts/data_validator.gd")
const Traffic = preload("res://scripts/traffic_state.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")

var failures: Array[String] = []
var check_count: int = 0
var effects: Array[String] = []


func _ready() -> void:
	EffectApplier.space_effect.connect(func(kind: String, _position: Vector2, _npc: String) -> void: effects.append(kind))
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Space content loads with valid references")
	_check_content()
	_check_traffic()
	_check_piracy()
	_check_navigation()
	_check_hazards()
	_check_planets()
	_check_saves()
	await _check_ui()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Space activity checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch(quiet: bool = true) -> void:
	seed(725)
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true})
	if quiet:
		for npc: Dictionary in DataLoader.get_records("npcs"):
			if npc["role"] == "pirate":
				GameState.state["flight"]["npcs"][npc["id"]]["cooldown"] = 1000.0
	effects.clear()


func _place(position: Vector2) -> void:
	GameState.state["flight"]["pos"] = Motion.coordinates(position * Motion.MAP_SCALE)
	GameState.state["flight"]["target"] = Motion.coordinates(position * Motion.MAP_SCALE)


func _check_content() -> void:
	_launch()
	_check(DataLoader.get_records("systems").size() == 12, "The galaxy has twelve authored systems")
	for system: Dictionary in DataLoader.get_records("systems"):
		_check(Traffic.planets(str(system["id"])).size() >= 2, "Each system has inhabited destinations")
		var roles: Array[String] = []
		for npc: Dictionary in DataLoader.get_records("npcs"):
			if npc["system"] == system["id"] and str(npc["role"]) not in roles:
				roles.append(str(npc["role"]))
		_check(roles.has("civilian") and roles.has("patrol") and roles.has("pirate"), "Each system has civilian traffic, patrol and pirates")
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["systems"][0]["objects"][0]["shop"] = "missing_shop"
	_check("missing_shop" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Planet shop ids are validated")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["systems"][0]["objects"][0]["dialogue"] = "missing_dialogue"
	_check("missing_dialogue" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Planet dialogue ids are validated")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["systems"][0]["traffic"]["spawn_delay"] = [10, -1]
	_check(not Validator.validate(groups, DataLoader.record_sources).is_empty(), "Invalid traffic timing is rejected")


func _check_traffic() -> void:
	_launch()
	_place(Vector2(50, 710))
	var distant: Dictionary = GameState.state["flight"]["npcs"]["npc_alpha_courier"].duplicate(true)
	EffectApplier.advance_flight(150.0)
	_check(effects.has("takeoff") and effects.has("landing"), "The simulation produces both departures and arrivals")
	var takeoffs: int = effects.count("takeoff")
	var landings: int = effects.count("landing")
	_check(absi(takeoffs - landings) <= 5, "Traffic stays approximately balanced without alternating rigidly")
	_check(GameState.state["flight"]["npcs"]["npc_alpha_courier"] == distant, "Unloaded systems retain their saved traffic state")
	_check(GameState.save_game("user://traffic.json") == OK, "Live traffic can be saved")
	var npc: Dictionary = GameState.state["flight"]["npcs"]["npc_earth_courier"]
	npc["status"] = "landing"
	npc["destination"] = "earth_1"
	npc["pos"] = [901.0, 660.0]
	EffectApplier.advance_flight(0.1)
	_check(GameState.state["flight"]["npcs"]["npc_earth_courier"]["status"] == "landed", "The landing transition is processed")
	_check(not Conditions.npc_is_active("npc_earth_courier"), "Landed ships disappear from flight interaction")
	var before: Dictionary = GameState.serialize()
	EffectApplier.toggle_flight_pause()
	before = GameState.serialize()
	EffectApplier.advance_flight(20)
	_check(GameState.serialize() == before, "Pause freezes all traffic and pursuit timers")


func _check_piracy() -> void:
	_launch(false)
	_place(Vector2(800, 400))
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["pos"] = Motion.coordinates(Motion.point(GameState.state["flight"]["pos"]) - Vector2(0, 160))
	var pirate: Dictionary = DataLoader.get_record("npc_earth_pirate")
	var entries: Dictionary = GameState.state["flight"]["npcs"]
	var patrol: Dictionary = entries["npc_earth_patrol"]
	patrol["pos"] = Motion.coordinates(Motion.point(entries[pirate["id"]]["pos"]) + Vector2(5, 5))
	_check(not Conditions.can_pirate_target(pirate, entries[pirate["id"]], "npc_earth_patrol", entries), "Pirates never choose patrol ships as robbery victims")
	EffectApplier.advance_flight(0.1)
	var entry: Dictionary = GameState.state["flight"]["npcs"][pirate["id"]]
	_check(entry["status"] == "chase" and entry["target"] == "player", "Entering the trigger zone starts player pursuit")
	_check(Motion.point(entry["pos"]).distance_to(Motion.point(GameState.state["flight"]["pos"])) < 160, "The pirate moves toward its target")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://pursuit.json") == OK and GameState.load_game("user://pursuit.json") == OK and GameState.serialize() == snapshot, "Pursuit and its target survive exact JSON round trips")
	_place(Vector2(30, 710))
	EffectApplier.advance_flight(0.1)
	entry = GameState.state["flight"]["npcs"][pirate["id"]]
	_check(entry["status"] == "cruise" and entry["target"] == "" and float(entry["cooldown"]) > 0, "Leaving the lose radius ends pursuit and starts cooldown")
	_launch(false)
	_place(Vector2(800, 400))
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["pos"] = Motion.coordinates(Motion.point(GameState.state["flight"]["pos"]) - Vector2(0, 160))
	EffectApplier.advance_flight(2.0)
	_check(GameState.state["flight"]["encounter"] == "event_pirate_test" and not Conditions.can_tick_flight(), "A pursuing pirate automatically opens its encounter when it reaches the player")
	_check(EffectApplier.choose_flight_event("event_pirate_test", 1) == OK and GameState.state["money"] == 800 and GameState.state["flight"]["npcs"]["npc_earth_pirate"]["target"] == "", "Paying the player bribe releases pursuit and charges once")
	for destroyed: bool in [true, false]:
		_launch(false)
		_place(Vector2(30, 710))
		var saved_chance: float = float(DataLoader.records["npc_earth_pirate"]["piracy"]["destroy_chance"])
		DataLoader.records["npc_earth_pirate"]["piracy"]["destroy_chance"] = 1.0 if destroyed else 0.0
		entries = GameState.state["flight"]["npcs"]
		entries["npc_earth_courier"]["pos"] = Motion.coordinates(Motion.point(entries["npc_earth_pirate"]["pos"]) + Vector2(7, 10))
		entries["npc_earth_courier"]["timer"] = 100.0
		EffectApplier.advance_flight(3.5)
		_check(effects.has("destroyed" if destroyed else "paid"), "A caught civilian resolves the authored robbery outcome")
		_check(Conditions.npc_is_active("npc_earth_courier") != destroyed, "Only destroyed robbery victims disappear")
		_check(GameState.state["flight"]["npcs"]["npc_earth_pirate"]["target"] == "", "The pirate releases its victim after resolving robbery")
		DataLoader.records["npc_earth_pirate"]["piracy"]["destroy_chance"] = saved_chance


func _check_navigation() -> void:
	_launch()
	_check(EffectApplier.start_autopilot("sys_alpha") == ERR_UNAVAILABLE, "Unknown wormholes cannot be used by autopilot")
	GameState.state["systems"]["sys_alpha"] = "seen"
	_check(EffectApplier.start_autopilot("sys_alpha") == ERR_UNAVAILABLE, "Knowing a system alone does not disclose a usable wormhole")
	EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}, {"unlock_route": "r_alpha_colony"}])
	_check(EffectApplier.start_autopilot("sys_colony_3") == OK, "A known directed chain can be selected for automatic flight")
	_check(GameState.state["current_system"] == "sys_earth" and not GameState.state["flight"]["autopilot"].is_empty(), "Starting autopilot moves locally before changing systems")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://autopilot.json") == OK and GameState.load_game("user://autopilot.json") == OK and GameState.serialize() == snapshot, "An active multi-hop route is saved exactly")
	for _second: int in range(45):
		if GameState.state["flight"]["paused"]:
			_check(not GameState.state["flight"]["autopilot"].is_empty(), "Proximity pauses retain the automatic route until dialogue or trade is chosen")
			EffectApplier.toggle_flight_pause()
		EffectApplier.advance_flight(1.0)
	_check(GameState.state["current_system"] == "sys_colony_3" and GameState.state["flight"]["autopilot"].is_empty(), "Autopilot flies to gates and completes both directed jumps")
	_check(Clock.current_day() == 3 and float(GameState.state["ship"]["fuel"]["current"]) < 19.0, "Automatic travel pays jump fuel, local fuel and travel days")
	_launch()
	EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}])
	EffectApplier.start_autopilot("sys_alpha")
	_check(EffectApplier.set_flight_target(Vector2(50, 700)) == OK and GameState.state["flight"]["autopilot"].is_empty(), "Manual steering cancels autopilot")
	GameState.state["ship"]["fuel"]["current"] = 1.0
	_check(EffectApplier.start_autopilot("sys_alpha") == ERR_UNAVAILABLE, "Insufficient jump fuel cannot start an automatic route")
	_launch(false)
	EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}])
	_place(Vector2(700, 350))
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["pos"] = Motion.coordinates(Motion.point(GameState.state["flight"]["pos"]) + Vector2(150, 0))
	EffectApplier.start_autopilot("sys_alpha")
	EffectApplier.advance_flight(0.1)
	_check(GameState.state["flight"]["autopilot"].is_empty() and GameState.state["flight"]["npcs"]["npc_earth_pirate"]["target"] == "player", "A newly acquired pirate pursuit interrupts automatic flight")
	var position: Vector2 = Vector2(300, 380) * Motion.MAP_SCALE
	var safe: bool = true
	for _i: int in range(150):
		position = Motion.advance(position, Geometry.safe_target(position, (Vector2(750, 380) * Motion.MAP_SCALE), "sys_earth"), 150, 0.1)
		safe = safe and not Conditions.star_is_dangerous(position)
	_check(safe, "Every step of automatic local navigation avoids stellar radiation")
	_check(position.distance_to((Vector2(750, 380) * Motion.MAP_SCALE)) < 2.0, "The safe detour reaches a target on the opposite side of a star")


func _check_hazards() -> void:
	_launch()
	_place(Vector2(500, 380))
	EffectApplier.advance_flight(1.0)
	_check(is_equal_approx(float(GameState.state["ship"]["hull"]["current"]), 92.0), "A stationary ship takes configured damage per second near the star")
	_check(effects.has("star_damage"), "Star damage emits a visible damage event")
	EffectApplier.toggle_flight_pause()
	var snapshot: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(2)
	_check(GameState.serialize() == snapshot, "Paused flight takes no stellar damage")
	_check(GameState.save_game("user://burn.json") == OK and GameState.load_game("user://burn.json") == OK and GameState.serialize() == snapshot, "Fractional hull damage survives save and load")
	EffectApplier.toggle_flight_pause()
	GameState.state["ship"]["hull"]["current"] = 0.4
	EffectApplier.advance_flight(0.1)
	_check(GameState.state["location"] == "hub_office" and GameState.state["money"] == 600 and Clock.current_day() == 2 and GameState.state["ship"]["hull"]["current"] == 100, "Fatal star damage invokes the existing paid tow without a soft lock")
	_launch()
	_place(Vector2(300, 380))
	EffectApplier.set_flight_target((Vector2(750, 380) * Motion.MAP_SCALE))
	EffectApplier.advance_flight(10.0)
	_check(float(GameState.state["ship"]["hull"]["current"]) < 100, "A fast pass through the star cannot tunnel past its damage zone")


func _check_planets() -> void:
	_launch()
	_place(Vector2(50, 710))
	GameState.state["ship"]["fuel"]["current"] = 25.5
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.buy_planet_fuel("earth_1", 1.0) == ERR_UNAVAILABLE and not Conditions.can_refuel() and not Conditions.can_buy_item("planet_market_test", "carrot"), "Remote planet services are inaccessible")
	_check(GameState.serialize() == snapshot, "Rejected remote services cannot change resources")
	_place(Vector2(300, 220))
	_check(EffectApplier.buy_planet_fuel("earth_1", 1.0) == OK and GameState.state["money"] == 980 and GameState.state["ship"]["fuel"]["current"] == 26.5, "Nearby fuel purchases charge the system price")
	_check(EffectApplier.buy_planet_fuel("earth_1", 3.5) == OK and GameState.state["money"] == 910 and GameState.state["ship"]["fuel"]["current"] == 30.0, "A fractional full top-up is priced and capped correctly")
	_check(EffectApplier.buy_planet_fuel("earth_1", 1.0) == ERR_UNAVAILABLE and EffectApplier.buy_planet_fuel("earth_1", NAN) == ERR_UNAVAILABLE, "Invalid and excess fuel purchases are rejected")
	_check(EffectApplier.buy_item("planet_market_test", "carrot") == OK and GameState.state["inventory"] == [{"item": "carrot", "count": 1}] and OrderManager.active_mass() == 0.0, "Planet food enters the player inventory without cargo mass")
	_check(not Conditions.can_prepare_ingredient("recipe_carrot_01", "carrot", "cut"), "Food bought in space cannot be prepared outside the hub kitchen")
	_place(Vector2(720, 640))
	_check(not Conditions.can_interact_planet("earth_3"), "An uninhabited planet offers no trade or dialogue")
	_launch()
	GameState.state["location"] = "hub_office"
	_check(EffectApplier.accept_order("ord_slice_test") == OK, "The delivery fixture accepts its regular order")
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	_place(Vector2(300, 220))
	_check(EffectApplier.deliver_order("ord_slice_test") == ERR_UNAVAILABLE, "A different planet cannot accept the delivery")
	_place(Vector2(650, 400))
	_check(EffectApplier.deliver_order("ord_slice_test") == OK and GameState.state["money"] == 1250 and OrderManager.active_mass() == 0.0, "The destination accepts cargo and applies its JSON reward")
	_check(EffectApplier.deliver_order("ord_slice_test") == ERR_UNAVAILABLE and GameState.state["money"] == 1250, "Repeated hand-in cannot duplicate rewards")


func _check_saves() -> void:
	_launch()
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://space.json") == OK and GameState.load_game("user://space.json") == OK and GameState.serialize() == snapshot, "The expanded state survives exact JSON serialization")
	for key: String in ["status", "destination", "target", "timer", "cooldown"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["flight"]["npcs"]["npc_earth_courier"][key] = "missing" if key in ["status", "destination", "target"] else -1
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid NPC " + key + " is rejected atomically")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy["flight"].erase("autopilot")
	legacy["flight"].erase("map_scale")
	for field: String in ["pos", "target"]:
		legacy["flight"][field] = Motion.coordinates(Motion.point(legacy["flight"][field]) / Motion.MAP_SCALE)
	var previous_npcs: Array[String] = ["npc_earth_courier", "npc_earth_transport", "npc_earth_pirate", "npc_alpha_courier", "npc_beta_courier", "npc_colony_courier", "npc_delta_courier", "npc_far_courier"]
	for npc_id: String in legacy["flight"]["npcs"].keys():
		if npc_id not in previous_npcs:
			legacy["flight"]["npcs"].erase(npc_id)
	for entry: Dictionary in legacy["flight"]["npcs"].values():
		entry["pos"] = Motion.coordinates(Motion.point(entry["pos"]) / Motion.MAP_SCALE)
		for key: String in Traffic.FIELDS:
			entry.erase(key)
	for system_id: String in legacy["systems"].keys():
		if system_id in ["sys_gamma", "sys_epsilon", "sys_zeta", "sys_orion", "sys_vega", "sys_frontier"]:
			legacy["systems"].erase(system_id)
	_check(GameState.restore(legacy) == OK and GameState.state["systems"]["sys_gamma"] == "hidden" and GameState.state["flight"]["autopilot"].is_empty(), "The previous flight format gains traffic and hidden systems")


func _check_ui() -> void:
	_launch()
	GameState.state["location"] = "hub_office"
	EffectApplier.accept_order("ord_slice_test")
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay: Control = view.find_child("ObjectInteractions", true, false)
	_check(not overlay.get_node("earth_2").visible and not overlay.get_node("r_earth_alpha").visible, "Object actions stay hidden outside interaction range")
	_place(Vector2(650, 400))
	EffectApplier.flight_changed.emit()
	await get_tree().process_frame
	_check(overlay.get_node("earth_2/Trade").visible and overlay.get_node("earth_2/Dialogue").visible, "An inhabited planet shows exactly its trade and dialogue actions")
	_check(overlay.get_node("earth_2").get_child_count() == 3 and overlay.get_node("earth_2").has_node("Deliver_ord_slice_test") and overlay.get_node("r_earth_alpha").get_child_count() == 1, "Wormholes offer Enter and a delivery planet adds its direct hand-in action")
	await _capture("planet")
	await _click(overlay.get_node("earth_2/Dialogue"))
	var panel: Control = view.get_node_or_null("PlanetPanel")
	_check(panel != null, "A real click on the projected planet button opens dialogue")
	if panel != null:
		var deliver: Button = panel.find_child("Deliver_ord_slice_test", true, false)
		_check(deliver != null and not deliver.disabled, "The planet dialogue contains the eligible quest hand-in")
		await _capture("quests")
		await _click(deliver)
		_check(OrderManager.status("ord_slice_test") == "completed" and GameState.state["money"] == 1250, "The actual dialogue button awards the completed delivery")
		await _click(panel.find_child("Close", true, false))
	await _click(overlay.get_node("earth_2/Trade"))
	panel = view.get_node_or_null("PlanetPanel")
	_check(panel != null and panel.find_child("FuelOne", true, false) != null, "The trade action opens fuel and inventory stock")
	if panel != null:
		GameState.state["ship"]["fuel"]["current"] = 28.5
		panel.refresh()
		await get_tree().process_frame
		await _capture("trade")
		await _click(panel.find_child("FuelFull", true, false))
		_check(GameState.state["ship"]["fuel"]["current"] == 30 and GameState.state["money"] == 1220, "The visible full-tank button charges the fractional deficit")
		await _click(panel.find_child("Buy_carrot", true, false))
		_check(not GameState.state["inventory"].is_empty(), "The visible buy button gives the player ingredients")
		await _click(panel.find_child("Close", true, false))
	_place(Vector2(930, 150))
	EffectApplier.flight_changed.emit()
	await get_tree().process_frame
	_check(overlay.get_node("r_earth_alpha/Enter").visible and not overlay.get_node("r_earth_alpha/Enter").disabled, "The unknown gate offers Enter only after approach")
	await _capture("gate")
	await _click(overlay.get_node("r_earth_alpha/Enter"))
	_check(GameState.state["current_system"] == "sys_alpha", "The overhead Enter action performs the authored jump")
	view.open_map()
	await get_tree().process_frame
	var chart: Control = view.find_child("Chart", true, false)
	_check(chart != null and chart.has_node("sys_earth") and chart.has_node("sys_alpha"), "The map shows known systems after exploration")
	EffectApplier.apply_effects([{"unlock_route": "r_alpha_earth"}])
	await get_tree().process_frame
	await _click(chart.get_node("sys_earth"))
	_check(view._map == null and GameState.state["flight"]["autopilot"].get("destination") == "sys_earth", "Clicking a known map destination starts local automatic travel")
	EffectApplier.stop_autopilot()
	_place(Vector2(500, 380))
	EffectApplier.advance_flight(0.1)
	await get_tree().process_frame
	_check(view._flash.color.a > 0 and not view._status.text.is_empty(), "Stellar damage lights the screen and shows an explicit warning")
	await _capture("hazard")
	for system: Dictionary in DataLoader.get_records("systems"):
		GameState.state["systems"][system["id"]] = "visited"
	for route: Dictionary in DataLoader.get_records("routes"):
		EffectApplier.apply_effects([{"unlock_route": route["id"]}])
	view.open_map()
	await get_tree().process_frame
	await _capture("galaxy")
	view.queue_free()
	await get_tree().process_frame


func _click(button: Button) -> void:
	if button == null:
		_check(false, "The requested UI button exists")
		return
	await get_tree().process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-space" not in OS.get_cmdline_user_args():
		return
	if "--small-space" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/space-" + suffix + ".png") == OK, "The " + suffix + " view renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
