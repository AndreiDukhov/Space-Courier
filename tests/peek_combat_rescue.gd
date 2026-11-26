extends Node

const Motion = preload("res://scripts/flight_motion.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")

var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All content and peeking resources validate")
	if not DataLoader.load_errors.is_empty():
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	_new_game()
	var hub: Control = await _scene("hub")
	await _peek(hub)
	await _rescue()
	await _combat()
	for message: String in failures:
		printerr("FAIL: " + message)
	print("Peek combat rescue checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _peek(hub: Control) -> void:
	EffectApplier.move_player("hub_corridor")
	await _frames()
	_check(hub.get_node("%Background").texture.get_width() == 1671, "The revised corridor image is loaded")
	var widths: Array[float] = [0.12, 0.052, 0.097, 0.044, 0.115]
	var index: int = 0
	for door: Dictionary in DataLoader.get_record("hub_corridor_doors")["doors"]:
		_check(float(door["drop_rect"][2]) > widths[index], "The full door frame is easier to click")
		index += 1
	await _click(hub.get_node("BedroomDoors/door_pilot"))
	await _click(hub.get_node("BedroomDoors/DoorMenu").find_child("Peek", true, false))
	_check(hub._peek != null and hub._peek.location_id == "hub_pilot_bedroom", "The real bedroom action opens a view through the door")
	if hub._peek != null:
		var door: Sprite2D = hub._peek.get_node("DoorSprites/Door")
		_check(door.texture is AtlasTexture and hub._peek.has_node("DoorSprites/Frame") and GameState.state["peek"]["opening"] == 0, "The separate door starts closed against the stationary jamb")
		var snapshot: Dictionary = GameState.serialize()
		var before: Vector2 = hub._peek._room.position
		await _capture("peek")
		await _motion(Vector2(hub.size.x * 0.85, hub.size.y * 0.3), Vector2.ZERO)
		await get_tree().create_timer(0.3).timeout
		_check(hub._peek._room.position.distance_to(before) > 8, "Pointer motion changes the viewing angle behind the foreground door")
		_check(GameState.serialize() == snapshot, "Looking around spends no time and changes no gameplay state")
		await _capture("peek-angle")
		await _key(KEY_ESCAPE)
		_check(hub._peek == null and not PauseMenu.is_open(), "Escape leaves peeking without opening a second menu")
	Clock.advance_slots(2)
	EffectApplier.move_player("hub_showers")
	await _frames()
	await _click(hub.find_child("PeekShower", true, false))
	_check(hub._peek != null and hub._peek.location_id == "hub_showers", "The shower uses the same peeking presentation")
	if hub._peek != null:
		await _capture("shower")
		await _click(hub._peek.find_child("Close", true, false))


func _rescue() -> void:
	_new_game()
	EffectApplier.move_player("hub_tech")
	_check(GameState.save_game() == OK, "A manual save is available before departure")
	var manual: String = FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.launch_flight() == OK, "Departure succeeds after saving")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.AUTOSAVE_PATH))
	_check(saved["location"] == "hub_tech" and saved["money"] == before["money"] and saved["day"] == before["day"], "The autosave is written before the departure changes location")
	_check(FileAccess.get_file_as_string(GameState.SAVE_PATH) == manual, "The separate autosave preserves the manual save")
	var flight: Control = await _scene("system_flight")
	flight.set_physics_process(false)
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true})
	GameState.state["ship"]["fuel"]["current"] = 0.000001
	EffectApplier.set_flight_target(Motion.point(GameState.state["flight"]["pos"]) + Vector2(100, 0))
	EffectApplier.advance_flight(1.0)
	await _frames()
	_check(GameState.state["ship"]["fuel"]["current"] == 0 and flight._fuel_dialog != null and GameState.state["location"] == "ship_bridge", "Running dry presents a choice while the player remains in space")
	var stopped: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(5.0)
	_check(GameState.serialize() == stopped, "The emergency choice freezes ships, hazards and events")
	await _capture("empty-fuel")
	_check(GameState.save_game() == OK, "An empty-tank manual save does not replace the preflight autosave")
	await _click(flight._fuel_dialog.find_child("Load", true, false))
	_check(flight._fuel_dialog.find_child("LoadAuto", true, false).is_visible_in_tree(), "Loading offers the separate preflight slot even after a newer empty-tank save")
	await _click(flight._fuel_dialog.find_child("LoadAuto", true, false))
	var hub: Control = await _wait_scene("Hub")
	_check(hub != null and GameState.serialize() == before, "The load choice returns to the exact preflight autosave without a towing charge")
	if hub == null:
		return
	hub._launch_flight()
	flight = await _wait_scene("SystemFlight")
	flight.set_physics_process(false)
	GameState.state["money"] = 100
	GameState.state["ship"]["fuel"]["current"] = 0.0
	EffectApplier.flight_changed.emit()
	await _frames()
	await _click(flight._fuel_dialog.find_child("Tow", true, false))
	hub = await _wait_scene("Hub")
	_check(hub != null and GameState.state["location"] == GameState.INITIAL_LOCATION and GameState.state["current_system"] == "sys_earth", "The tow actually returns to the hub building")
	_check(GameState.state["money"] == -400 and GameState.state["ship"]["fuel"]["current"] == GameState.state["ship"]["fuel"]["max"], "The tow charges exactly 500 credits, permits debt and restores fuel")
	_check(Conditions.has_tow_notice() and hub._tow_notice != null, "Arrival shows the warm hub notification")
	await _capture("tow-arrival")
	var rescued: Dictionary = GameState.serialize()
	_check(EffectApplier.request_tow() == ERR_UNAVAILABLE and GameState.serialize() == rescued, "Repeated towing cannot charge the player again in the hub")
	await _click(hub._tow_notice.find_child("Close", true, false))
	_check(not Conditions.has_tow_notice() and hub._tow_notice == null, "Acknowledging arrival clears its saved notification")
	_check(GameState.save_game("user://rescue-check.json") == OK and GameState.load_game("user://rescue-check.json") == OK, "Debt and rescue flags survive serialization")


