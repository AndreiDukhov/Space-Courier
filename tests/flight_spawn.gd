extends Node

const Motion = preload("res://scripts/flight_motion.gd")
const Spawn = preload("res://scripts/flight_spawn.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Geometry = preload("res://scripts/space_geometry.gd")
const Validator = preload("res://scripts/data_validator.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Flight spawn data validates")
	_check_departure()
	_check_directions()
	_check_routes()
	_check_validation()
	await _check_ui()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Flight spawn checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	_check(EffectApplier.launch_flight() == OK, "The normal flight action leaves the workshop")
	for entry: Dictionary in GameState.state["flight"]["npcs"].values():
		entry["cooldown"] = 10000.0


func _check_departure() -> void:
	_launch()
	var earth: Dictionary = Conditions.space_object("earth_1")
	var pos: Vector2 = Motion.point(GameState.state["flight"]["pos"])
	var distance: float = pos.distance_to(Motion.point(earth["pos"]))
	_check(pos == Spawn.hub_departure() and distance > float(earth["radius"]) / Motion.WORLD_SCALE and Conditions.can_dock(), "Launching places the ship outside Earth's surface within docking range")
	_check(GameState.state["flight"]["pos"] == GameState.state["flight"]["target"] and not GameState.state["flight"]["paused"], "The launch begins stationary and ready for a movement command")
	_check(not Conditions.star_is_dangerous(pos), "Earth departure is outside the stellar hazard")
	EffectApplier.set_flight_target(pos + Vector2(200, 0))
	EffectApplier.advance_flight(0.1)
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://launch-position.json") == OK and GameState.load_game("user://launch-position.json") == OK and GameState.serialize() == snapshot, "Loading a flying ship preserves its saved course and position")
	GameState.state["flight"]["pos"] = earth["pos"].duplicate()
	GameState.state["flight"]["target"] = earth["pos"].duplicate()
	_check(EffectApplier.dock_at_hub() == OK and EffectApplier.move_player("hub_tech") == OK and EffectApplier.launch_flight() == OK, "The ship can dock and launch again through the existing actions")
	_check(Motion.point(GameState.state["flight"]["pos"]) == Spawn.hub_departure(), "A later hub departure also starts beside Earth")


func _check_directions() -> void:
	var source: Dictionary = DataLoader.records["sys_earth"]
	var destination: Dictionary = DataLoader.records["sys_alpha"]
	var original_source: Array = source["map_pos"].duplicate()
	var original_destination: Array = destination["map_pos"].duplicate()
	destination["map_pos"] = [0, 0]
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	for direction: Vector2i in directions:
		source["map_pos"] = [direction.x * 100, direction.y * 100]
		var pos: Vector2 = Spawn.arrival("sys_earth", "sys_alpha")
		_check((pos - Motion.BOUNDS * 0.5).normalized().dot(Vector2(direction).normalized()) > 0.9999, "The entry edge follows relative direction " + str(direction))
		_check(Motion.bounded(pos) == pos and is_equal_approx(_edge_distance(pos), Spawn.ENTRY_MARGIN), "The directional entry remains inset from the boundary")
	source["map_pos"] = [0, 0]
	var fallback: Vector2 = Spawn.arrival("sys_earth", "sys_alpha")
	_check(is_finite(fallback.x) and is_finite(fallback.y) and fallback.y > Motion.BOUNDS.y * 0.5, "Coincident galaxy positions have a finite deterministic fallback")
	source["map_pos"] = original_source
	destination["map_pos"] = original_destination


func _check_routes() -> void:
	for route: Dictionary in DataLoader.get_records("routes"):
		_launch()
		GameState.state["current_system"] = route["from"]
		GameState.state["systems"][route["from"]] = "visited"
		var gate: Dictionary = Conditions.space_object(str(route["id"]))
		GameState.state["flight"]["pos"] = gate["pos"].duplicate()
		GameState.state["flight"]["target"] = gate["pos"].duplicate()
		GameState.state["flight"]["defeated_npcs"].append("npc_earth_raider_2")
		var npcs: Dictionary = GameState.state["flight"]["npcs"].duplicate(true)
		_check(EffectApplier.jump_route(str(route["id"])) == OK, "The authored gate enters " + str(route["to"]))
		var flight: Dictionary = GameState.state["flight"]
		var pos: Vector2 = Motion.point(flight["pos"])
		_check(pos == Spawn.arrival(str(route["from"]), str(route["to"])) and flight["pos"] == flight["target"], "The actual jump applies its route-specific stopped entry")
		_check(is_equal_approx(_edge_distance(pos), Spawn.ENTRY_MARGIN), "The actual arrival stays inside the system boundary")
		var star: Dictionary = Geometry.star(str(route["to"]))
		_check(pos.distance_to(Motion.point(star["pos"])) > float(star["hazard"]["radius"]), "Arrival avoids the destination star's hazard")
		for object: Dictionary in DataLoader.get_record(str(route["to"]))["objects"]:
			if object["type"] == "planet":
				_check(pos.distance_to(Motion.point(object["pos"])) > float(object["radius"]) / Motion.WORLD_SCALE, "Arrival is outside each planet's surface")
			elif object["type"] == "gate":
				_check(pos.distance_to(Motion.point(object["pos"])) > Motion.INTERACTION_RADIUS, "Arrival requires an approach before a new wormhole interaction")
		_check(flight["npcs"] == npcs and "npc_earth_raider_2" in flight["defeated_npcs"], "Changing the player's entry preserves NPC state and defeated ships")
		var snapshot: Dictionary = GameState.serialize()
		_check(GameState.save_game("user://route-entry.json") == OK and GameState.load_game("user://route-entry.json") == OK and GameState.serialize() == snapshot, "The route-specific entry position round-trips exactly")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["systems"][0]["objects"] = groups["systems"][0]["objects"].filter(func(object: Dictionary) -> bool: return object.get("id") != "earth_1")
	_check("The hub planet must exist in the initial system: earth_1" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "The required departure planet is validated at startup")


func _check_ui() -> void:
	_launch()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	var row: Control = view.find_child("ObjectInteractions", true, false).get_node("earth_1")
	_check(row.is_visible_in_tree() and not row.get_node("Dialogue").disabled and not row.get_node("Trade").disabled, "Normal launch shows Earth's nearby services")
	_check(view._player.position.is_equal_approx(Motion.world_position(GameState.state["flight"]["pos"], 2.8)), "The model and follow camera use the actual Earth departure position")
	await _capture("earth")
	var gate: Dictionary = Conditions.space_object("r_earth_alpha")
	GameState.state["flight"]["pos"] = gate["pos"].duplicate()
	GameState.state["flight"]["target"] = gate["pos"].duplicate()
	EffectApplier.flight_changed.emit()
	await _frames()
	var enter: Button = view.find_child("ObjectInteractions", true, false).get_node("r_earth_alpha/Enter")
	await _click(enter)
	_check(GameState.state["current_system"] == "sys_alpha" and view._player.position.is_equal_approx(Motion.world_position(Motion.coordinates(Spawn.arrival("sys_earth", "sys_alpha")), 2.8)), "A real Enter click updates the destination model and camera position")
	await _capture("alpha")
	view.queue_free()
	await _frames()


func _edge_distance(pos: Vector2) -> float:
	return minf(minf(pos.x, Motion.BOUNDS.x - pos.x), minf(pos.y, Motion.BOUNDS.y - pos.y))


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
	if "--capture-flight-spawn" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/flight-spawn-" + suffix + ".png") == OK, "The " + suffix + " flight entry renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
