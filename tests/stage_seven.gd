extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const State = preload("res://scripts/combat_state.gd")
const Validator = preload("res://scripts/data_validator.gd")
const SAVE_PATH: String = "res://.godot/stage-seven-save.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Revised combat content loads without errors")
	_check_cone_examples()
	_check_movement()
	_check_weapons()
	_check_shots()
	_check_abilities_and_results()
	_check_default_battle()
	_check_persistence()
	_check_validation()
	await _check_view()
	await _check_scene_flow()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 7 revised checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _fresh() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()


func _start() -> void:
	_fresh()
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] = ["cannon_s"]
	GameState.state["flight"]["pos"] = GameState.state["flight"]["npcs"]["npc_earth_pirate"]["pos"].duplicate()
	GameState.state["flight"]["pos"][0] -= 20.0
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "A JSON encounter starts the revised battle")
	GameState.state["combat"]["player"]["pos"] = [13, 12]
	GameState.state["combat"]["opponent"]["pos"] = [19, 12]
	for actor: String in ["player", "opponent"]:
		GameState.state["combat"]["movement"][actor] = State.new_turn(GameState.state["combat"][actor])


func _cone_cells(origin: Vector2i, turn_origin: Vector2i, facing: int, points: int, settings: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z: int in range(-20, 21):
		for x: int in range(-20, 21):
			var target: Vector2i = Vector2i(x, z)
			if Movement.cone_contains(origin, target, turn_origin, facing, points, settings):
				result.append(target)
	return result


func _check_cone_examples() -> void:
	var settings: Dictionary = DataLoader.get_record("ship_main")["movement"]
	_check(_cone_cells(Vector2i.ZERO, Vector2i.ZERO, 0, 8, settings).size() == 38, "The supplied level-zero cone example has exactly 38 cells")
	settings["maneuver_level"] = 3
	_check(_cone_cells(Vector2i.ZERO, Vector2i.ZERO, 0, 8, settings).size() == 50, "The supplied level-three cone example has exactly 50 cells")
	settings["maneuver_level"] = 0
	var origin: Vector2i = Vector2i(2, -3)
	var with_inertia: Array[Vector2i] = _cone_cells(origin, Vector2i.ZERO, 0, 4, settings)
	_check(with_inertia.size() == 8 and Movement.cost(Vector2i.ZERO, origin) == 4, "The supplied lateral move leaves exactly eight fixed-course cells")
	settings["inertia_base"] = 0.0
	settings["inertia_min"] = 0.0
	var without_inertia: Array[Vector2i] = _cone_cells(origin, Vector2i.ZERO, 0, 4, settings)
	_check(without_inertia.size() == 12, "Disabling inertia restores the twelve-cell reference cone")
	for excluded: Vector2i in [Vector2i(0, -6), Vector2i(1, -4), Vector2i(1, -5), Vector2i(1, -6)]:
		_check(excluded in without_inertia and excluded not in with_inertia, "The documented opposite-side cell is excluded by inertia")
	var blocked: Array[Vector2i] = [Vector2i(0, -2)]
	_check(not Movement.clear_segment(Vector2i.ZERO, Vector2i(0, -4), blocked) and Movement.clear_segment(Vector2i.ZERO, Vector2i(2, -4), blocked), "A straight movement path cannot cross an occupied cell")


func _check_movement() -> void:
	_start()
	var combat: Dictionary = GameState.state["combat"]
	_check(Math.WIDTH == 32 and Math.HEIGHT == 24 and combat["ap"] == 6 and combat["move_points"] == 6, "The board doubles in both dimensions and retains separate AP and movement")
	_check(combat["player"]["facing"] == 2 and combat["opponent"]["facing"] == 6, "Eight-direction spawn headings reflect the encounter sides")
	var before: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(5.0)
	_check(GameState.serialize() == before and not Conditions.can_open_flight_map() and not Conditions.can_dock(), "Battle still freezes flight and blocks world navigation")
	for target: Vector2i in [Vector2i(12, 12), Vector2i(13, 13), Vector2i(19, 12), Vector2i(-1, 8)]:
		_check(EffectApplier.move_combat(target) == ERR_UNAVAILABLE and GameState.serialize() == before, "Backward, sideways, occupied or off-board movement is rejected")
	_check(not EffectApplier.has_method("turn_combat"), "There is no turn-in-place command")
	_check(EffectApplier.move_combat(Vector2i(15, 13)) == OK and combat["move_points"] == 3 and combat["ap"] == 6 and combat["player"]["facing"] == 3, "A diagonal maneuver costs ceil(distance) and immediately turns ship and cone")
	_check(not Conditions.can_move_combat(Vector2i(16, 13)), "The next cone uses the new southeast heading")
	GameState.state["heroines"]["pilot"]["mood"] = 100.0
	_check(EffectApplier.use_combat_ability("emergency_burn") == OK and combat["move_points"] == 7, "High-mood burn adds four movement points during a maneuver sequence")
	_check(EffectApplier.move_combat(Vector2i(16, 14)) == OK and combat["move_points"] == 5, "Further movement follows the rotated cone and costs two points")
	_check(EffectApplier.undo_combat_move() == OK and combat["player"]["pos"] == [15, 13] and combat["player"]["facing"] == 3 and combat["move_points"] == 7, "Undo restores the prior cell and heading")
	_check(EffectApplier.undo_combat_move() == OK and combat["player"]["pos"] == [13, 12] and combat["player"]["facing"] == 2 and combat["move_points"] == 10, "Undo preserves a burn purchased after the original move")
	_check(not Conditions.can_undo_combat_move() and EffectApplier.undo_combat_move() == ERR_UNAVAILABLE, "Undo history ends at the turn origin")
	EffectApplier.end_combat_turn()
	_check(combat["round"] == 2 and combat["ap"] == 6 and combat["move_points"] == 6 and not Conditions.can_undo_combat_move(), "Ending the turn clears undo history and temporary movement")
	_check(GameState.restore(GameState.serialize()) == OK, "Enemy movement uses the same cone rules and leaves a valid saved history")
	_fresh()
	GameState.state["location"] = "hub_office"
	EffectApplier.accept_order("ord_private_01")
	EffectApplier.accept_order("ord_state_01")
	_check(Math.movement_budget() == 5, "Reserved cargo continues reducing movement by floor(mass / 4)")


func _check_weapons() -> void:
	_start()
	_check(Math.player_weapons().size() == 3 and GameState.state["ship"]["slots"]["turret"] == 1 and GameState.state["ship"]["slots"]["course"] == 1 and GameState.state["ship"]["slots"]["broadside"] == 1, "The test loadout has all three weapon mounts")
	var player: Dictionary = GameState.state["combat"]["player"]
	var origin: Vector2i = Math.cell(player["pos"])
	var turret: Dictionary = DataLoader.get_record("cannon_s")
	var course: Dictionary = DataLoader.get_record("course_cannon")
	var broadside: Dictionary = DataLoader.get_record("broadside_plasma")
	_check(Math.in_arc(origin, origin + Vector2i(2, 0), 2, turret) and Math.in_arc(origin, origin + Vector2i(0, 2), 2, turret) and not Math.in_arc(origin, origin + Vector2i(-2, 0), 2, turret), "The turret covers front and sides but excludes the stern")
	_check(Conditions.can_shoot_combat("course_cannon", Vector2i(19, 12)) and not Conditions.can_shoot_combat("cannon_s", Vector2i(19, 12)), "A distant straight target is in course range but outside short turret range")
	_check(Math.in_arc(origin, Vector2i(19, 12), 2, course) and not Math.in_arc(origin, Vector2i(19, 13), 2, course), "The straight course weapon rejects a neighboring off-axis target")
	course["arc_degrees"] = 20
	_check(Math.in_arc(origin, Vector2i(19, 13), 2, course), "A narrow-cone course variant can be configured through JSON")
	_check(Math.in_arc(origin, origin + Vector2i(0, 3), 2, broadside) and Math.in_arc(origin, origin + Vector2i(0, -3), 2, broadside) and not Math.in_arc(origin, origin + Vector2i(3, 0), 2, broadside) and not Math.in_arc(origin, origin + Vector2i(-3, 0), 2, broadside), "Broadside weapons cover both flanks but exclude bow and stern")
	for facing: int in range(8):
		_check(Math.in_arc(Vector2i(10, 8), Vector2i(10, 8) + Movement.DIRECTIONS[facing] * 2, facing, DataLoader.get_record("course_cannon")), "The course firing line rotates correctly in all eight headings")
	GameState.state["heroines"]["security"]["mood"] = 0.0
	var low: float = Math.shot_chance(player, Vector2i(19, 12), course, true)
	GameState.state["heroines"]["security"]["mood"] = 100.0
	var high: float = Math.shot_chance(player, Vector2i(19, 12), course, true)
	_check(is_equal_approx(high - low, 0.3), "Security mood changes accuracy by the JSON crew modifier")
	GameState.state["ship"]["hull"]["current"] = 50.0
	_check(is_equal_approx(high - Math.shot_chance(player, Vector2i(19, 12), course, true), 0.125), "Half hull applies half of the configured hull penalty")
	var unaffected: float = Math.shot_chance(player, Vector2i(19, 12), course, true)
	GameState.state["heroines"]["medic"]["mood"] = 0.0
	_check(Math.shot_chance(player, Vector2i(19, 12), course, true) == unaffected and DataLoader.get_record("mechanic").is_empty(), "Other heroines do not affect gunnery and no mechanic was added")
	GameState.state["heroines"]["security"]["aboard"] = false
	_check(Math.security_mood() == 50.0 and GameState.state["heroines"]["security"]["loc"] == "ship_bridge", "An absent security officer provides a neutral modifier; her test schedule is on the ship")


func _force_weapon(weapon_id: String, chance: float, critical: float, damage: int) -> Dictionary:
	var original: Dictionary = DataLoader.records[weapon_id].duplicate(true)
	DataLoader.records[weapon_id]["accuracy"] = {"close": chance, "far": chance, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
	DataLoader.records[weapon_id]["critical"] = {"chance": critical, "multiplier": 2.0}
	DataLoader.records[weapon_id]["dmg"] = [damage, damage]
	DataLoader.records[weapon_id]["ap_cost"] = 2
	DataLoader.records[weapon_id]["range"] = 40
	return original


func _check_shots() -> void:
	_start()
	var original: Dictionary = _force_weapon("course_cannon", 1.0, 0.0, 10)
	var combat: Dictionary = GameState.state["combat"]
	var target: Vector2i = Math.cell(combat["opponent"]["pos"])
	_check(EffectApplier.shoot_combat("course_cannon", target) == OK and combat["last_shot"]["result"] == "hit" and combat["opponent"]["shield"] == 5 and combat["opponent"]["hull"] == 30 and combat["ap"] == 4, "The chosen weapon hits the chosen cell and applies shield damage")
	var after_shot: Dictionary = GameState.serialize()
	_check(EffectApplier.shoot_combat("course_cannon", target) == ERR_UNAVAILABLE and GameState.serialize() == after_shot, "A weapon cannot fire twice in the same turn")
	EffectApplier.end_combat_turn()
	EffectApplier.shoot_combat("course_cannon", Math.cell(combat["opponent"]["pos"]))
	EffectApplier.end_combat_turn()
	_check(EffectApplier.shoot_combat("course_cannon", Math.cell(combat["opponent"]["pos"])) == OK and combat["opponent"]["hull"] == 20, "Shots across separate turns reach hull after depleting shields")
	DataLoader.records["course_cannon"] = original.duplicate(true)
	_start()
	original = _force_weapon("course_cannon", 1.0, 1.0, 10)
	GameState.state["combat"]["opponent"]["shield"] = 0.0
	_check(EffectApplier.shoot_combat("course_cannon", Vector2i(19, 12)) == OK and GameState.state["combat"]["last_shot"]["result"] == "critical" and GameState.state["combat"]["last_shot"]["damage"] == 20, "A critical hit multiplies damage and is recorded distinctly")
	DataLoader.records["course_cannon"] = original.duplicate(true)
	_start()
	original = _force_weapon("course_cannon", 0.0, 1.0, 10)
	_check(EffectApplier.shoot_combat("course_cannon", Vector2i(19, 12)) == OK and GameState.state["combat"]["last_shot"]["result"] == "miss" and GameState.state["combat"]["last_shot"]["damage"] == 0, "Zero accuracy always misses and cannot produce a critical")
	DataLoader.records["course_cannon"] = original.duplicate(true)
	_start()
	original = _force_weapon("course_cannon", 1.0, 0.0, 10)
	var before_target: Dictionary = GameState.state["combat"]["opponent"].duplicate(true)
	_check(EffectApplier.shoot_combat("course_cannon", Vector2i(14, 12)) == OK and GameState.state["combat"]["opponent"] == before_target and GameState.state["combat"]["last_shot"]["result"] == "miss", "A legal shot at an empty cell spends AP and cannot auto-target the enemy")
	_check(Math.shot_chance(GameState.state["combat"]["player"], Vector2i(14, 12), DataLoader.get_record("course_cannon"), true) == 0.0, "The hit preview for an empty cell is zero")
	DataLoader.records["course_cannon"] = original.duplicate(true)
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.shoot_combat("missing", Vector2i(19, 12)) == ERR_UNAVAILABLE and EffectApplier.shoot_combat("course_cannon", Vector2i(-1, 8)) == ERR_UNAVAILABLE and GameState.serialize() == before, "Missing weapons and invalid target cells cannot consume AP")
	_check(Math.damage(30, 2, 10, "laser") == {"hull": 24.0, "shield": 0.0}, "Laser damage still applies its hull multiplier after shield spillover")
	_start()
	GameState.state["combat"]["opponent"]["pos"] = [13, 15]
	GameState.state["combat"]["movement"]["opponent"] = State.new_turn(GameState.state["combat"]["opponent"])
	original = _force_weapon("broadside_plasma", 1.0, 0.0, 10)
	_check(EffectApplier.shoot_combat("broadside_plasma", Vector2i(13, 15)) == OK and GameState.state["combat"]["last_shot"]["weapon"] == "broadside_plasma" and GameState.state["combat"]["opponent"]["shield"] == 0, "The broadside weapon fires at an actual flank target")
	DataLoader.records["broadside_plasma"] = original.duplicate(true)


func _win() -> void:
	var original: Dictionary = _force_weapon("cannon_s", 1.0, 0.0, 200)
	DataLoader.records["cannon_s"]["arc_degrees"] = 360
	EffectApplier.shoot_combat("cannon_s", Math.cell(GameState.state["combat"]["opponent"]["pos"]))
	DataLoader.records["cannon_s"] = original.duplicate(true)


func _lose() -> void:
	var original: Array = DataLoader.records["pirate_light"]["weapons"].duplicate(true)
	for weapon: Dictionary in DataLoader.records["pirate_light"]["weapons"]:
		weapon["accuracy"] = {"close": 1.0, "far": 1.0, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
		weapon["dmg"] = [400, 400]
		weapon["range"] = 40
		weapon["arc_degrees"] = 360
	GameState.state["combat"]["evasion"] = {"value": 0.0, "rounds": 0}
	EffectApplier.end_combat_turn()
	DataLoader.records["pirate_light"]["weapons"] = original.duplicate(true)


func _check_abilities_and_results() -> void:
	_start()
	GameState.state["heroines"]["pilot"]["mood"] = 0.0
	var combat: Dictionary = GameState.state["combat"]
	_check(EffectApplier.use_combat_ability("evasive_maneuver") == OK and is_equal_approx(combat["evasion"]["value"], 0.3), "Pilot mood still scales evasion independently of security accuracy")
	_check(EffectApplier.use_combat_ability("evasive_maneuver") == ERR_UNAVAILABLE, "An active cooldown blocks immediate reuse")
	EffectApplier.end_combat_turn()
	_check(combat["evasion"]["rounds"] == 1 and combat["cooldowns"]["evasive_maneuver"] == 2, "Enemy turns consume evasion duration and cooldown")
	EffectApplier.end_combat_turn()
	_check(combat["evasion"]["rounds"] == 0 and combat["evasion"]["value"] == 0, "Evasion expires after two enemy turns")
	GameState.state["ship"]["fuel"]["current"] = 0.5
	_check(not Conditions.can_use_combat_ability("emergency_burn"), "Burn requires its full fuel cost")
	GameState.state["combat"]["player"]["shield"] = 8.0
	_check(EffectApplier.shield_combat() == OK and combat["player"]["shield"] == 8 and combat["ap"] == 3 and not combat["shield_recharge"].is_empty(), "Shield reboot spends half the full AP budget and queues recovery")
	_check(EffectApplier.shield_combat() == ERR_UNAVAILABLE, "An already pending shield recharge cannot be queued twice")
	var pending: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK and GameState.serialize() == pending, "Pending shield recovery survives saving without an early refill")
	EffectApplier.end_combat_turn()
	_check(GameState.state["combat"]["player"]["shield"] == 10 and GameState.state["combat"]["shield_recharge"].is_empty(), "Shields recover after the enemy acts at the next round")
	_start()
	_win()
	var loot: Dictionary = GameState.state["combat"]["loot"].duplicate(true)
	_check(GameState.state["combat"]["result"] == "victory" and not Conditions.can_act_combat(), "A lethal selected shot produces victory")
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK, "A victory and its recorded loot can be saved and loaded")
	var money: int = int(GameState.state["money"])
	_check(EffectApplier.finish_combat() == OK and GameState.state["money"] == money + int(loot["money"]) and not Conditions.npc_is_active("npc_earth_pirate"), "Victory pays the recorded loot and removes the source ship")
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.finish_combat() == ERR_UNAVAILABLE and GameState.serialize() == before, "Repeated result delivery cannot pay twice")
	_start()
	GameState.state["money"] = 0
	_lose()
	_check(GameState.state["combat"]["result"] == "defeat" and GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK, "A defeat can be saved with zero hull")
	_check(EffectApplier.finish_combat() == OK and GameState.state["money"] == -400 and GameState.state["location"] == "hub_office" and GameState.state["ship"]["hull"]["current"] == 100 and Clock.current_day() == 2, "Defeat rescue still prevents a dead end even without money")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check_default_battle() -> void:
	_start()
	seed(1729)
	for _turn: int in range(40):
		if not Conditions.can_act_combat():
			break
		if Conditions.can_use_combat_ability("evasive_maneuver"):
			EffectApplier.use_combat_ability("evasive_maneuver")
		var target: Vector2i = Math.cell(GameState.state["combat"]["opponent"]["pos"])
		while Conditions.can_shoot_combat("course_cannon", target):
			EffectApplier.shoot_combat("course_cannon", target)
		if Conditions.can_act_combat():
			EffectApplier.end_combat_turn()
	_check(GameState.state["combat"]["result"] == "victory", "A battle with unmodified JSON weapons and AI can be won")
	_check(GameState.restore(GameState.serialize()) == OK, "The ordinary battle leaves a valid restorable result")


