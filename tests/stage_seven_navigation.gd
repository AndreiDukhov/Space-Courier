extends Node

const AI = preload("res://scripts/combat_ai.gd")
const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Routes = preload("res://scripts/combat_routes.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const State = preload("res://scripts/combat_state.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const SAVE_PATH: String = "res://.godot/navigation-save.json"

var check_count: int = 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Navigation changes load without data errors")
	_check_edges()
	_check_approach()
	_check_multiple_turns()
	_check_edge_state()
	await _check_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Combat navigation checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _settings() -> Dictionary:
	return DataLoader.get_record("ship_main")["movement"]


func _check_edges() -> void:
	var settings: Dictionary = _settings()
	var width: int = Math.WIDTH
	var height: int = Math.HEIGHT
	_check(width == 32 and height == 24, "The combat map is enlarged to 32 by 24 cells")
	var cells: Array[Vector2i] = [Vector2i(width / 2, 0), Vector2i(width / 2, height - 1), Vector2i(0, height / 2), Vector2i(width - 1, height / 2), Vector2i(0, 0), Vector2i(width - 1, 0), Vector2i(0, height - 1), Vector2i(width - 1, height - 1)]
	var occupied: Vector2i = Vector2i(width / 2, height / 2)
	for origin: Vector2i in cells:
		for facing: int in range(8):
			var vessel: Dictionary = {"pos": Math.coordinates(origin), "facing": facing}
			var turn: Dictionary = State.new_turn(vessel)
			var count: int = 0
			for direction: Vector2i in Movement.DIRECTIONS:
				if Conditions.can_move_vessel(vessel, origin + direction, turn, 6, settings, occupied):
					count += 1
			_check(count > 0, "A ship can leave an edge or corner with any heading: %s facing %d" % [origin, facing])
	for distance: int in range(5):
		var origin: Vector2i = Vector2i(width / 2, distance)
		var expected: int = 0 if distance > 3 else mini(3, 4 - distance)
		_check(Movement.edge_turn_bonus(origin, 0) == expected, "Boundary steering increases gradually as the bow approaches the edge")
	var center: Vector2i = Vector2i(width / 2, height / 2)
	var center_ship: Dictionary = {"pos": Math.coordinates(center), "facing": 0}
	_check(Movement.edge_turn_bonus(center, 0) == 0 and not Conditions.can_move_vessel(center_ship, center + Vector2i.DOWN, State.new_turn(center_ship), 6, settings, Vector2i(0, 0)), "Ordinary open-space movement still prohibits flying backward")
	var edge: Vector2i = Vector2i(width / 2, 0)
	var vessel: Dictionary = {"pos": Math.coordinates(edge), "facing": 0}
	_check(Conditions.can_move_vessel(vessel, edge + Vector2i.DOWN, State.new_turn(vessel), 1, settings, occupied) and Movement.next_facing(edge, edge + Vector2i.DOWN, 0, settings) == 4, "A ship pointed out of the map can turn inward with actual movement")
	_check(not Conditions.can_move_vessel(vessel, edge, State.new_turn(vessel), 6, settings, occupied), "Boundary assistance never authorizes a turn without changing cells")
	var detour: Array[Vector2i] = Routes.path(vessel, edge + Vector2i(0, 2), State.new_turn(vessel), 6, settings, edge + Vector2i.DOWN)
	_check(not detour.is_empty(), "Boundary assistance can find a cell route around the opponent")
	var blocked: Array[Vector2i] = [edge + Vector2i.DOWN]
	for index: int in range(1, detour.size()):
		_check(Movement.clear_segment(detour[index - 1], detour[index], blocked), "Each assisted route leg avoids the opponent")
	_check(Conditions.can_move_vessel(vessel, edge + Vector2i.RIGHT, State.new_turn(vessel), 1, settings, edge + Vector2i.DOWN), "A blocked inward cell leaves an assisted route along the edge")


func _follow(vessel: Dictionary, target: Dictionary, path: Array[Vector2i], settings: Dictionary) -> Dictionary:
	var result: Dictionary = vessel.duplicate(true)
	var turn: Dictionary = State.new_turn(vessel)
	var remaining: int = 5
	for cell: Vector2i in path:
		var route: Array[Vector2i] = Conditions.vessel_move_path(result, cell, turn, remaining, settings, Math.cell(target["pos"]))
		_check(not route.is_empty(), "Pursuit obeys shared movement and collision rules")
		remaining -= Movement.cost(Math.cell(result["pos"]), cell)
		result["facing"] = Routes.arrival_facing(route)
		result["pos"] = Math.coordinates(cell)
	return result


func _check_approach() -> void:
	var settings: Dictionary = _settings()
	var vessel: Dictionary = {"pos": [16, 21], "facing": 0}
	var target: Dictionary = {"pos": [16, 1], "facing": 4}
	var guns: Array[Dictionary] = [DataLoader.get_record("cannon_s")]
	var path: Array[Vector2i] = AI.plan(vessel, State.new_turn(vessel), 5, settings, target, guns)
	var result: Dictionary = _follow(vessel, target, path, settings)
	_check(not path.is_empty() and Math.distance(Math.cell(result["pos"]), Math.cell(target["pos"])) < 20.0 and AI.firing_order(result, target, guns, 6).is_empty(), "An out-of-range enemy advances even though this turn still cannot produce a shot")
	vessel = {"pos": [10, 8], "facing": 1}
	target = {"pos": [1, 14], "facing": 0}
	guns = [DataLoader.get_record("course_cannon")]
	path = AI.plan(vessel, State.new_turn(vessel), 5, settings, target, guns)
	_check(not path.is_empty(), "The reproduced northeast-course stall now produces a maneuver")
	result = _follow(vessel, target, path, settings)
	_check(result["pos"] != vessel["pos"] or result["facing"] != vessel["facing"], "The fallback route makes positional or heading progress")


func _check_multiple_turns() -> void:
	var settings: Dictionary = _settings()
	var target: Dictionary = {"pos": [29, 2], "facing": 5}
	for profile: Array in DataLoader.get_record("pirate_light")["loadouts"]:
		var guns: Array[Dictionary] = Loadouts.weapons("pirate_light", profile)
		for facing: int in [0, 1, 4, 6]:
			var vessel: Dictionary = {"pos": [2, 20], "facing": facing}
			var reached: bool = false
			for _turn: int in range(14):
				if not AI.firing_order(vessel, target, guns, 6).is_empty():
					reached = true
					break
				var path: Array[Vector2i] = AI.plan(vessel, State.new_turn(vessel), 5, settings, target, guns)
				if path.is_empty():
					break
				vessel = _follow(vessel, target, path, settings)
			_check(reached, "A distant enemy eventually reaches a firing sector with profile %s and initial heading %d" % [profile, facing])


func _start() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["flight"]["pos"] = GameState.state["flight"]["npcs"]["npc_earth_pirate"]["pos"].duplicate()
	GameState.state["flight"]["pos"][0] -= 20.0
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] = ["cannon_s"]
	EffectApplier.start_flight_event("event_pirate_test")
	EffectApplier.choose_flight_event("event_pirate_test", 0)


