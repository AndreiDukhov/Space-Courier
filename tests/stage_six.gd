extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Spawn = preload("res://scripts/flight_spawn.gd")
const Navigation = preload("res://scripts/galaxy_navigation.gd")
const Validator = preload("res://scripts/data_validator.gd")
const FlightView = preload("res://scripts/system_flight.gd")
const SAVE_PATH: String = "res://.godot/stage-six-save-test.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Player flight data loads without errors")
	_check_movement()
	_check_fuel()
	_check_celestials()
	_check_wormholes()
	_check_persistence()
	_check_validation()
	await _check_view()
	await _check_scene_flow()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 6 player flight checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _workshop() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true, "pirate_test_bribed": true})
	for npc: Dictionary in GameState.state["flight"]["npcs"].values():
		npc["cooldown"] = 10000.0
	for npc: Dictionary in DataLoader.get_records("npcs"):
		GameState.state["flight"]["defeated_npcs"].append(npc["id"])
	_check(EffectApplier.move_player("hub_tech") == OK, "The test starts inside the workshop")


func _launch() -> void:
	_workshop()
	_check(EffectApplier.launch_flight() == OK, "The player can launch from the office")


func _approach_gate(route_id: String) -> void:
	for object: Dictionary in DataLoader.get_record(str(GameState.state["current_system"]))["objects"]:
		if object.get("to_route") == route_id:
			EffectApplier.set_flight_target(Motion.point(object["pos"]))
			EffectApplier.advance_flight(20.0)