func _combat() -> void:
	_new_game()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var pirate: Dictionary = GameState.state["flight"]["npcs"]["npc_earth_pirate"]
	pirate["weapons"] = ["cannon_s"]
	GameState.state["flight"]["pos"] = Motion.coordinates(Motion.point(pirate["pos"]) - Vector2(20, 0))
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "The ordinary encounter starts combat")
	var view: Control = await _scene("combat")
	_check(view._space.get_global_rect() == view.get_global_rect(), "Combat space fills the whole game window")
	for name: String in ["Undo", "Save", "Load", "Help"]:
		_check(view.find_child(name, true, false) == null, "The removed combat control is absent: " + name)
	_check(view._actions.size.y < 160 and view._buttons["EndTurn"].global_position.x < view._buttons["Move"].global_position.x, "The compact bottom bar starts with the end-maneuver card")
	_check(view._buttons["EndTurn"].title == "Завершить ход", "The turn-ending card uses the requested label")
	_check(view._points.global_position.x > view.size.x * 0.8 and view._ap_value.text == "6/6", "AP and MP icons overlay the upper-right of the map")
	for card: Control in view._weapons.values():
		_check(card.get_global_rect().encloses(card.find_child("Caption", true, false).get_global_rect()), "Weapon captions fit inside their compact cards")
	await _capture("combat")
	var camera_before: Vector3 = view._camera.position
	var point: Vector2 = view.size * 0.5
	await _mouse(MOUSE_BUTTON_MIDDLE, true, point)
	await _motion(point + Vector2(90, 35), Vector2(90, 35))
	await _mouse(MOUSE_BUTTON_MIDDLE, false, point + Vector2(90, 35))
	_check(view._camera.position.distance_to(camera_before) > 1, "Dragging freely moves the tactical camera")
	GameState.state["ship"]["fuel"]["current"] = 0.0
	_check(EffectApplier.use_combat_ability("emergency_burn") == OK and GameState.state["ship"]["fuel"]["current"] == 0.0, "Dash works with an empty tank and consumes no fuel")
	GameState.state["combat"]["move_points"] = 0
	EffectApplier.combat_changed.emit()
	await get_tree().create_timer(0.25).timeout
	_check(view._buttons["EndTurn"]._attention and view._buttons["EndTurn"].modulate != Color.WHITE, "The end card visibly pulses when both AP and MP are exhausted")
	await _capture("combat-exhausted")
	await _click(view._buttons["EndTurn"])
	_check(GameState.state["combat"]["round"] == 2 and not view._buttons["EndTurn"]._attention, "The end card starts the next round and stops pulsing")


func _scene(name: String) -> Control:
	get_tree().change_scene_to_file("res://scenes/" + name + ".tscn")
	return await _wait_scene({"hub": "Hub", "system_flight": "SystemFlight", "combat": "Combat"}[name])


func _wait_scene(name: String) -> Control:
	for _frame: int in range(90):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == name and get_tree().current_scene.is_node_ready():
			await _frames()
			return get_tree().current_scene
	return null


func _click(button: Button) -> void:
	await _mouse(MOUSE_BUTTON_LEFT, true, button.get_global_rect().get_center())
	await _mouse(MOUSE_BUTTON_LEFT, false, button.get_global_rect().get_center())


func _mouse(button: MouseButton, pressed: bool, point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	get_viewport().push_input(event, true)
	await _frames()


func _motion(point: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	get_viewport().push_input(event, true)
	await _frames()


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-revision" in OS.get_cmdline_user_args():
		if "--small" in OS.get_cmdline_user_args(): suffix += "-small"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/revision-" + suffix + ".png")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
