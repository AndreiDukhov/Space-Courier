extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const State = preload("res://scripts/combat_state.gd")
const Validator = preload("res://scripts/data_validator.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Space presentation content validates")
	_check_validation()
	await _check_backdrops()
	await _check_interception_ui()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Space presentation checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch(system_id: String = "sys_earth") -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["current_system"] = system_id
	GameState.state["systems"][system_id] = "visited"
	for entry: Dictionary in GameState.state["flight"]["npcs"].values():
		entry["cooldown"] = 10000.0


func _check_validation() -> void:
	var backgrounds: Array[String] = []
	for system: Dictionary in DataLoader.get_records("systems"):
		_check(FileAccess.file_exists(str(system["background"])), "The background exists for " + str(system["id"]))
		if str(system["background"]) not in backgrounds:
			backgrounds.append(str(system["background"]))
	_check(backgrounds.size() == 3, "Three distinct space images are assigned to the galaxy")
	for invalid: Variant in [null, 42, "res://missing.png", "res://scripts/ui_text.gd"]:
		var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
		groups["systems"][0]["background"] = invalid
		_check("System background must reference an existing project image" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Invalid background references are reported at load time")


func _check_backdrops() -> void:
	_launch()
	var flight: Control = FlightScene.instantiate()
	add_child(flight)
	flight.set_physics_process(false)
	await _frames()
	var help: Label = flight.get_node("%Help")
	_check(help.get_line_count() == 1 and not "\n" in help.text, "All flight hints share one line")
	_check(help.get_global_rect().end.x <= flight.size.x and help.get_minimum_size().x <= help.size.x, "The one-line hints fit at the current window size")
	var resources: Label = flight.get_node("%Resources")
	var lines: PackedStringArray = resources.text.split("\n")
	_check(resources.get_line_count() == 2 and lines.size() == 2 and "Топливо" in lines[0] and "Корпус" in lines[0] and "1000 кредитов" == lines[1], "Fuel and hull share the first line, with credits below")
	_check(resources.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and resources.get_global_rect().end.x <= flight.size.x, "Resource rows align to the upper right")
	var backdrop: TextureRect = flight.find_child("SpaceBackdrop", true, false)
	_check(flight.get_node("%Viewport").transparent_bg and backdrop.show_behind_parent and backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The background sits behind the transparent flight viewport and passes pointer input")
	for system_id: String in ["sys_earth", "sys_alpha", "sys_beta"]:
		GameState.state["current_system"] = system_id
		GameState.state["systems"][system_id] = "visited"
		EffectApplier.galaxy_changed.emit()
		await _frames()
		_check(backdrop.texture.resource_path == DataLoader.get_record(system_id)["background"], "Changing systems updates the flight background")
		await _check_visible_background(flight.get_node("%SpaceContainer"), backdrop)
		await _capture("flight-" + system_id)
		GameState.state["combat"] = State.initial("pirate_light", "")
		var combat: Control = CombatScene.instantiate()
		add_child(combat)
		await _frames()
		var combat_space: Control = combat.find_child("SpaceContainer", true, false)
		var combat_backdrop: TextureRect = combat_space.get_node("SpaceBackdrop")
		_check(combat_backdrop.texture == backdrop.texture and combat_space.get_node("Viewport").transparent_bg, "Combat uses the current system's same background")
		var tile: MeshInstance3D = combat.find_child("Board", true, false).get_node("Tiles").get_child(0)
		_check(tile.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and tile.material_override.albedo_color.a < 1.0, "The battle grid leaves the cosmic background visible through its tiles")
		await _check_visible_background(combat_space, combat_backdrop)
		await _capture("combat-" + system_id)
		combat.queue_free()
		await _frames()
		GameState.state["combat"] = {}
	var before: Array = GameState.state["flight"]["target"].duplicate()
	await _click_at(flight.get_node("%SpaceContainer").get_global_rect().get_center() + Vector2(90, 50))
	_check(GameState.state["flight"]["target"] != before, "The background preserves steering through the normal map input")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://space-background.json") == OK and GameState.load_game("user://space-background.json") == OK and GameState.serialize() == snapshot, "The selected system restores its backdrop through the existing save state")
	await _frames()
	_check(backdrop.texture.resource_path == DataLoader.get_record("sys_beta")["background"], "Loading keeps the destination's background")
	flight.queue_free()
	await _frames()


func _check_interception_ui() -> void:
	_launch("sys_beta")
	var npc_id: String = "npc_beta_raider_2"
	var entry: Dictionary = GameState.state["flight"]["npcs"][npc_id]
	entry["pos"] = [300.0, 1800.0]
	entry["cooldown"] = 0.0
	GameState.state["flight"]["pos"] = [340.0, 1800.0]
	GameState.state["flight"]["target"] = [340.0, 1800.0]
	GameState.state["money"] = 100
	var flight: Control = FlightScene.instantiate()
	add_child(flight)
	flight.set_physics_process(false)
	await _frames()
	EffectApplier.advance_flight(0.1)
	await _frames()
	var event_id: String = str(DataLoader.get_record(npc_id)["event"])
	_check(GameState.state["flight"]["encounter"] == event_id and flight.get_node("%EncounterLayer").visible, "A pirate catching the player opens the modal without a click")
	_check(not flight.get_node("%FlightEncounter/%EventChoices/Option0").disabled and flight.get_node("%FlightEncounter/%EventChoices/Option1").disabled, "The encounter offers combat and checks whether the bribe is affordable")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://interception.json") == OK and GameState.load_game("user://interception.json") == OK and GameState.serialize() == snapshot, "A forced pirate dialogue survives saving and loading")
	await _frames()
	await _capture("interception")
	await _click_at(flight.get_node("%FlightEncounter/%EventChoices/Option0").get_global_rect().get_center())
	_check(Conditions.has_combat() and GameState.state["combat"]["source_npc"] == npc_id, "The forced encounter's battle choice starts combat against the interceptor")
	flight.queue_free()
	await _frames()


func _check_visible_background(space: Control, backdrop: TextureRect) -> void:
	backdrop.hide()
	await _frames()
	await RenderingServer.frame_post_draw
	var before: Image = get_viewport().get_texture().get_image()
	backdrop.show()
	await _frames()
	await RenderingServer.frame_post_draw
	var after: Image = get_viewport().get_texture().get_image()
	var changed: int = 0
	var scale: Vector2 = Vector2(after.get_size()) / get_viewport().get_visible_rect().size
	for y: int in range(1, 7):
		for x: int in range(1, 11):
			var point: Vector2 = (space.global_position + space.size * Vector2(x / 11.0, y / 7.0)) * scale
			var previous: Color = before.get_pixel(int(point.x), int(point.y))
			var current: Color = after.get_pixel(int(point.x), int(point.y))
			if absf(previous.r - current.r) + absf(previous.g - current.g) + absf(previous.b - current.b) > 0.025:
				changed += 1
	_check(changed >= 5, "The rendered space image is visible beneath the 3D map")


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
	if "--capture-space-ui" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/space-ui-" + suffix + ".png") == OK, "The " + suffix + " screen renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