func _check_movement() -> void:
	_workshop()
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.set_flight_target(Vector2(800, 380)) == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "A ship cannot be moved while the player is in the building")
	_check(EffectApplier.launch_flight() == OK and GameState.state["location"] == "ship_bridge", "Launching leaves the building and enters local space")
	_check(not Conditions.can_use_order_terminal() and Conditions.can_dock(), "Launching leaves the terminal and places the ship within reach of Earth")
	var origin: Vector2 = Motion.point(GameState.state["flight"]["pos"])
	var destination: Vector2 = origin + Vector2(300, 0)
	_check(EffectApplier.set_flight_target(destination) == OK, "A flight target can be set")
	EffectApplier.advance_flight(1.0)
	_check(Motion.point(GameState.state["flight"]["pos"]).is_equal_approx(origin + Vector2(150, 0)), "Real-time movement advances at the configured speed")
	_check(Clock.current_day() == 1 and is_equal_approx(float(GameState.state["ship"]["fuel"]["current"]), 30.0 - 1.0 / 60.0), "A second of movement slowly consumes fuel without advancing game days")
	_check(EffectApplier.toggle_flight_pause() == OK, "The player can pause flight")
	snapshot = GameState.serialize()
	EffectApplier.advance_flight(3.0)
	_check(GameState.serialize() == snapshot and EffectApplier.set_flight_target(Vector2.ZERO) == ERR_UNAVAILABLE, "Pause stops movement and ignores new flight commands")
	_check(EffectApplier.toggle_flight_pause() == OK, "Flight can resume")
	EffectApplier.advance_flight(10.0)
	_check(Motion.point(GameState.state["flight"]["pos"]) == destination, "The ship stops at its destination without overshooting")
	_check(EffectApplier.set_flight_target(Vector2(-100, Motion.BOUNDS.y + 100)) == OK and Motion.point(GameState.state["flight"]["target"]) == Vector2(0, Motion.BOUNDS.y), "Flight targets are constrained to the current system")
	snapshot = GameState.serialize()
	_check(EffectApplier.set_flight_target(Vector2(NAN, 0)) == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Non-finite commands are rejected")
	EffectApplier.advance_flight(-1.0)
	_check(GameState.serialize() == snapshot, "A negative frame delta cannot move the ship")
	EffectApplier.set_flight_target(Vector2(900, 660))
	EffectApplier.advance_flight(20.0)
	_check(Conditions.can_dock() and EffectApplier.dock_at_hub() == OK and GameState.state["location"] == "hub_office", "Docking near the home planet returns to the separate hub building")


func _check_wormholes() -> void:
	_launch()
	_check(GameState.state["systems"]["sys_alpha"] == "hidden" and Navigation.visible_routes().is_empty(), "Entering a system reveals no uncharted destinations")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.jump_route("r_earth_alpha") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "The route cannot be traversed from the centre of the map")
	_approach_gate("r_earth_alpha")
	var fuel_before_jump: float = float(GameState.state["ship"]["fuel"]["current"])
	_check(Conditions.can_jump("r_earth_alpha") and not Conditions.is_destination_known("r_earth_alpha"), "An unknown wormhole remains usable after approaching it")
	EffectApplier.toggle_flight_pause()
	_check(not Conditions.can_jump("r_earth_alpha"), "A paused ship cannot start a jump")
	EffectApplier.toggle_flight_pause()
	_check(EffectApplier.jump_route("r_earth_alpha") == OK, "The player can jump into an unknown wormhole")
	_check(GameState.state["current_system"] == "sys_alpha" and is_equal_approx(float(GameState.state["ship"]["fuel"]["current"]), fuel_before_jump - 4.0) and Clock.current_day() == 2, "The fixed route chooses its authored destination and preserves fractional fuel")
	_check(Conditions.is_destination_known("r_earth_alpha") and not Conditions.is_destination_known("r_alpha_earth"), "Traversal reveals only that wormhole's own direction")
	_check(GameState.state["systems"]["sys_far"] == "hidden" and GameState.state["systems"]["sys_colony_3"] == "hidden", "The arrival system does not disclose its other outgoing connections")
	_check(Motion.point(GameState.state["flight"]["pos"]) == Spawn.arrival("sys_earth", "sys_alpha") and GameState.state["flight"]["target"] == GameState.state["flight"]["pos"], "Arrival loads the destination edge facing the source system with a stopped ship")
	_approach_gate("r_alpha_far")
	_check(EffectApplier.jump_route("r_alpha_far") == OK and GameState.state["current_system"] == "sys_far", "A wormhole can lead to the distant end of the galaxy")
	_check(not Conditions.can_dock() and not Conditions.can_enter("hub_office"), "Distant arrival cannot open the home building")
	_launch()
	_approach_gate("r_earth_alpha")
	GameState.state["ship"]["fuel"]["current"] = 5
	snapshot = GameState.serialize()
	_check(EffectApplier.jump_route("r_earth_alpha") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Unknown travel uses the visible upper fuel budget without leaking actual cost")


func _check_fuel() -> void:
	_launch()
	var origin: Vector2 = Motion.point(GameState.state["flight"]["pos"])
	for leg: int in range(20):
		var target: Vector2 = origin + (Vector2(450, 0) if leg % 2 == 0 else Vector2.ZERO)
		EffectApplier.set_flight_target(target)
		EffectApplier.advance_flight(3.0)
	EffectApplier.advance_flight(0.1)
	_check(is_equal_approx(float(GameState.state["ship"]["fuel"]["current"]), 29.0), "One minute of actual movement consumes one fuel unit")
	var fuel: float = float(GameState.state["ship"]["fuel"]["current"])
	EffectApplier.advance_flight(200.0)
	_check(GameState.state["ship"]["fuel"]["current"] == fuel, "Waiting at the destination consumes no fuel")
	_launch()
	EffectApplier.set_flight_target(origin + Vector2(300, 0))
	EffectApplier.advance_flight(2.0)
	var single_step: float = float(GameState.state["ship"]["fuel"]["current"])
	_launch()
	EffectApplier.set_flight_target(origin + Vector2(300, 0))
	for _step: int in range(16):
		EffectApplier.advance_flight(0.125)
	_check(is_equal_approx(float(GameState.state["ship"]["fuel"]["current"]), single_step), "Fuel consumption does not depend on physics frame size")
	_launch()
	GameState.state["ship"]["fuel"]["current"] = 0.01
	EffectApplier.set_flight_target(origin + Vector2(300, 0))
	EffectApplier.advance_flight(10.0)
	_check(is_equal_approx(Motion.point(GameState.state["flight"]["pos"]).distance_to(origin), 90.0) and GameState.state["ship"]["fuel"]["current"] == 0.0, "The ship spends its last fuel and stops at the affordable distance")
	var snapshot: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(10.0)
	_check(GameState.state["flight"]["pos"] == snapshot["flight"]["pos"] and GameState.state["ship"]["fuel"]["current"] == 0.0 and not Conditions.can_move_flight(), "Zero fuel prevents further player movement without stopping other ships")
	_check(Conditions.can_request_tow() and EffectApplier.request_tow() == OK and GameState.state["ship"]["fuel"]["current"] == 30.0, "Fuel exhaustion keeps the existing rescue path available")
	_workshop()
	_check(EffectApplier.apply_effects([{"fuel": -0.25}]) == OK and Conditions.can_refuel(), "Fractional fuel effects and fractional missing fuel are supported")
	_check(EffectApplier.refuel_ship() == OK and GameState.state["ship"]["fuel"]["current"] == 30.0 and GameState.state["money"] == 995, "Refuelling fills a fractional deficit and charges only its value")
	EffectApplier.apply_effects([{"fuel": -0.01}])
	GameState.state["money"] = 0
	snapshot = GameState.serialize()
	_check(EffectApplier.refuel_ship() == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "A fractional top-up cannot become a free refuel")


func _check_celestials() -> void:
	var star_colors: Dictionary = {}
	for system: Dictionary in DataLoader.get_records("systems"):
		var stars: Array[Dictionary] = []
		var planets: Array[Dictionary] = []
		var distances: Dictionary = {}
		for object: Dictionary in system["objects"]:
			if object["type"] == "star":
				stars.append(object)
				star_colors[object["color"]] = true
			elif object["type"] == "planet":
				planets.append(object)
				distances[Motion.point(object["pos"]).distance_to(Motion.BOUNDS / 2.0)] = true
		_check(stars.size() == 1 and Motion.point(stars[0]["pos"]) == Motion.BOUNDS / 2.0, "Every system has one central star")
		_check(planets.size() == 3 and distances.size() == 3, "Every system has three planets at different orbital distances")
		_check(Motion.SPAWN.distance_to(Motion.BOUNDS / 2.0) * Motion.WORLD_SCALE > float(stars[0]["radius"]), "Arrival spawns the player outside the central star")
	_check(star_colors.size() == DataLoader.get_records("systems").size(), "Stars in different systems use different JSON colors")
	_launch()
	EffectApplier.set_flight_target(Vector2(650, 400))
	EffectApplier.advance_flight(20.0)
	_check(not Conditions.can_dock(), "Other planets in the home system cannot open the building on Earth")


func _check_persistence() -> void:
	_launch()
	EffectApplier.set_flight_target(Vector2(731, 211))
	EffectApplier.advance_flight(0.37)
	EffectApplier.toggle_flight_pause()
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "A moving ship's position, target and pause state can be saved")
	_workshop()
	_check(GameState.load_game(SAVE_PATH) == OK and GameState.serialize() == snapshot, "Loading restores the exact flight snapshot")
	for invalid_flight: Variant in [
		{}, {"pos": [0, 0], "target": [0, 0], "paused": 1},
		{"pos": [-1, 0], "target": [0, 0], "paused": false},
		{"pos": [0, 0], "target": [3001, 0], "paused": false},
		{"pos": [0, 0], "target": [0, 0], "paused": false, "npcs": {}}
	]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["flight"] = invalid_flight
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Malformed flight snapshots cannot replace the running save")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The temporary flight save is removed")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	_gate_fixture(groups)["to_route"] = "r_alpha_far"
	_check("gate route must originate" in "\n".join(Validator.validate(groups, {})), "Gates cannot refer to a route starting in another system")
	groups = DataLoader.records_by_group.duplicate(true)
	_gate_fixture(groups)["pos"] = [500, 380]
	_check("wormholes must be near" in "\n".join(Validator.validate(groups, {})), "Wormholes belong near the system boundary")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["systems"][0]["objects"].erase(_gate_fixture(groups))
	_check("route requires a gate" in "\n".join(Validator.validate(groups, {})), "Each route needs an actual physical entrance")
	groups = DataLoader.records_by_group.duplicate(true)
	for object: Dictionary in groups["systems"][0]["objects"]:
		if object["type"] == "star":
			object["color"] = "not a color"
	_check("Celestial color must" in "\n".join(Validator.validate(groups, {})), "Invalid star colors are reported by DataLoader validation")
	groups = DataLoader.records_by_group.duplicate(true)
	for object: Dictionary in groups["systems"][0]["objects"]:
		if object["type"] == "star":
			object["pos"] = [100, 100]
	_check("star must be at its centre" in "\n".join(Validator.validate(groups, {})), "Stars must remain at the system centre")


