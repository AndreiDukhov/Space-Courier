extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Patrol = preload("res://scripts/npc_motion.gd")
const Validator = preload("res://scripts/data_validator.gd")
const SAVE_PATH: String = "res://.godot/stage-six-npc-save.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "NPC and event content loads without errors")
	_check_patrols()
	_check_simulation()
	_check_events()
	_check_persistence()
	_check_validation()
	await _check_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 6 NPC checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["role"] == "pirate":
			GameState.state["flight"]["npcs"][npc["id"]]["cooldown"] = 10000.0
	_check(EffectApplier.move_player("hub_tech") == OK and EffectApplier.launch_flight() == OK, "The NPC test starts in local flight")


func _chase(npc_id: String) -> void:
	for _step: int in range(120):
		if not GameState.state["flight"]["encounter"].is_empty():
			return
		if Conditions.can_interact_npc(npc_id):
			return
		if GameState.state["flight"]["paused"]:
			if Conditions.can_interact_npc(npc_id):
				return
			EffectApplier.toggle_flight_pause()
		EffectApplier.set_flight_target(Motion.point(GameState.state["flight"]["npcs"][npc_id]["pos"]))
		EffectApplier.advance_flight(0.1)


func _marker() -> void:
	EffectApplier.set_flight_target(Vector2(780, 1650))
	EffectApplier.advance_flight(10.0)


func _check_patrols() -> void:
	var points: Array = [[100, 0], [100, 100], [0, 100], [0, 0]]
	var result: Dictionary = Patrol.advance(Vector2.ZERO, 0, points, 50.0, 1.0)
	_check(Motion.point(result["pos"]) == Vector2(50, 0) and result["waypoint"] == 0, "Patrol motion uses the NPC's own speed")
	result = Patrol.advance(Vector2.ZERO, 0, points, 50.0, 3.0)
	_check(Motion.point(result["pos"]) == Vector2(100, 50) and result["waypoint"] == 1, "Patrol motion carries remaining distance around a corner")
	result = Patrol.advance(Vector2.ZERO, 0, points, 50.0, 83.0)
	_check(Motion.point(result["pos"]) == Vector2(100, 50) and result["waypoint"] == 1, "Large frame steps can cross many complete patrol loops")
	var segmented: Dictionary = {"pos": [0.0, 0.0], "waypoint": 0}
	for _step: int in range(30):
		segmented = Patrol.advance(Motion.point(segmented["pos"]), int(segmented["waypoint"]), points, 50.0, 0.1)
	_check(segmented == Patrol.advance(Vector2.ZERO, 0, points, 50.0, 3.0), "Patrol outcomes do not depend on frame segmentation")
	for system: Dictionary in DataLoader.get_records("systems"):
		var count: int = 0
		for npc: Dictionary in DataLoader.get_records("npcs"):
			if npc["system"] == system["id"]:
				count += 1
		_check(count > 0, "Every system has an NPC ship")


