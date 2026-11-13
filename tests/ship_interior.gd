extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Router = preload("res://scripts/scene_router.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Text = preload("res://scripts/ui_text.gd")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "The new backgrounds and UI data validate")
	_check_rules()
	_check_autopilot()
	_check_encounters()
	await _check_scene_flow()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Ship interior checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	for npc: Dictionary in GameState.state["flight"]["npcs"].values():
		npc["cooldown"] = 10000.0


func _check_rules() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_check(EffectApplier.visit_ship() == ERR_UNAVAILABLE and EffectApplier.leave_ship() == ERR_UNAVAILABLE, "The building has no direct interior flight transition")
	for paused: bool in [false, true]:
		_launch()
		var pos: Vector2 = Motion.point(GameState.state["flight"]["pos"])
		EffectApplier.set_flight_target(pos + Vector2(400, 0))
		GameState.state["flight"]["paused"] = paused
		var exterior: Dictionary = GameState.serialize()
		_check(EffectApplier.visit_ship() == OK and Conditions.is_inside_ship() and not Conditions.can_fly(), "Entering the bridge changes the view using the existing boolean flags")
		_check(Router.current_path() == "res://scenes/hub.tscn" and not Conditions.can_tick_flight(), "The bridge routes to room navigation and stops the simulation")
		var interior: Dictionary = GameState.serialize()
		EffectApplier.advance_flight(30.0, true)
		_check(GameState.serialize() == interior, "Player, NPCs, fuel, hazards, time and autopilot remain frozen aboard")
		_check(EffectApplier.visit_ship() == ERR_UNAVAILABLE and EffectApplier.toggle_flight_pause() == ERR_UNAVAILABLE and EffectApplier.set_flight_target(pos) == ERR_UNAVAILABLE, "Repeated entry and exterior commands cannot modify a bridge visit")
		_check(not Conditions.can_use_galaxy_map() and not Conditions.domestic_available() and not Conditions.can_dock() and not Conditions.can_enter("hub_corridor"), "The bridge cannot reach building services or exterior travel actions")
		_check(GameState.save_game("user://bridge.json") == OK and GameState.load_game("user://bridge.json") == OK and GameState.serialize() == interior, "The bridge and its frozen flight round-trip exactly through JSON")
		_check(EffectApplier.leave_ship() == OK and GameState.serialize() == exterior, "Returning restores the previous running or manual-pause state exactly")
		_check(Router.current_path() == "res://scenes/system_flight.tscn", "Leaving routes back to the local flight map")
		EffectApplier.advance_flight(0.1)
		_check((GameState.state["flight"]["pos"] == exterior["flight"]["pos"]) == paused, "Only the previously running ship resumes movement")
	_launch()
	var old_save: Dictionary = GameState.serialize()
	_check(not old_save["flags"].has(GameState.SHIP_INTERIOR_FLAG) and GameState.restore(old_save) == OK and Conditions.can_fly(), "Existing saves without the interior flag still open the exterior")
	var invalid: Dictionary = old_save.duplicate(true)
	invalid["flags"][GameState.SHIP_INTERIOR_FLAG] = true
	invalid["location"] = "hub_corridor"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == old_save, "An inconsistent interior flag is rejected atomically")


func _check_autopilot() -> void:
	_launch()
	EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}])
	_check(EffectApplier.start_autopilot("sys_alpha") == OK, "The normal known-route action starts autopilot")
	var exterior: Dictionary = GameState.serialize()
	_check(EffectApplier.visit_ship() == OK, "A ship on autopilot can enter the bridge")
	var interior: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(30.0)
	_check(GameState.serialize() == interior and not GameState.state["flight"]["autopilot"].is_empty(), "A bridge visit freezes the active autopilot without cancelling its route")
	_check(EffectApplier.leave_ship() == OK and GameState.serialize() == exterior, "Leaving the bridge preserves the active route exactly")
	GameState.state["ship"]["fuel"]["current"] = 0.0
	_check(EffectApplier.visit_ship() == OK and EffectApplier.leave_ship() == OK, "Entering and leaving the bridge remain available without fuel")


func _check_encounters() -> void:
	_launch()
	var pirate: Dictionary = GameState.state["flight"]["npcs"]["npc_earth_pirate"]
	pirate["cooldown"] = 0.0
	GameState.state["flight"]["pos"] = pirate["pos"].duplicate()
	GameState.state["flight"]["target"] = pirate["pos"].duplicate()
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK, "A nearby pirate opens the normal encounter")
	var encounter: Dictionary = GameState.serialize()
	_check(EffectApplier.visit_ship() == ERR_UNAVAILABLE and GameState.serialize() == encounter, "The ship interior cannot bypass a pirate dialogue")
	_check(EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "The pirate can start a real combat")
	var combat: Dictionary = GameState.serialize()
	_check(EffectApplier.visit_ship() == ERR_UNAVAILABLE and GameState.serialize() == combat and Router.current_path() == "res://scenes/combat.tscn", "The ship interior cannot bypass combat")