func _check_persistence() -> void:
	_start()
	EffectApplier.move_combat(Vector2i(15, 13))
	EffectApplier.use_combat_ability("evasive_maneuver")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "A maneuver and its undo history can be saved")
	EffectApplier.end_combat_turn()
	_check(GameState.load_game(SAVE_PATH) == OK and GameState.serialize() == snapshot, "Loading restores exact inertia origin, heading, history and ability state")
	_check(EffectApplier.undo_combat_move() == OK and GameState.state["combat"]["player"]["pos"] == [13, 12], "A restored maneuver can still be undone")
	_check(GameState.restore(snapshot) == OK, "The maneuver snapshot remains valid after undo")
	for field: String in ["enemy", "position", "overlap", "ap", "heading", "mp", "history", "origin", "history_cost", "history_limit", "shot", "shot_owner", "movement_parameters", "source", "defeated", "modules", "orders", "missing_movement"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match field:
			"enemy": invalid["combat"]["enemy"] = "missing"
			"position": invalid["combat"]["player"]["pos"] = [Math.WIDTH, 0]
			"overlap": invalid["combat"]["player"]["pos"] = invalid["combat"]["opponent"]["pos"].duplicate()
			"ap": invalid["combat"]["ap"] = 7
			"heading": invalid["combat"]["player"]["facing"] = 8
			"mp": invalid["combat"]["move_points"] = -1
			"history": invalid["combat"]["movement"]["player"]["history"] = []
			"origin": invalid["combat"]["movement"]["player"]["origin"] = [0, 0]
			"history_cost": invalid["combat"]["movement"]["player"]["history"][0]["move_points"] = 0
			"history_limit": invalid["combat"]["movement"]["player"]["history"][0]["move_points"] = 999
			"shot": invalid["combat"]["last_shot"] = {"shooter": "player", "weapon": "missing", "target": [1, 1], "result": "hit", "damage": 1}
			"shot_owner": invalid["combat"]["last_shot"] = {"shooter": "opponent", "weapon": "course_cannon", "target": [1, 1], "result": "hit", "damage": 1}
			"movement_parameters": invalid["ship"]["movement"]["cone_slope_max"] = NAN
			"source": invalid["combat"]["source_npc"] = "npc_earth_courier"
			"defeated": invalid["flight"]["defeated_npcs"] = ["missing"]
			"modules": invalid["ship"]["modules"] = ["missing"]
			"orders": invalid["orders"] = []
			"missing_movement": invalid["combat"].erase("movement")
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid revised combat save is rejected: " + field)
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The revised combat save is removed")


func _check_validation() -> void:
	for field: String in ["enemy", "weapon_id", "arc", "critical", "modifier", "movement", "age"]:
		var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
		match field:
			"enemy": groups["events"][3]["options"][0]["effects"] = [{"start_combat": "missing"}]
			"weapon_id": groups["enemies"][0]["weapons"][0]["id"] = "missing"
			"arc": groups["modules"][1]["arc_degrees"] = 400
			"critical": groups["modules"][1]["critical"]["chance"] = 2
			"modifier": groups["modules"][1]["accuracy"]["hull_penalty"] = NAN
			"movement": groups["ship"][0]["movement"]["maneuver_level"] = -1
			"age": groups["heroines"][2]["age"] = 20
		_check(not Validator.validate(groups, {}).is_empty(), "DataLoader reports invalid revised combat content: " + field)


func _click(view: Control, cell: Vector2i, native: bool = false) -> void:
	var camera: Camera3D = view.find_child("Camera", true, false)
	var space: SubViewportContainer = view.find_child("SpaceContainer", true, false)
	var point: Vector3 = Math.world_position(Math.coordinates(cell))
	point.y = 0
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = camera.unproject_position(point)
	if native and DisplayServer.get_name() != "headless":
		event.position += space.global_position
		event.global_position = event.position
		get_viewport().push_input(event, true)
		event.pressed = false
		event.button_mask = 0
		get_viewport().push_input(event, true)
	else:
		space.gui_input.emit(event)


func _idle(view: Control) -> void:
	for _step: int in range(60):
		if not view.find_child("Board", true, false).is_animating():
			return
		await get_tree().create_timer(0.05).timeout
	_check(false, "Ship animation finishes in bounded time")


func _check_view() -> void:
	_start()
	var view: Control = load("res://scenes/combat.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var board: Node3D = view.find_child("Board", true, false)
	var camera: Camera3D = view.find_child("Camera", true, false)
	var space: SubViewportContainer = view.find_child("SpaceContainer", true, false)
	_check(board.get_node("Tiles").get_child_count() == Math.WIDTH * Math.HEIGHT and board.get_node("PlayerShip").get_child_count() > 4, "The enlarged 3D board has 768 tiles and a multipart ship model")
	_check(camera.rotation_degrees.x > -65 and camera.rotation_degrees.x < -35 and not view.has_method("_turn"), "The camera is visibly angled and turn-in-place controls are absent")
	var start_position: Vector3 = board.get_node("PlayerShip").position
	_click(view, Vector2i(15, 13), true)
	_check(GameState.state["combat"]["player"]["pos"] == [15, 13] and board.get_node("PlayerShip").position == start_position and board.is_animating(), "A real grid click starts a maneuver without teleporting the model")
	await get_tree().create_timer(0.28).timeout
	var intermediate: Vector3 = board.get_node("PlayerShip").position
	_check(intermediate != start_position and intermediate != Math.world_position([15, 13]), "The model passes through an intermediate position during its smooth move")
	await _idle(view)
	_check(board.get_node("PlayerShip").position.is_equal_approx(Math.world_position([15, 13])), "The model finishes exactly at the selected cell")
	view.find_child("Undo", true, false).pressed.emit()
	await _idle(view)
	_check(GameState.state["combat"]["player"]["pos"] == [13, 12], "The UI undo button restores the prior maneuver")
	view.find_child("Weapon_course_cannon", true, false).pressed.emit()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	var point: Vector3 = Math.world_position([19, 12])
	point.y = 0
	motion.position = camera.unproject_position(point)
	space.gui_input.emit(motion)
	_check("%" in view.find_child("TargetInfo", true, false).text, "Weapon selection and cell hover show hit and critical percentages")
	await _capture("weapons")
	_click(view, Vector2i(19, 12), true)
	_check(GameState.state["combat"]["ap"] == 4 and GameState.state["combat"]["last_shot"]["weapon"] == "course_cannon", "Clicking the selected cell fires the selected weapon")
	await _idle(view)
	var before: Dictionary = GameState.serialize()
	var previous_camera: Vector3 = camera.position
	var drag: InputEventMouseButton = InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_RIGHT
	drag.pressed = true
	drag.position = Vector2(space.size) / 2.0
	space.gui_input.emit(drag)
	motion.position = drag.position + Vector2(50, 30)
	motion.relative = Vector2(50, 30)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	space.gui_input.emit(motion)
	drag.pressed = false
	space.gui_input.emit(drag)
	_check(camera.position != previous_camera and GameState.serialize() == before, "RTS drag pans the camera without moving ships or spending resources")
	var old_zoom: float = camera.size
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = drag.position
	space.gui_input.emit(wheel)
	_check(camera.size < old_zoom, "The mouse wheel zooms the tactical camera")
	for _step: int in range(40):
		space.gui_input.emit(wheel)
	_check(camera.size == 7.0, "Camera zoom has a bounded close limit")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for _step: int in range(40):
		space.gui_input.emit(wheel)
	_check(camera.size == 40.0, "Camera zoom has a bounded distant limit")
	motion.position = Vector2(2, space.size.y / 2.0)
	motion.relative = Vector2.ZERO
	motion.button_mask = 0
	space.gui_input.emit(motion)
	previous_camera = camera.position
	camera._process(0.25)
	_check(camera.position.x < previous_camera.x, "Moving the pointer to the field edge scrolls the RTS camera")
	camera.pan(Vector2(1000, 1000))
	_check(camera.position.x <= Math.WIDTH / 2.0 and camera.position.z <= Math.HEIGHT / 2.0 + 13.0 and GameState.serialize() == before, "Camera panning is clamped and never mutates battle state")
	camera.size = 13.0
	camera.pan(Vector2(-camera.position.x, 13.0 - camera.position.z))
	camera.stop_tracking()
	view.find_child("evasive_maneuver", true, false).pressed.emit()
	if "--probe-combat-user-save" in OS.get_cmdline_user_args() and not FileAccess.file_exists(GameState.SAVE_PATH):
		var snapshot: Dictionary = GameState.serialize()
		view.find_child("Save", true, false).pressed.emit()
		_check(FileAccess.file_exists(GameState.SAVE_PATH), "Combat UI writes actual user://save.json")
		EffectApplier.end_combat_turn()
		view.find_child("Load", true, false).pressed.emit()
		_check(GameState.serialize() == snapshot, "Combat UI restores exact state from the actual user save")
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH)) == OK, "The user-save probe is removed")
	await _capture("models")
	_win()
	_check(view.find_child("Continue", true, false).visible and "Победа" in view.find_child("Result", true, false).text, "A selected weapon kill opens the victory result")
	await _capture("victory")
	await _idle(view)
	view.find_child("Continue", true, false).pressed.emit()
	view.queue_free()
	await get_tree().process_frame


