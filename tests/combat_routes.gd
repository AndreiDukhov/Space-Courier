extends Node

const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Routes = preload("res://scripts/combat_routes.gd")
const State = preload("res://scripts/combat_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const CombatScene = preload("res://scenes/combat.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Combat route content validates")
	_check_geometry()
	await _check_player_motion()
	await _check_enemy_motion()
	await _check_legacy_undo()
	_check_facing_history()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Combat route checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _battle() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var npc: Dictionary = GameState.state["flight"]["npcs"]["npc_earth_pirate"]
	GameState.state["flight"]["pos"] = npc["pos"].duplicate()
	GameState.state["flight"]["target"] = npc["pos"].duplicate()
	EffectApplier.start_flight_event("event_pirate_test")
	EffectApplier.choose_flight_event("event_pirate_test", 0)
	var combat: Dictionary = GameState.state["combat"]
	combat["player"]["pos"] = [8, 12]
	combat["player"]["facing"] = 2
	combat["opponent"]["pos"] = [22, 12]
	combat["opponent"]["facing"] = 6
	for actor: String in ["player", "opponent"]:
		combat["movement"][actor] = State.new_turn(combat[actor])


func _check_geometry() -> void:
	var settings: Dictionary = DataLoader.get_record("ship_main")["movement"]
	var origin: Vector2i = Vector2i(10, 12)
	var turn: Dictionary = {"origin": [8, 8], "facing": 2, "history": []}
	var vessel: Dictionary = {"pos": Math.coordinates(origin), "facing": 2}
	var path: Array[Vector2i] = Routes.path(vessel, Vector2i(16, 11), turn, 8, settings, Vector2i(30, 20))
	_check(not path.is_empty() and not Movement.cone_contains(origin, Vector2i(13, 11), Vector2i(8, 8), 2, 8, settings, 2, true), "Inertia reproduces a destination whose straight line crosses forbidden cells")
	_verify_path(path, vessel, turn, 8, settings, Vector2i(30, 20))
	origin = Vector2i(8, 12)
	vessel = {"pos": Math.coordinates(origin), "facing": 2}
	turn = State.new_turn(vessel)
	path = Routes.path(vessel, Vector2i(13, 12), turn, 6, settings, Vector2i(10, 12))
	_check(not path.is_empty() and (path.has(Vector2i(10, 11)) or path.has(Vector2i(10, 13))), "A reachable maneuver can route around an occupied ship")
	_verify_path(path, vessel, turn, 6, settings, Vector2i(10, 12))
	var expected: Array[Vector2i] = path.duplicate()
	path.clear()
	_check(Routes.path(vessel, Vector2i(13, 12), turn, 6, settings, Vector2i(10, 12)) == expected, "Returned paths cannot mutate the cached geometry")
	_check(Routes.path(vessel, Vector2i(10, 12), turn, 6, settings, Vector2i(10, 12)).is_empty(), "Occupied destinations stay unavailable")
	_check(Routes.path(vessel, Vector2i(13, 12), turn, 4, settings, Vector2i(10, 12)).is_empty(), "A reduced movement budget invalidates the cached destination")
	for facing: int in range(8):
		vessel = {"pos": [16, 12], "facing": facing}
		turn = State.new_turn(vessel)
		var target: Vector2i = Vector2i(16, 12) + Movement.DIRECTIONS[facing] * 3
		path = Routes.path(vessel, target, turn, 6, settings, Vector2i(1, 1))
		_check(not path.is_empty() and path[-1] == target, "The route supports heading " + str(facing))
		_verify_path(path, vessel, turn, 6, settings, Vector2i(1, 1))


func _verify_path(path: Array[Vector2i], vessel: Dictionary, turn: Dictionary, budget: int, settings: Dictionary, occupied: Vector2i) -> void:
	_check(not path.is_empty() and path[0] == Math.cell(vessel["pos"]), "A route starts at the actual ship cell")
	var blocked: Array[Vector2i] = [occupied]
	for index: int in range(1, path.size()):
		var delta: Vector2i = path[index] - path[index - 1]
		_check(maxi(absi(delta.x), absi(delta.y)) == 1, "Each route leg connects adjacent cells")
		_check(Conditions.can_move_vessel(vessel, path[index], turn, budget, settings, occupied), "Every intermediate waypoint is an available highlighted destination")
		_check(Movement.clear_segment(path[index - 1], path[index], blocked), "A route leg cannot clip an occupied cell or its corner")


func _check_player_motion() -> void:
	_battle()
	GameState.state["ship"]["movement"]["cone_base"] = 0.0
	GameState.state["ship"]["movement"]["cone_slope_base"] = 0.2
	var target: Vector2i = Vector2i(13, 13)
	var path: Array[Vector2i] = Conditions.combat_move_path(target)
	_check(not path.is_empty() and not Conditions.can_move_combat(Vector2i(11, 13)), "A narrow cone requires travelling forward before moving laterally")
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await _frames()
	var board: Node3D = view.find_child("Board", true, false)
	var space: Control = view.find_child("SpaceContainer", true, false)
	var point: Vector2 = space.global_position + view._camera.unproject_position(Math.world_position(Math.coordinates(target)))
	var hover: InputEventMouseMotion = InputEventMouseMotion.new()
	hover.position = point
	get_viewport().push_input(hover, true)
	await _frames()
	_check(board.get_node("MovementRoute").visible, "Hovering an available cell draws the calculated polyline")
	await _capture("preview")
	var invalid_hover: InputEventMouseMotion = InputEventMouseMotion.new()
	invalid_hover.position = space.global_position + view._camera.unproject_position(Math.world_position([11, 13]))
	get_viewport().push_input(invalid_hover, true)
	await _frames()
	_check(not board.get_node("MovementRoute").visible, "Hovering a forbidden cell clears the preview")
	get_viewport().push_input(hover, true)
	await _frames()
	var ship: Node3D = board.get_node("PlayerShip")
	var before: Vector3 = ship.position
	_click_at(point)
	_check(GameState.state["combat"]["player"]["pos"] == Math.coordinates(target) and ship.position == before and board._active_route == path, "A normal map click accepts the previewed route without teleporting the model")
	await _follow_animation(board, ship, path)
	_check(ship.position.is_equal_approx(Math.world_position(Math.coordinates(target))), "The player finishes exactly at the requested cell")
	var arrival_facing: int = Movement.facing_toward(Vector2(path[-1] - path[-2]))
	_check(GameState.state["combat"]["player"]["facing"] == arrival_facing, "The saved ship heading follows the final route segment")
	var bow: Vector2 = Vector2(-sin(ship.rotation.y), -cos(ship.rotation.y))
	_check(bow.dot(Movement.heading(arrival_facing)) > 0.9999, "The model keeps its bow pointed along the end of the route")
	await _capture("facing-arrival")
	var combat: Dictionary = GameState.state["combat"]
	_check(Conditions.can_move_vessel(combat["player"], target + Vector2i(1, 1), combat["movement"]["player"], 2, Math.movement_settings(true), Math.cell(combat["opponent"]["pos"])) and not Conditions.can_move_vessel(combat["player"], target + Vector2i.RIGHT, combat["movement"]["player"], 2, Math.movement_settings(true), Math.cell(combat["opponent"]["pos"])), "The next movement cone follows the actual arrival heading")
	var course: Dictionary = DataLoader.get_record("course_cannon")
	_check(Conditions.can_fire_weapon(combat["player"], {"pos": Math.coordinates(target + Vector2i(2, 2))}, course, 6) and not Conditions.can_fire_weapon(combat["player"], {"pos": Math.coordinates(target + Vector2i(2, 0))}, course, 6), "Course weapons use the same final direction as the visible bow")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://combat-route.json") == OK and GameState.load_game("user://combat-route.json") == OK and GameState.serialize() == snapshot, "A curved maneuver round-trips through the existing save history")
	await _frames()
	var reverse: Array[Vector2i] = path.duplicate()
	reverse.reverse()
	view.find_child("Undo", true, false).pressed.emit()
	_check(board._active_route == reverse, "Undo after loading reconstructs the same route in reverse")
	await _follow_animation(board, ship, reverse)
	_check(GameState.state["combat"]["player"]["pos"] == [8, 12] and GameState.state["combat"]["move_points"] == 6 and GameState.restore(GameState.serialize()) == OK, "Undo restores position, movement points and a valid combat snapshot")
	view.queue_free()
	await _frames()


func _check_enemy_motion() -> void:
	_battle()
	var original: Dictionary = DataLoader.records["pirate_light"]["movement"].duplicate(true)
	var settings: Dictionary = original.duplicate(true)
	settings["cone_base"] = 0.0
	settings["cone_slope_base"] = 0.25
	DataLoader.records["pirate_light"]["movement"] = settings
	var combat: Dictionary = GameState.state["combat"]
	combat["player"]["pos"] = [14, 12]
	combat["player"]["facing"] = 6
	combat["opponent"]["pos"] = [8, 12]
	combat["opponent"]["facing"] = 2
	for actor: String in ["player", "opponent"]:
		combat["movement"][actor] = State.new_turn(combat[actor])
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await _frames()
	var turn: Dictionary = combat["movement"]["opponent"]
	var target: Vector2i = Vector2i(12, 13)
	var path: Array[Vector2i] = Routes.path(combat["opponent"], target, turn, 5, settings, Vector2i(14, 12))
	turn["history"].append({"pos": [8, 12], "move_points": 5, "facing": 2})
	combat["opponent"]["facing"] = Routes.arrival_facing(path)
	combat["opponent"]["pos"] = Math.coordinates(target)
	EffectApplier.combat_changed.emit()
	var board: Node3D = view.find_child("Board", true, false)
	_check(board.is_animating() and not path.is_empty(), "An enemy maneuver uses the shared cell route")
	await _follow_animation(board, board.get_node("EnemyShip"), path)
	var enemy_bow: Vector2 = Vector2(-sin(board.get_node("EnemyShip").rotation.y), -cos(board.get_node("EnemyShip").rotation.y))
	_check(enemy_bow.dot(Movement.heading(Routes.arrival_facing(path))) > 0.9999, "The enemy's bow follows its final route segment")
	_check(GameState.restore(GameState.serialize()) == OK, "The enemy's curved maneuver remains saveable")
	var player_path: Array[Vector2i] = Conditions.combat_move_path(Vector2i(11, 12))
	_check(EffectApplier.move_combat(Vector2i(11, 12)) == OK, "The player can later occupy a cell from the enemy's earlier route")
	await _follow_animation(board, board.get_node("PlayerShip"), player_path)
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://enemy-route-facing.json") == OK and GameState.load_game("user://enemy-route-facing.json") == OK and GameState.serialize() == snapshot, "Enemy history uses the player's position at that turn when validating a later save")
	view.queue_free()
	await _frames()
	DataLoader.records["pirate_light"]["movement"] = original


func _follow_animation(board: Node3D, ship: Node3D, path: Array[Vector2i]) -> void:
	var stays_on_route: bool = true
	var moved: bool = false
	var start: Vector3 = ship.position
	var frames: int = 0
	while board.is_animating() and frames < 1200:
		await get_tree().process_frame
		frames += 1
		moved = moved or ship.position.distance_to(start) > 0.05
		var distance: float = INF
		for index: int in range(1, path.size()):
			var a: Vector3 = Math.world_position(Math.coordinates(path[index - 1]))
			var b: Vector3 = Math.world_position(Math.coordinates(path[index]))
			distance = minf(distance, ship.position.distance_to(Geometry3D.get_closest_point_to_segment(ship.position, a, b)))
		stays_on_route = stays_on_route and distance < 0.001
	_check(stays_on_route and moved and not board.is_animating(), "Every animated frame follows the accepted cell path")


func _check_legacy_undo() -> void:
	_battle()
	GameState.state["ship"]["movement"]["cone_base"] = 0.0
	GameState.state["ship"]["movement"]["cone_slope_base"] = 0.2
	var combat: Dictionary = GameState.state["combat"]
	combat["movement"]["player"]["history"].append({"pos": [8, 12], "move_points": 6})
	combat["player"]["pos"] = [13, 13]
	combat["move_points"] = 0
	combat["opponent"]["pos"] = [13, 12]
	combat["movement"]["opponent"] = State.new_turn(combat["opponent"])
	_check(GameState.restore(GameState.serialize()) == OK, "A legacy straight-line maneuver remains loadable")
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await _frames()
	var board: Node3D = view.find_child("Board", true, false)
	_check(EffectApplier.undo_combat_move() == OK, "An old maneuver can still be undone when no legal cell route exists")
	_check(board.get_node("PlayerShip").position.is_equal_approx(Math.world_position([8, 12])) and not board.is_animating(), "A legacy undo resynchronizes the model instead of leaving it at an obsolete cell")
	view.queue_free()
	await _frames()


func _check_facing_history() -> void:
	_battle()
	GameState.state["heroines"]["pilot"]["mood"] = 50.0
	GameState.state["ship"]["movement"]["cone_base"] = 0.0
	GameState.state["ship"]["movement"]["cone_slope_base"] = 0.4
	var combat: Dictionary = GameState.state["combat"]
	combat["movement"]["player"]["history"] = [{"pos": [8, 12], "move_points": 6}]
	combat["player"]["pos"] = [11, 13]
	combat["player"]["facing"] = 2
	combat["move_points"] = 2
	_check(GameState.restore(GameState.serialize()) == OK, "An old history record is migrated on load")
	combat = GameState.state["combat"]
	_check(combat["movement"]["player"]["history"][0] == {"pos": [8, 12], "move_points": 6, "facing": 2} and combat["player"]["facing"] == 2, "Legacy migration preserves the original recorded ship course")
	_check(EffectApplier.use_combat_ability("emergency_burn") == OK and EffectApplier.move_combat(Vector2i(14, 14)) == OK, "A migrated battle accepts a new curved maneuver")
	_check(combat["player"]["facing"] == 3 and combat["movement"]["player"]["history"][1]["facing"] == 2, "The new record captures the pre-move course and the ship takes its arrival course")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://mixed-facing-history.json") == OK and GameState.load_game("user://mixed-facing-history.json") == OK and GameState.serialize() == snapshot, "Migrated and newly recorded maneuvers persist together")
	for invalid_facing: Variant in [-1, 8, 1.5, "2", null, NAN, INF]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["combat"]["movement"]["player"]["history"][0]["facing"] = invalid_facing
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Malformed history courses are rejected atomically")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["combat"]["movement"]["player"]["history"][1]["facing"] = 0
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "A discontinuous saved course is rejected")
	_check(EffectApplier.undo_combat_move() == OK and GameState.state["combat"]["player"]["pos"] == [11, 13] and GameState.state["combat"]["player"]["facing"] == 2 and GameState.state["combat"]["move_points"] == 5, "Undo restores the exact course captured before the new maneuver")
	_check(EffectApplier.undo_combat_move() == OK and GameState.state["combat"]["player"]["pos"] == [8, 12] and GameState.state["combat"]["player"]["facing"] == 2 and GameState.state["combat"]["move_points"] == 9, "Undo also restores the migrated maneuver and preserves the purchased burn")
	_check(GameState.restore(GameState.serialize()) == OK, "The fully undone migrated battle remains valid")


func _click_at(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-combat-routes" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/combat-route-" + suffix + ".png") == OK, "The route " + suffix + " renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