func _gate_fixture(groups: Dictionary) -> Dictionary:
	for object: Dictionary in groups["systems"][0]["objects"]:
		if object.get("type") == "gate":
			return object
	return {}


func _check_view() -> void:
	_launch()
	var packed: PackedScene = load("res://scenes/system_flight.tscn")
	var view: FlightView = packed.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await get_tree().process_frame
	_check(view.get_node("%Viewport").get_camera_3d() != null and view.get_node("%SystemSpace").get_child_count() > 0, "The flight view contains a separate 3D system and top camera")
	_check("Назначение неизвестно" in view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha/Enter").tooltip_text and "Альфа" not in view.gate_name("r_earth_alpha", 1), "An unknown gate's label conceals its destination")
	_check("3–6" in view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha/Enter").tooltip_text and not view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha").visible, "Gate fuel estimates move into the overhead action tooltip")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(view.get_node("%Viewport").size) * Vector2(0.7, 0.4)
	view.get_node("%SpaceContainer").gui_input.emit(click)
	_check(Motion.point(GameState.state["flight"]["target"]) != Motion.SPAWN, "Clicking local space sets a world-plane target")
	var first_target: Vector2 = Motion.point(GameState.state["flight"]["target"])
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(view.get_node("%Viewport").size) * Vector2(0.25, 0.6)
	view.get_node("%SpaceContainer").gui_input.emit(motion)
	_check(Motion.point(GameState.state["flight"]["target"]) != first_target, "Holding the left mouse button updates the target as the cursor moves")
	var held_target: Vector2 = Motion.point(GameState.state["flight"]["target"])
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	get_viewport().push_input(release)
	motion.position = Vector2(view.get_node("%Viewport").size) * Vector2(0.8, 0.2)
	view.get_node("%SpaceContainer").gui_input.emit(motion)
	_check(Motion.point(GameState.state["flight"]["target"]) == held_target, "Releasing the mouse stops cursor tracking and keeps the last destination")
	if DisplayServer.get_name() != "headless":
		var space_rect: Rect2 = view.get_node("%SpaceContainer").get_global_rect()
		var actual_press: InputEventMouseButton = InputEventMouseButton.new()
		actual_press.button_index = MOUSE_BUTTON_LEFT
		actual_press.button_mask = MOUSE_BUTTON_MASK_LEFT
		actual_press.pressed = true
		actual_press.position = space_rect.position + space_rect.size * Vector2(0.6, 0.3)
		actual_press.global_position = actual_press.position
		get_viewport().push_input(actual_press)
		var pressed_target: Vector2 = Motion.point(GameState.state["flight"]["target"])
		_check(pressed_target != held_target, "A real viewport mouse press reaches the flight controls")
		var actual_motion: InputEventMouseMotion = InputEventMouseMotion.new()
		actual_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		actual_motion.position = space_rect.position + space_rect.size * Vector2(0.35, 0.7)
		actual_motion.global_position = actual_motion.position
		get_viewport().push_input(actual_motion)
		_check(Motion.point(GameState.state["flight"]["target"]) != pressed_target, "Dragging through the viewport updates the ship's destination")
		get_viewport().push_input(release)
	view.get_node("%Pause").pressed.emit()
	_check(GameState.state["flight"]["paused"] and view.get_node("%Paused").visible, "The pause button updates the game state and HUD")
	await _capture("local")
	view.get_node("%Pause").grab_focus()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key)
	_check(not GameState.state["flight"]["paused"], "Space resumes flight even when a UI button owns keyboard focus")
	_approach_gate("r_earth_alpha")
	_check(not view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha/Enter").disabled, "Approaching the wormhole enables its jump control")
	view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha/Enter").pressed.emit()
	_check(GameState.state["current_system"] == "sys_alpha" and "Альфа" in view.get_node("%Title").text, "The jump loads and labels the new system")
	_check(view.find_child("ObjectInteractions", true, false).has_node("r_alpha_far") and not view.find_child("ObjectInteractions", true, false).has_node("r_earth_beta"), "Objects are rebuilt from the destination system's own JSON")
	view.get_node("%Map").pressed.emit()
	var map: Control = view.get_node("GalaxyMap")
	await get_tree().process_frame
	_check(map.get_node("%Chart").has_node("sys_alpha") and not map.get_node("%Chart").has_node("sys_far"), "The global map reveals only the system actually reached")
	var before: String = str(GameState.state["current_system"])
	map.get_node("%Jump").pressed.emit()
	_check(not view.has_node("GalaxyMap") and GameState.state["current_system"] == before, "The map button returns to local flight without teleporting")
	await _capture("arrival")
	_approach_gate("r_alpha_earth")
	view.find_child("ObjectInteractions", true, false).get_node("r_alpha_earth/Enter").pressed.emit()
	_check(GameState.state["current_system"] == "sys_earth" and "Альфа" in view.gate_name("r_earth_alpha", 1), "Returning home shows the learned destination on the original wormhole")
	_check("Топливо: 4" in view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha/Enter").tooltip_text and not Conditions.can_dock(), "Measured cost is shown while docking still requires a planetary approach")
	EffectApplier.set_flight_target(Vector2(900, 660))
	EffectApplier.advance_flight(20.0)
	_check(Conditions.can_dock(), "A home-planet approach enables docking through dialogue")
	await _capture("known")
	if "--capture-systems" in OS.get_cmdline_user_args():
		for system: Dictionary in DataLoader.get_records("systems"):
			GameState.state["current_system"] = system["id"]
			GameState.state["systems"][system["id"]] = "visited"
			GameState.state["flight"]["pos"] = Motion.coordinates(Motion.SPAWN)
			GameState.state["flight"]["target"] = Motion.coordinates(Motion.SPAWN)
			EffectApplier.galaxy_changed.emit()
			for object: Dictionary in system["objects"]:
				if object["type"] == "star":
					var star: MeshInstance3D = view.get_node("%SystemSpace").find_child(str(object["id"]), true, false)
					_check(star != null and star.mesh is SphereMesh and is_equal_approx(star.mesh.radius, float(object["radius"])), "The central star is a 3D sphere using its JSON radius")
			await _capture(str(system["id"]))
	view.queue_free()
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-flight" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "The player flight viewport is rendered")
	_check(image.save_png("res://.godot/stage-six-" + suffix + ".png") == OK, "The player flight screenshot is saved")


func _check_scene_flow() -> void:
	get_tree().current_scene = null
	_check(get_tree().change_scene_to_file("res://scenes/boot.tscn") == OK, "The normal project entry point can start")
	var hub: Node = await _wait_scene("Hub")
	_check(hub != null, "The normal boot loads the hub scene")
	if hub == null:
		return
	hub.get_node("%Locations/hub_tech/Travel").pressed.emit()
	hub.get_node("TechHotspot/Computer").pressed.emit()
	_check(not hub.get_node("%TerminalContent/ComputerMenu/Launch").disabled, "The workshop PC exposes the real flight-launch action")
	hub.get_node("%TerminalContent/ComputerMenu/Launch").pressed.emit()
	var flight: Node = await _wait_scene("SystemFlight")
	_check(flight != null and GameState.state["location"] == "ship_bridge", "Launching switches to the actual local flight scene")
	if flight == null:
		return
	EffectApplier.set_flight_target(Vector2(731, 211))
	EffectApplier.advance_flight(0.37)
	EffectApplier.toggle_flight_pause()
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "The scene-flow test saves a paused flight")
	EffectApplier.toggle_flight_pause()
	EffectApplier.set_flight_target(Vector2(900, 660))
	EffectApplier.advance_flight(20.0)
	flight.find_child("ObjectInteractions", true, false).get_node("earth_1/Dialogue").pressed.emit()
	flight.get_node("PlanetPanel").find_child("Dock", true, false).pressed.emit()
	hub = await _wait_scene("Hub")
	_check(hub != null and GameState.state["location"] == "hub_office", "Docking returns through the actual scene transition to the office")
	if hub != null:
		_check(not hub.get_node("%Locations").has_node("ship_bridge"), "The returned hub still contains only building locations")
		_check(GameState.load_game(SAVE_PATH) == OK, "A flight save can be loaded from the hub")
		flight = await _wait_scene("SystemFlight")
		_check(flight != null and GameState.serialize() == snapshot, "Loading a flight snapshot restores its scene and exact paused position")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The scene-flow verification save is removed")


func _wait_scene(scene_name: String) -> Node:
	for _frame: int in range(90):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == scene_name:
			return get_tree().current_scene
	return null


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
