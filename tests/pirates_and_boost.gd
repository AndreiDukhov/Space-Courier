extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Geometry = preload("res://scripts/space_geometry.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "The expanded pirate data validates")
	_check_pirates()
	_check_saved_population()
	await _check_interaction()
	await _check_boost()
	_check_boost_hazard()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Pirates and boost checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	EffectApplier.apply_effects([{"flag": "signal_test_done", "set": true}])
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["role"] == "pirate":
			GameState.state["flight"]["npcs"][npc["id"]]["cooldown"] = 1000.0


func _position(pos: Vector2, target: Vector2) -> void:
	GameState.state["flight"]["pos"] = Motion.coordinates(pos)
	GameState.state["flight"]["target"] = Motion.coordinates(target)
	EffectApplier.flight_changed.emit()


func _check_pirates() -> void:
	var count: int = 0
	for system: Dictionary in DataLoader.get_records("systems"):
		var events: Array[String] = []
		for npc: Dictionary in DataLoader.get_records("npcs"):
			if npc["system"] != system["id"] or npc["role"] != "pirate":
				continue
			count += 1
			_check(str(npc["event"]) not in events, "Each pirate has a distinct encounter within " + str(system["id"]))
			events.append(str(npc["event"]))
			_launch()
			GameState.state["current_system"] = system["id"]
			GameState.state["systems"][system["id"]] = "visited"
			for other: Dictionary in DataLoader.get_records("npcs"):
				if other["id"] != npc["id"]:
					GameState.state["flight"]["defeated_npcs"].append(other["id"])
			var entry: Dictionary = GameState.state["flight"]["npcs"][npc["id"]]
			entry["cooldown"] = 0.0
			_position(Motion.point(entry["pos"]) + Vector2(100, 0), Motion.point(entry["pos"]) + Vector2(100, 0))
			EffectApplier.advance_flight(0.1)
			entry = GameState.state["flight"]["npcs"][npc["id"]]
			_check(entry["status"] == "chase" and entry["target"] == "player", str(npc["id"]) + " acquires the player inside its trigger radius")
			_check(GameState.state["flight"]["encounter"].is_empty(), "Detection starts pursuit before interception")
			_position(Motion.point(entry["pos"]) + Vector2(40, 0), Motion.point(entry["pos"]) + Vector2(40, 0))
			EffectApplier.advance_flight(0.1)
			_check(GameState.state["flight"]["encounter"] == npc["event"], "Reaching the player automatically opens the pirate's encounter")
			var intercepted: Dictionary = GameState.serialize()
			EffectApplier.advance_flight(1.0)
			_check(GameState.serialize() == intercepted, "An interception freezes movement until its choice is resolved")
			_check(EffectApplier.choose_flight_event(str(npc["event"]), 1) == OK, "An automatic encounter accepts the bribe")
			EffectApplier.advance_flight(0.1)
			_check(GameState.state["flight"]["encounter"].is_empty(), "The paid pirate cannot immediately intercept again")
			entry = GameState.state["flight"]["npcs"][npc["id"]]
			entry["status"] = "cruise"
			entry["target"] = ""
			entry["cooldown"] = 22.0
			_position(Motion.point(entry["pos"]) + Vector2(20, 0), Motion.point(entry["pos"]) + Vector2(20, 0))
			_check(not Conditions.can_pirate_target(npc, entry, "player", GameState.state["flight"]["npcs"]), "Aggression cooldown delays a new pursuit")
			_check(EffectApplier.pause_at_npc(str(npc["id"])) == OK and Conditions.can_contact_npc(str(npc["id"])), "Paused selection permits dialogue during the aggression cooldown")
			_check(EffectApplier.start_flight_event(str(npc["event"])) == OK and Conditions.encounter_npc(str(npc["event"])) == npc["id"], "The encounter belongs to the selected pirate")
			_check(EffectApplier.choose_flight_event(str(npc["event"]), 1) == OK and GameState.state["money"] == 600, "The selected pirate accepts a second explicitly chosen bribe")
			_check(Conditions.event_is_available(str(npc["event"])) and Conditions.can_contact_npc(str(npc["id"])), "A previous bribe keeps later manual interaction available")
		_check(events.size() == 3, "The system has three authored pirates")
	_check(count == 36, "The galaxy has thirty-six pirates")


func _check_saved_population() -> void:
	_launch()
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["cooldown"] = 9.5
	var legacy: Dictionary = GameState.serialize()
	for npc: Dictionary in DataLoader.files["res://data/npcs/pirates.json"]:
		legacy["flight"]["npcs"].erase(npc["id"])
	_check(legacy["flight"]["npcs"].size() == 91 and GameState.restore(legacy) == OK, "A pre-expansion save gains the new population")
	_check(GameState.state["flight"]["npcs"].size() == 115, "Every new pirate has saved runtime state")
	for npc_id: String in legacy["flight"]["npcs"]:
		_check(GameState.state["flight"]["npcs"][npc_id] == legacy["flight"]["npcs"][npc_id], "Existing ship state survives migration for " + npc_id)
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://pirate-population.json") == OK and GameState.load_game("user://pirate-population.json") == OK and GameState.serialize() == snapshot, "The expanded population round-trips with stable equipment and cooldowns")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["flight"]["npcs"].erase("npc_earth_courier")
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "The expansion still rejects a missing original NPC")
	invalid = snapshot.duplicate(true)
	invalid["flight"]["npcs"]["npc_beta_raider_2"]["cooldown"] = -1
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid saved pirate data is rejected instead of replaced")
	invalid = legacy.duplicate(true)
	invalid["flight"]["npcs"]["npc_earth_courier"] = "invalid"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Population migration safely rejects a malformed old NPC entry")