func _check_scene_flow() -> void:
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/boot.tscn")
	var hub: Node = await _wait_scene("Hub")
	_check(hub != null, "The project still boots into the actual hub")
	if hub == null:
		return
	hub.get_node("%Locations/hub_tech/Travel").pressed.emit()
	hub.get_node("TechHotspot/Computer").pressed.emit()
	hub.get_node("%TerminalContent/ComputerMenu/Launch").pressed.emit()
	var flight: Node = await _wait_scene("SystemFlight")
	_check(flight != null, "The normal launch still enters local flight")
	if flight == null:
		return
	flight.set_physics_process(false)
	for _step: int in range(200):
		var event: String = str(GameState.state["flight"]["encounter"])
		if event == "event_pirate_test":
			break
		if not event.is_empty():
			EffectApplier.choose_flight_event(event, 1)
		if GameState.state["flight"]["paused"]:
			EffectApplier.toggle_flight_pause()
		EffectApplier.approach_npc("npc_earth_pirate")
		EffectApplier.advance_flight(0.1)
	_check(GameState.state["flight"]["encounter"] == "event_pirate_test" and not Conditions.can_tick_flight() and flight.get_node("%EncounterLayer").visible, "A pirate interception opens its encounter automatically through normal flight")
	flight.get_node("%FlightEncounter").get_node("%EventChoices/Option0").pressed.emit()
	var combat: Node = await _wait_scene("Combat")
	_check(combat != null, "A real moving-NPC encounter enters the revised 3D combat scene")
	if combat == null:
		return
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK, "The real battle scene can save its revised state")
	_lose()
	await _idle(combat)
	combat.find_child("Continue", true, false).pressed.emit()
	hub = await _wait_scene("Hub")
	_check(hub != null and GameState.state["location"] == "hub_office", "Defeat returns through the real scene transition to the hub")
	_check(GameState.load_game(SAVE_PATH) == OK, "A revised battle can be loaded from the hub")
	combat = await _wait_scene("Combat")
	_check(combat != null and GameState.serialize() == snapshot, "Loading restores the exact revised battle scene and state")
	if combat == null:
		return
	_win()
	await _idle(combat)
	combat.find_child("Continue", true, false).pressed.emit()
	flight = await _wait_scene("SystemFlight")
	_check(flight != null and not flight.get_node("%NPCView").has_node("npc_earth_pirate"), "Victory returns to real flight with the defeated model removed")
	if flight != null:
		flight.set_physics_process(false)
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK, "The scene-flow save is removed")


func _wait_scene(scene_name: String) -> Node:
	for _frame: int in range(90):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == scene_name:
			return get_tree().current_scene
	return null


func _capture(suffix: String) -> void:
	if "--capture-combat" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty() and image.save_png("res://.godot/stage-seven-revised-" + suffix + ".png") == OK, "The revised 3D combat screenshot is rendered and saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