func _check_simulation() -> void:
	_launch()
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.approach_npc("npc_alpha_courier") == ERR_UNAVAILABLE and EffectApplier.approach_npc("missing") == ERR_UNAVAILABLE and GameState.serialize() == before, "Approach commands reject missing ships and ships in other systems")
	EffectApplier.set_flight_target(Motion.SPAWN + Vector2(100, 0))
	EffectApplier.advance_flight(0.5)
	_check(GameState.state["flight"]["pos"] != before["flight"]["pos"] and GameState.state["flight"]["npcs"]["npc_earth_courier"]["pos"] != before["flight"]["npcs"]["npc_earth_courier"]["pos"], "Player and current-system NPCs move during the same real-time step")
	_check(GameState.state["flight"]["npcs"]["npc_alpha_courier"] == before["flight"]["npcs"]["npc_alpha_courier"], "Ships in unloaded systems retain their stored positions")
	EffectApplier.toggle_flight_pause()
	before = GameState.serialize()
	EffectApplier.advance_flight(5.0)
	_check(GameState.serialize() == before, "Pause freezes both player and all local NPC ships")
	EffectApplier.toggle_flight_pause()
	GameState.state["ship"]["fuel"]["current"] = 0.0
	before = GameState.serialize()
	EffectApplier.advance_flight(0.5)
	_check(GameState.state["flight"]["pos"] == before["flight"]["pos"] and GameState.state["flight"]["npcs"]["npc_earth_courier"] != before["flight"]["npcs"]["npc_earth_courier"], "NPCs continue moving when the player has no fuel")
	_check(GameState.state["ship"]["fuel"]["current"] == 0.0, "NPC movement never consumes the player's fuel")
	_launch()
	for _leg: int in range(30):
		if GameState.state["flight"]["paused"]:
			EffectApplier.toggle_flight_pause()
		EffectApplier.set_flight_target(Vector2(2790, 450))
		EffectApplier.advance_flight(1.0)
		if Conditions.is_near([2790, 450]):
			break
	var patrols: Dictionary = GameState.state["flight"]["npcs"].duplicate(true)
	_check(EffectApplier.jump_route("r_earth_alpha") == OK and GameState.state["flight"]["npcs"] == patrols, "Jumping preserves every NPC's stored patrol progress")
	EffectApplier.advance_flight(0.5)
	_check(GameState.state["flight"]["npcs"]["npc_earth_courier"] == patrols["npc_earth_courier"] and GameState.state["flight"]["npcs"]["npc_alpha_courier"] != patrols["npc_alpha_courier"], "Arrival activates only the destination system's NPCs")


func _check_events() -> void:
	_launch()
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.start_flight_event("event_courier_test") == ERR_UNAVAILABLE and GameState.serialize() == before, "Remote contact cannot open a ship encounter")
	_check(EffectApplier.start_flight_event("event_signal_test") == ERR_UNAVAILABLE and GameState.serialize() == before, "A distant marker cannot open an event")
	_marker()
	_check(GameState.state["flight"]["encounter"] == "event_signal_test", "Approaching a marker automatically opens its linked event")
	_check(GameState.state["money"] == 1000 and not GameState.state["flags"].get("signal_test_done", false), "Starting an event applies no option rewards")
	before = GameState.serialize()
	EffectApplier.advance_flight(10.0)
	_check(GameState.serialize() == before, "An active encounter freezes both player and NPC simulation")
	_check(EffectApplier.set_flight_target(Vector2.ZERO) == ERR_UNAVAILABLE and EffectApplier.toggle_flight_pause() == ERR_UNAVAILABLE and not Conditions.can_open_flight_map(), "An active encounter blocks flight, pause changes and map access")
	_check(EffectApplier.choose_flight_event("event_signal_test", 99) == ERR_UNAVAILABLE and GameState.serialize() == before, "An invalid choice cannot alter the active event")
	var original: Array = DataLoader.records["event_signal_test"]["options"][0]["effects"].duplicate(true)
	DataLoader.records["event_signal_test"]["options"][0]["effects"] = [{"money": 100}, {"stat": "missing.mood", "add": 1}]
	_check(EffectApplier.choose_flight_event("event_signal_test", 0) == ERR_INVALID_DATA and GameState.serialize() == before, "Invalid consequences preserve the event and cannot partially pay out")
	DataLoader.records["event_signal_test"]["options"][0]["effects"] = original
	_check(EffectApplier.choose_flight_event("event_signal_test", 0) == OK and GameState.state["money"] == 1050 and GameState.state["flight"]["encounter"].is_empty(), "A marker choice applies its effects and resumes flight")
	before = GameState.serialize()
	_check(EffectApplier.choose_flight_event("event_signal_test", 0) == ERR_UNAVAILABLE and GameState.serialize() == before, "Repeated choice delivery cannot duplicate a reward")
	_check(not Conditions.event_is_available("event_signal_test") and EffectApplier.start_flight_event("event_signal_test") == ERR_UNAVAILABLE, "JSON conditions prevent reopening a completed test event")
	_launch()
	_chase("npc_earth_courier")
	_check(not GameState.state["flight"]["paused"] and GameState.state["flight"]["encounter"].is_empty() and EffectApplier.pause_at_npc("npc_earth_courier") == OK and EffectApplier.start_flight_event("event_courier_test") == OK, "Closing with a moving NPC requires an explicit selection to pause and talk")
	_check(EffectApplier.choose_flight_event("event_courier_test", 0) == OK and GameState.state["money"] == 1025, "A ship encounter uses the shared consequence system")
	_launch()
	_chase("npc_earth_transport")
	var fuel_before: float = float(GameState.state["ship"]["fuel"]["current"])
	_check(EffectApplier.start_flight_event("event_transport_test") == OK and EffectApplier.choose_flight_event("event_transport_test", 1) == OK, "The second NPC can present a different test event")
	_check(is_equal_approx(float(GameState.state["ship"]["fuel"]["current"]), fuel_before - 0.25) and GameState.state["heroines"]["pilot"]["attitude"] == 22.0, "Option effects and action tags use the central fuel and crew rules")
	_launch()
	DataLoader.records["event_signal_test"]["chance"] = 0
	_marker()
	_check(GameState.state["flight"]["encounter"].is_empty(), "An event with zero chance does not start on approach")
	DataLoader.records["event_signal_test"]["chance"] = 1
	EffectApplier.advance_flight(1.0)
	_check(GameState.state["flight"]["encounter"].is_empty(), "A failed approach roll is not repeated every physics frame")
	EffectApplier.set_flight_target(Motion.SPAWN)
	EffectApplier.advance_flight(10.0)
	_marker()
	_check(GameState.state["flight"]["encounter"] == "event_signal_test", "Leaving and approaching again permits a new event roll")