func _check_scene_flow() -> void:
	get_tree().current_scene = null
	_check(get_tree().change_scene_to_file("res://scenes/boot.tscn") == OK, "The normal project entry point starts")
	var hub: Node = await _wait_scene("Hub")
	if hub == null:
		_check(false, "Boot reaches the building")
		return
	await _click(hub.get_node("%Locations/hub_corridor/Travel"))
	_check(GameState.state["location"] == "hub_corridor" and hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_corridor.png", "The corridor thumbnail opens the supplied image")
	for slot: String in ["day", "evening", "night"]:
		EffectApplier.apply_effects([{"advance_time": 1}])
		await _frames()
		_check(hub.get_node("%Background").material.get_shader_parameter("ambient") == DataLoader.get_record("hub_lighting")["slots"][slot]["ambient"], "The corridor uses the existing lighting profile for " + slot)
		await _capture("corridor-" + slot)
	var building_save: Dictionary = GameState.serialize()
	await _click(hub.get_node("%Locations/hub_tech/Travel"))
	await _click(hub.get_node("TechHotspot/Computer"))
	await _click(hub.get_node("%TerminalContent/ComputerMenu/Launch"))
	var flight: Node = await _wait_scene("SystemFlight")
	if flight == null:
		_check(false, "The workshop computer launches local flight")
		return
	flight.set_physics_process(false)
	EffectApplier.set_flight_target(Motion.point(GameState.state["flight"]["pos"]) + Vector2(300, 0))
	EffectApplier.toggle_flight_pause()
	var exterior: Dictionary = GameState.serialize()
	await _capture("flight")
	await _click(flight.get_node("%Ship"))
	hub = await _wait_scene("Hub")
	if hub == null:
		_check(false, "The ship button opens the real room scene")
		return
	_check(Conditions.is_inside_ship() and hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/ship_bridge.png", "The ship button opens the supplied bridge artwork")
	_check(hub.get_node("%Locations").get_child_count() == 1 and hub.get_node("%Locations").has_node("ship_bridge"), "Only the bridge is available in ship navigation")
	_check(hub.get_node("%People").has_node("security") and hub.get_node("%People").has_node("pilot"), "Existing crew placements populate the bridge")
	_check(hub.get_node("%LocationName").text == "Мостик" and hub.get_node("%Background").material.get_shader_parameter("ambient") == 1.0, "The bridge stays illuminated during the night slot")
	_check(hub.get_node("LocationPanel/Margin/Column/DomesticActions").get_child_count() == 1 and not hub.get_node("OfficeHotspot/Computer").is_visible_in_tree(), "The bridge exposes the return action and hides building-only services")
	var interior: Dictionary = GameState.serialize()
	for _frame: int in range(6):
		await get_tree().physics_frame
	_check(GameState.serialize() == interior, "The actual bridge scene does not advance flight physics")
	await _capture("bridge")
	await _click(hub.get_node("%People/security"))
	_check(hub.get_node("%Conversation").visible and hub._active_heroine_id == "security", "The crew button opens the existing conversation interface")
	await _capture("conversation")
	await _click(hub.get_node("%CloseDialogue"))
	_check(GameState.save_game("user://bridge-view.json") == OK, "The real bridge state can be saved")
	await _click(hub.get_node("LocationPanel/Margin/Column/DomesticActions/ReturnToFlight"))
	flight = await _wait_scene("SystemFlight")
	_check(flight != null and GameState.serialize() == exterior, "The return button restores the actual flight scene and manual pause")
	if flight == null:
		return
	_check(flight.get_node("%Ship").text == Text.get_text("ui_flight_visit_ship") and not flight.get_node("%Ship").disabled, "The returned map exposes the ship button again")
	_check(GameState.load_game("user://bridge-view.json") == OK, "A bridge save can be loaded from flight")
	hub = await _wait_scene("Hub")
	_check(hub != null and GameState.serialize() == interior, "Loading returns to the bridge with the exact frozen state")
	if hub != null:
		_check(GameState.restore(building_save) == OK, "A building save can be restored from the ship")
		await _frames()
		_check(hub.get_node("%Locations").get_child_count() == 10 and hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_corridor.png", "Restoring the building restores its separate corridor and room navigation")


func _wait_scene(scene_name: String) -> Node:
	for _frame: int in range(90):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == scene_name:
			return get_tree().current_scene
	return null


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-ship-interior" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/ship-interior-" + suffix + ".png") == OK, "The " + suffix + " view renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