func _place(actor: String, cell: Vector2i, facing: int) -> void:
	var combat: Dictionary = GameState.state["combat"]
	combat[actor]["pos"] = Math.coordinates(cell)
	combat[actor]["facing"] = facing
	combat["movement"][actor] = State.new_turn(combat[actor])


func _check_edge_state() -> void:
	_start()
	var edge: Vector2i = Vector2i(Math.WIDTH / 2, 0)
	_place("player", edge, 0)
	_check(EffectApplier.move_combat(edge + Vector2i.DOWN) == OK and GameState.state["combat"]["player"]["facing"] == 4 and GameState.state["combat"]["move_points"] == 5, "The player can escape the edge through the actual move command")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK and GameState.serialize() == snapshot, "An assisted turn and its history survive exact save/load")
	_check(EffectApplier.undo_combat_move() == OK and GameState.state["combat"]["player"]["pos"] == Math.coordinates(edge) and GameState.state["combat"]["player"]["facing"] == 0 and GameState.state["combat"]["move_points"] == 6, "Undo restores the edge position, heading and movement")
	_check(GameState.restore(GameState.serialize()) == OK, "The undone assisted maneuver remains a valid state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _click(view: Control, cell: Vector2i) -> void:
	var camera: Camera3D = view.find_child("Camera", true, false)
	var space: SubViewportContainer = view.find_child("SpaceContainer", true, false)
	var position: Vector3 = Math.world_position(Math.coordinates(cell))
	position.y = 0
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.position = camera.unproject_position(position)
	if DisplayServer.get_name() == "headless":
		space.gui_input.emit(click)
	else:
		click.position += space.global_position
		click.global_position = click.position
		get_viewport().push_input(click, true)
		click.pressed = false
		click.button_mask = 0
		get_viewport().push_input(click, true)


func _check_view() -> void:
	_start()
	var edge: Vector2i = Vector2i(Math.WIDTH / 2, 0)
	_place("player", edge, 0)
	var view: Control = load("res://scenes/combat.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var board: Node3D = view.find_child("Board", true, false)
	_check(board.get_node("Tiles").get_child_count() == 768 and "180" in view.find_child("TargetInfo", true, false).text, "The larger board renders and the boundary steering bonus is visible")
	await _capture("edge")
	_click(view, edge + Vector2i.DOWN)
	_check(board.is_animating() and GameState.state["combat"]["player"]["facing"] == 4, "A grid click starts the assisted inward maneuver")
	await _idle(view)
	var vessel: Node3D = board.get_node("PlayerShip")
	_check(vessel.position.is_equal_approx(Math.world_position(Math.coordinates(edge + Vector2i.DOWN))) and absf(angle_difference(vessel.rotation.y, PI)) < 0.001, "The model finishes the escape at the correct cell and heading")
	view.find_child("Undo", true, false).pressed.emit()
	await _idle(view)
	_check(GameState.state["combat"]["player"]["pos"] == Math.coordinates(edge), "The rendered assisted maneuver can be undone")
	_place("player", Vector2i(7, 8), 2)
	_place("opponent", Vector2i(13, 8), 6)
	_check(GameState.restore(GameState.serialize()) == OK, "Positions from the previous 20 by 16 board remain loadable")
	var camera: Camera3D = view.find_child("Camera", true, false)
	var screen: Vector2 = camera.unproject_position(Math.world_position([7, 8]))
	_check(Rect2(Vector2.ZERO, Vector2(camera.get_viewport().size)).has_point(screen), "Loading recenters the camera on the restored player")
	view.queue_free()
	await get_tree().process_frame
	await _check_loop_animation()


func _check_loop_animation() -> void:
	_start()
	var origin: Vector2i = Vector2i(Math.WIDTH - 2, 1)
	_place("player", Vector2i(Math.WIDTH - 6, 6), 0)
	_place("opponent", origin, 1)
	var view: Control = load("res://scenes/combat.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var combat: Dictionary = GameState.state["combat"]
	var turn: Dictionary = combat["movement"]["opponent"]
	var next: Vector2i = origin + Vector2i.RIGHT
	var settings: Dictionary = DataLoader.get_record("pirate_light")["movement"]
	_check(Conditions.can_move_vessel(combat["opponent"], next, turn, 5, settings, Math.cell(combat["player"]["pos"])), "The first leg of an edge loop is a legal maneuver")
	turn["history"].append({"pos": Math.coordinates(origin), "move_points": 5, "facing": int(combat["opponent"]["facing"])})
	combat["opponent"]["facing"] = Movement.next_facing(origin, next, 1, settings)
	combat["opponent"]["pos"] = Math.coordinates(next)
	_check(Conditions.can_move_vessel(combat["opponent"], origin, turn, 4, settings, Math.cell(combat["player"]["pos"])), "The returning leg uses the boundary steering allowance")
	turn["history"].append({"pos": Math.coordinates(next), "move_points": 4, "facing": int(combat["opponent"]["facing"])})
	combat["opponent"]["facing"] = Movement.next_facing(next, origin, int(combat["opponent"]["facing"]), settings)
	combat["opponent"]["pos"] = Math.coordinates(origin)
	EffectApplier.combat_changed.emit()
	_check(view.find_child("Board", true, false).is_animating(), "A legal enemy loop is animated even when its final cell is unchanged")
	await _idle(view)
	var vessel: Node3D = view.find_child("EnemyShip", true, false)
	_check(absf(angle_difference(vessel.rotation.y, PI / 2.0)) < 0.001 and GameState.restore(GameState.serialize()) == OK, "The enemy loop finishes facing west and remains saveable")
	view.queue_free()
	await get_tree().process_frame


func _idle(view: Control) -> void:
	for _step: int in range(100):
		if not view.find_child("Board", true, false).is_animating():
			return
		await get_tree().create_timer(0.05).timeout
	_check(false, "Navigation animation completes in bounded time")


func _capture(suffix: String) -> void:
	if "--capture-navigation" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty() and image.save_png("res://.godot/navigation-" + suffix + ".png") == OK, "The boundary maneuver screenshot is rendered and saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