func _check_persistence() -> void:
	_launch()
	_marker()
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "An active encounter and NPC patrols can be saved")
	EffectApplier.choose_flight_event("event_signal_test", 0)
	_check(GameState.load_game(SAVE_PATH) == OK and GameState.serialize() == snapshot, "Loading restores the exact open event and all NPC positions")
	_check(EffectApplier.choose_flight_event("event_signal_test", 0) == OK and GameState.state["money"] == 1050, "The restored encounter can resolve once")
	var resolved: Dictionary = GameState.serialize()
	_check(GameState.restore(resolved) == OK and GameState.serialize() == resolved, "Restoring a resolved event does not repeat its rewards")
	for field: String in ["missing_npc", "waypoint", "position", "encounter", "system"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match field:
			"missing_npc": invalid["flight"]["npcs"].erase("npc_earth_courier")
			"waypoint": invalid["flight"]["npcs"]["npc_earth_courier"]["waypoint"] = 999
			"position": invalid["flight"]["npcs"]["npc_earth_courier"]["pos"] = [-1, 0]
			"encounter": invalid["flight"]["encounter"] = "missing"
			"system":
				invalid["current_system"] = "sys_alpha"
				invalid["systems"]["sys_alpha"] = "visited"
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == resolved, "Invalid saved NPC or encounter references preserve the running game")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The NPC verification save is removed")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["system"] = "missing"
	_check("unknown systems id 'missing'" in "\n".join(Validator.validate(groups, {})), "NPC system references are checked at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["event"] = "missing"
	_check("unknown events id 'missing'" in "\n".join(Validator.validate(groups, {})), "NPC event references are checked at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["speed"] = 0
	_check("speed must be positive" in "\n".join(Validator.validate(groups, {})), "Invalid patrol speeds are rejected")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["waypoints"] = [[0, 0], [3001, 0]]
	_check("waypoints must stay inside" in "\n".join(Validator.validate(groups, {})), "Patrol routes cannot leave the system")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["events"][0]["chance"] = 2
	_check("chance must be between" in "\n".join(Validator.validate(groups, {})), "Invalid event probability is reported")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["events"][0]["options"][0]["effects"] = [{"rep": "missing", "add": 1}]
	_check("Invalid reputation effect" in "\n".join(Validator.validate(groups, {})), "Events validate consequences through EffectApplier")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["event"] = "event_signal_test"
	_check("NPC event requires the encounter trigger" in "\n".join(Validator.validate(groups, {})), "NPC links cannot use a marker-only trigger")


func _check_view() -> void:
	_launch()
	var packed: PackedScene = load("res://scenes/system_flight.tscn")
	var view: Control = packed.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await get_tree().process_frame
	var count: int = 0
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["system"] == "sys_earth" and Conditions.npc_is_active(str(npc["id"])):
			count += 1
	_check(count > 0 and view.get_node("%NPCView").has_node("npc_earth_patrol") and not view.find_child("ObjectInteractions", true, false).get_node("npc_earth_courier").visible, "The current system shows active ships with proximity-only actions")
	var vessel: Node3D = view.get_node("%NPCView/npc_earth_courier")
	var before: Vector3 = vessel.position
	EffectApplier.advance_flight(0.5)
	_check(vessel.position != before, "NPC models update from the central patrol state")
	EffectApplier.approach_npc("npc_earth_courier")
	_check(GameState.state["flight"]["target"] == GameState.state["flight"]["npcs"]["npc_earth_courier"]["pos"], "Approach commands use the moving ship's current position")
	_check(DataLoader.get_record("sys_earth")["objects"].any(func(object: Dictionary) -> bool: return object.get("event") == "event_signal_test"), "The test marker remains in the local system")
	await _capture("patrol")
	EffectApplier.set_flight_target(Vector2(780, 1650))
	EffectApplier.advance_flight(10.0)
	_check(view.get_node("%EncounterLayer").visible and view.get_node("%Pause").disabled and view.get_node("%Map").disabled, "Marker approach opens a modal encounter and blocks background controls")
	var encounter: Control = view.get_node("%FlightEncounter")
	_check(encounter.get_node("%EventChoices").get_child_count() == 2 and encounter.get_node("%EncounterSave").visible, "The encounter shows two JSON choices and an in-dialog save action")
	await _capture("marker")
	var old_choice: Button = encounter.get_node("%EventChoices/Option0")
	old_choice.pressed.emit()
	_check(not view.get_node("%EncounterLayer").visible and GameState.state["money"] == 1050, "A choice closes the modal and refreshes resources")
	old_choice.pressed.emit()
	_check(GameState.state["money"] == 1050, "A stale UI choice cannot pay twice")
	_chase("npc_earth_courier")
	var selection: InputEventMouseButton = InputEventMouseButton.new()
	selection.button_index = MOUSE_BUTTON_LEFT
	selection.pressed = true
	selection.position = view.camera.unproject_position(Motion.world_position(GameState.state["flight"]["npcs"]["npc_earth_courier"]["pos"], 2.8))
	view.get_node("%SpaceContainer").gui_input.emit(selection)
	view.find_child("ObjectInteractions", true, false).get_node("npc_earth_courier/Dialogue").pressed.emit()
	_check(view.get_node("%EncounterLayer").visible and GameState.state["flight"]["encounter"] == "event_courier_test", "The same modal handles a moving-ship encounter")
	if "--probe-npc-user-save" in OS.get_cmdline_user_args() and not FileAccess.file_exists(GameState.SAVE_PATH):
		var user_snapshot: Dictionary = GameState.serialize()
		encounter.get_node("%EncounterSave").pressed.emit()
		_check(FileAccess.file_exists(GameState.SAVE_PATH), "The encounter Save button writes the actual user save")
		encounter.get_node("%EventChoices/Option1").pressed.emit()
		view.get_node("%Load").pressed.emit()
		_check(GameState.serialize() == user_snapshot and view.get_node("%EncounterLayer").visible, "The Load button restores the actual pending encounter save")
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH)) == OK, "The encounter user-save probe file is removed")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "The view test can save an open ship encounter")
	encounter.get_node("%EventChoices/Option1").pressed.emit()
	_check(GameState.load_game(SAVE_PATH) == OK and GameState.serialize() == snapshot and view.get_node("%EncounterLayer").visible, "Loading rebuilds the open encounter in the live UI")
	await _capture("contact")
	encounter.get_node("%EventChoices/Option0").pressed.emit()
	_check(GameState.state["money"] == 1075 and not view.get_node("%EncounterLayer").visible, "The restored ship encounter resolves without replaying previous rewards")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The UI verification save is removed")
	view.queue_free()
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-npcs" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "The NPC encounter view is rendered")
	_check(image.save_png("res://.godot/stage-six-npc-" + suffix + ".png") == OK, "The NPC encounter screenshot is saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