func _check_interaction() -> void:
	_launch()
	GameState.state["current_system"] = "sys_beta"
	GameState.state["systems"]["sys_beta"] = "visited"
	var npc_id: String = "npc_beta_raider_2"
	GameState.state["flight"]["npcs"][npc_id]["pos"] = [300.0, 1800.0]
	GameState.state["flight"]["npcs"][npc_id]["cooldown"] = 22.0
	GameState.state["flight"]["npcs"]["npc_beta_pirate"]["pos"] = [320.0, 1800.0]
	_position(Vector2(330, 1800), Vector2(330, 1800))
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	var point: Vector2 = view.camera.unproject_position(Motion.world_position(GameState.state["flight"]["npcs"][npc_id]["pos"], 2.8))
	await _click_at(view.get_node("%SpaceContainer").global_position + point)
	var button: Button = view.find_child("ObjectInteractions", true, false).get_node(npc_id + "/Dialogue")
	_check(GameState.state["flight"]["paused"] and button.is_visible_in_tree() and not button.disabled, "A real click exposes usable pirate dialogue while its aggression cooldown is running")
	await _click(button)
	_check(view.get_node("%EncounterLayer").visible and GameState.state["flight"]["encounter"] == DataLoader.get_record(npc_id)["event"], "The overhead button opens the correct pirate encounter")
	await _capture("pirate-dialogue")
	await _click(view.get_node("%FlightEncounter/%EventChoices/Option0"))
	_check(Conditions.has_combat() and GameState.state["combat"]["source_npc"] == npc_id, "Combat uses the selected pirate even when another pirate is closer")
	view.queue_free()
	await _frames()


func _check_boost() -> void:
	_launch()
	_position(Vector2(300, 2100), Vector2(1200, 2100))
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	view._physics_process(1.0)
	var normal_distance: float = Motion.point(GameState.state["flight"]["pos"]).x - 300.0
	var normal_cost: float = 30.0 - float(GameState.state["ship"]["fuel"]["current"])
	_position(Vector2(300, 2100), Vector2(1200, 2100))
	GameState.state["ship"]["fuel"]["current"] = 30.0
	await _click(view.get_node("%Boost"))
	view._physics_process(1.0)
	_check(is_equal_approx(normal_distance, 150.0) and is_equal_approx(Motion.point(GameState.state["flight"]["pos"]).x - 300.0, normal_distance * 2.0), "The actual flight toolbar doubles local movement speed")
	var boost_cost: float = 30.0 - float(GameState.state["ship"]["fuel"]["current"])
	_check(absf(boost_cost - normal_cost * 3.0) < 0.00001, "Double-speed flight spends fifty percent more fuel per distance")
	await _capture("boost")
	EffectApplier.toggle_flight_pause()
	var snapshot: Dictionary = GameState.serialize()
	view._physics_process(1.0)
	_check(GameState.serialize() == snapshot, "A paused boosted flight preserves movement and fuel")
	EffectApplier.toggle_flight_pause()
	GameState.state["ship"]["fuel"]["current"] = 0.001
	_position(Vector2(300, 2100), Vector2(1200, 2100))
	view._physics_process(1.0)
	_check(float(GameState.state["ship"]["fuel"]["current"]) == 0.0 and absf(Motion.point(GameState.state["flight"]["pos"]).x - 306.0) < 0.001, "Boost stops at its fuel-limited distance without overdrawing")
	snapshot = GameState.serialize()
	view._physics_process(1.0)
	_check(GameState.state["flight"]["pos"] == snapshot["flight"]["pos"], "An empty tank cannot move under boost")
	GameState.state["ship"]["fuel"]["current"] = 30.0
	_position(Vector2(300, 2100), Vector2(300, 2100))
	EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}])
	_check(EffectApplier.start_autopilot("sys_alpha") == OK, "A known route can start while boost is selected")
	view._physics_process(0.1)
	_check(absf(Motion.point(GameState.state["flight"]["pos"]).distance_to(Vector2(300, 2100)) - 30.0) < 0.001, "Autopilot uses the selected boost for local movement")
	view.queue_free()
	await _frames()


func _check_boost_hazard() -> void:
	var damage: Array[float] = []
	for boost: bool in [false, true]:
		_launch()
		var star: Dictionary = Geometry.star("sys_earth")
		var span: Vector2 = Vector2(float(star["hazard"]["radius"]) + 90.0, 0)
		_position(Motion.point(star["pos"]) - span, Motion.point(star["pos"]) + span)
		EffectApplier.advance_flight(10.0, boost)
		damage.append(100.0 - float(GameState.state["ship"]["hull"]["current"]))
	_check(damage[0] > 0.0 and absf(damage[0] - damage[1] * 2.0) < 0.01, "Star damage uses the actual time spent crossing at each speed")


func _click(button: Button) -> void:
	await _frames()
	await _click_at(button.get_global_rect().get_center())


func _click_at(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-pirates-boost" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/" + suffix + ".png") == OK, "The " + suffix + " interface renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
