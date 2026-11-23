extends Node

const FlightScene = preload("res://scenes/system_flight.tscn")
const HubScene = preload("res://scenes/hub.tscn")
const Motion = preload("res://scripts/flight_motion.gd")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Full-window flight HUD data loads")
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	await _power_button()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	for entry: Dictionary in GameState.state["flight"]["npcs"].values():
		entry["cooldown"] = 10000.0
	var flight: Control = FlightScene.instantiate()
	add_child(flight)
	flight.set_physics_process(false)
	await _frames()
	_check(flight.get_node("%SpaceContainer").get_global_rect() == flight.get_global_rect(), "The flight viewport fills the game window without margins")
	for name: String in ["Help", "Save", "Load", "SaveRow", "Toolbar"]:
		var control: Control = flight.find_child(name, true, false)
		_check(control == null or not control.is_visible_in_tree(), "The redundant flight control is removed: " + name)
	_check(flight.get_node("%Title").text == DataLoader.get_record("sys_earth")["name"], "Only the authored system name appears over space")
	var fuel: Label = flight.get_node("%FuelValue")
	var hull: Label = flight.get_node("%HullValue")
	var credits: Label = flight.get_node("%CreditsValue")
	_check(fuel.global_position.y < hull.global_position.y and hull.global_position.y < credits.global_position.y, "Fuel, hull and credits are stacked vertically")
	_check(fuel.get_parent().get_child(0).kind == "fuel" and hull.get_parent().get_child(0).kind == "hull", "Fuel and hull rows have distinct readable icons")
	GameState.state["ship"]["fuel"]["current"] = 12.75
	GameState.state["ship"]["hull"]["current"] = 63.5
	GameState.state["money"] = 1234
	flight._sync_flight()
	_check(fuel.text.begins_with("12.75/") and hull.text.begins_with("63.5/") and credits.text == "1234", "The overlay refreshes its actual resource values")
	for node: String in ["FlightResources", "Boost", "FlightDock"]:
		_check(flight.get_global_rect().encloses(flight.get_node("%" + node).get_global_rect()), "The floating control stays inside the window: " + node)
	var snapshot: Dictionary = GameState.serialize()
	await _click(flight.get_node("%Boost"))
	_check(flight._boost and flight.get_node("%Boost").button_pressed and flight.get_node("%Boost").text.is_empty(), "The lever enables boost without a long caption")
	_check(GameState.serialize() == snapshot, "Toggling boost alone consumes no fuel or time")
	await _wait(0.18)
	await _capture("boost")
	await _click(flight.get_node("%Boost"))
	_check(not flight._boost, "The same lever disables boost")
	await _click(flight.get_node("%Pause"))
	_check(GameState.state["flight"]["paused"] and flight.get_node("%Paused").visible, "The compact pause button updates the normal simulation pause")
	await _click(flight.get_node("%Pause"))
	var point: Vector2 = flight.get_global_rect().get_center() + Vector2(90, 40)
	var previous: Array = GameState.state["flight"]["target"].duplicate()
	await _click_point(point)
	_check(GameState.state["flight"]["target"] != previous, "The overlay leaves normal steering accessible")
	await _click(flight.get_node("%Map"))
	_check(flight._map != null, "The compact map button opens the normal galaxy map")
	await _click(flight._map.get_node("%Close"))
	await _check_instruments(flight)
	for system: Dictionary in DataLoader.get_records("systems"):
		GameState.state["current_system"] = system["id"]
		GameState.state["systems"][system["id"]] = "visited"
		EffectApplier.galaxy_changed.emit()
		await _frames()
		_check(flight.get_node("%Title").text == system["name"], "Changing systems refreshes the name overlay")
		_check_indicators(flight)
		if system["id"] == "sys_earth":
			await _capture("flight")
	flight.queue_free()
	await _frames()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Flight HUD checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _power_button() -> void:
	EffectApplier.move_player("hub_office")
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	hub.open_order_terminal()
	await _frames()
	var button: Button = hub.get_node("%CloseTerminal")
	var artwork: TextureRect = hub.get_node("Terminal/Artwork")
	var centre: Vector2 = artwork.global_position + Vector2(0.5, 679.0 / 800.0) * artwork.size
	_check(button.get_global_rect().get_center().distance_to(centre) < 0.01, "The power button is centred precisely in its physical socket")
	_check(button.size.x <= 43.0 * artwork.size.x / 1280 and button.get_theme_constant("icon_max_width") < button.size.x * 0.7, "The button and glyph scale together with the monitor")
	await _capture("power")
	await _click(button)
	_check(not hub.get_node("%Terminal").visible, "The centred power button still closes the monitor")
	hub.queue_free()
	await _frames()


func _check_indicators(flight: Control) -> void:
	var visible_rows: Array[Control] = []
	var blocked: Array[Rect2] = flight.hud.reserved_rects()
	blocked.append(flight._journal.button_rect())
	for row: Control in flight._indicators.get_children():
		if not row.visible:
			continue
		visible_rows.append(row)
		var rect: Rect2 = row.get_rect()
		_check(Rect2(Vector2.ZERO, flight.size).encloses(rect), "An edge indicator remains completely visible: " + row.name)
		for area: Rect2 in blocked:
			_check(not rect.intersects(area), "Indicators avoid the name, instruments, lever, dock and journal")
	for first: int in range(visible_rows.size()):
		for second: int in range(first + 1, visible_rows.size()):
			_check(not visible_rows[first].get_rect().intersects(visible_rows[second].get_rect()), "Edge indicators remain separate")


func _check_instruments(flight: Control) -> void:
	for node: Control in [flight.get_node("%FuelValue").get_parent().get_child(0), flight.get_node("%HullValue").get_parent().get_child(0), flight.get_node("%Boost")]:
		await RenderingServer.frame_post_draw
		var before: Image = get_viewport().get_texture().get_image()
		node.hide()
		await _frames()
		await RenderingServer.frame_post_draw
		var after: Image = get_viewport().get_texture().get_image()
		var scale: Vector2 = Vector2(after.get_size()) / get_viewport().get_visible_rect().size
		var changed: int = 0
		for y: int in range(1, 10):
			for x: int in range(1, 10):
				var point: Vector2 = (node.global_position + node.size * Vector2(x / 10.0, y / 10.0)) * scale
				var a: Color = before.get_pixel(int(point.x), int(point.y))
				var b: Color = after.get_pixel(int(point.x), int(point.y))
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.05:
					changed += 1
		_check(changed >= 3, "The instrument remains rendered after closing the map: " + node.name)
		node.show()
		node.queue_redraw()
		await _frames()


func _capture(suffix: String) -> void:
	if "--capture-flight-hud" in OS.get_cmdline_user_args():
		if "--small" in OS.get_cmdline_user_args():
			suffix += "-small"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/full-flight-hud-" + suffix + ".png")


func _click(button: Button) -> void:
	await _click_point(button.get_global_rect().get_center())


func _click_point(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)
	await _frames()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
