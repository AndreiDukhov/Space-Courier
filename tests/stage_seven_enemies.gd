extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Routes = preload("res://scripts/combat_routes.gd")
const State = preload("res://scripts/combat_state.gd")
const AI = preload("res://scripts/combat_ai.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const Validator = preload("res://scripts/data_validator.gd")
const SAVE_PATH: String = "res://.godot/enemy-combat-save.json"

var failures: Array[String] = []
var check_count: int = 0
var _explosions: int = 0
var _shown_shots: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Enemy loadouts and weapon data load without errors")
	_check_loadouts()
	_check_fire_limits()
	_check_tactics()
	_check_save_contract()
	_check_data_validation()
	await _check_encounter()
	await _check_fx()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Enemy combat checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _fresh() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["flight"]["pos"] = GameState.state["flight"]["npcs"]["npc_earth_pirate"]["pos"].duplicate()
	GameState.state["flight"]["pos"][0] -= 20.0
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()


func _start(profile: Array = ["cannon_s", "course_cannon", "broadside_plasma"]) -> void:
	_fresh()
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] = profile.duplicate()
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "The encounter starts with the stored enemy loadout")
	GameState.state["combat"]["player"]["pos"] = [13, 12]
	GameState.state["combat"]["opponent"]["pos"] = [19, 12]
	for actor: String in ["player", "opponent"]:
		GameState.state["combat"]["movement"][actor] = State.new_turn(GameState.state["combat"][actor])


func _check_loadouts() -> void:
	var seen: Dictionary = {}
	seed(2048)
	for _roll: int in range(60):
		var ids: Array[String] = Loadouts.roll("pirate_light")
		_check(not ids.is_empty() and Loadouts.valid("pirate_light", ids), "A random enemy always has a configured nonempty loadout")
		seen[JSON.stringify(ids)] = true
	_check(seen.size() == 3, "Random selection can produce turret-only, broadside-only and all-weapons profiles")
	_fresh()
	_check(GameState.state["flight"]["npcs"]["npc_earth_courier"]["weapons"].is_empty(), "A noncombat NPC has no accidental enemy loadout")
	var profile: Array = GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"].duplicate()
	_check(GameState.save_game(SAVE_PATH) == OK, "A pre-encounter enemy loadout can be saved")
	EffectApplier.advance_flight(0.2)
	_check(GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] == profile, "Patrol movement preserves equipment")
	_check(GameState.load_game(SAVE_PATH) == OK and GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] == profile, "Loading does not reroll enemy equipment")
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK and GameState.state["combat"]["opponent"]["weapons"] == profile, "Combat uses exactly the loadout assigned before approach")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _force_weapon(weapon_id: String, chance: float, critical: float = 0.0) -> Dictionary:
	var original: Dictionary = DataLoader.records[weapon_id].duplicate(true)
	DataLoader.records[weapon_id]["accuracy"] = {"close": chance, "far": chance, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
	DataLoader.records[weapon_id]["critical"] = {"chance": critical, "multiplier": 2.0}
	DataLoader.records[weapon_id]["dmg"] = [2, 2]
	return original


func _check_fire_limits() -> void:
	_start()
	_check(GameState.state["combat"]["move_points"] == 6 and DataLoader.get_record("pirate_light")["speed"] == 5, "Both sides receive the increased movement budget")
	for weapon: Dictionary in Math.player_weapons():
		_check(weapon["ap_cost"] == 2, "Every player weapon costs two AP")
	for weapon: Dictionary in Math.enemy_weapons():
		_check(weapon["ap_cost"] == 2, "Every enemy weapon costs the same two AP")
	var original: Dictionary = _force_weapon("course_cannon", 0.0)
	_check(EffectApplier.shoot_combat("course_cannon", Vector2i(19, 12)) == OK and GameState.state["combat"]["ap"] == 4 and GameState.state["combat"]["fired"]["player"] == ["course_cannon"], "A miss spends two AP and consumes the weapon's shot")
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.shoot_combat("course_cannon", Vector2i(19, 12)) == ERR_UNAVAILABLE and GameState.serialize() == before, "A second shot from the same gun is rejected atomically")
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK and not Conditions.can_shoot_combat("course_cannon", Vector2i(19, 12)), "Save/load cannot restore a consumed shot in the same turn")
	DataLoader.records["course_cannon"] = original.duplicate(true)
	EffectApplier.end_combat_turn()
	_check(GameState.state["combat"]["fired"]["player"].is_empty(), "Player weapon shots reset on the next player turn")
	var used: Array = GameState.state["combat"]["fired"]["opponent"]
	var unique: Dictionary = {}
	for weapon_id: String in used:
		unique[weapon_id] = true
	_check(used.size() == unique.size() and used.size() >= 1, "Enemy weapons fire at most once each")
	_check(GameState.state["combat"]["shots"].size() == used.size(), "The enemy volley records every shot, rather than only its last gun")
	if not used.is_empty():
		_check(used[0] == "course_cannon", "A positioned enemy opens with its strongest weapon")
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK, "An enemy volley and spent gun lists can be persisted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _follow(vessel: Dictionary, turn: Dictionary, path: Array[Vector2i], points: int, settings: Dictionary, target: Dictionary) -> Dictionary:
	var result: Dictionary = vessel.duplicate(true)
	for cell: Vector2i in path:
		var route: Array[Vector2i] = Conditions.vessel_move_path(result, cell, turn, points, settings, Math.cell(target["pos"]))
		_check(not route.is_empty(), "Every AI maneuver obeys the same cone, inertia and collision checks")
		points -= Movement.cost(Math.cell(result["pos"]), cell)
		result["facing"] = Routes.arrival_facing(route)
		result["pos"] = Math.coordinates(cell)
	return result


func _check_tactics() -> void:
	_start()
	var settings: Dictionary = DataLoader.get_record("pirate_light")["movement"]
	var weapons: Array[Dictionary] = Math.enemy_weapons()
	var vessel: Dictionary = {"pos": [16, 12], "facing": 0}
	var target: Dictionary = {"pos": [17, 8], "facing": 4}
	var turn: Dictionary = State.new_turn(vessel)
	var path: Array[Vector2i] = AI.plan(vessel, turn, 5, settings, target, weapons)
	var final: Dictionary = _follow(vessel, turn, path, 5, settings, target)
	_check(not path.is_empty() and Conditions.can_fire_weapon(final, target, DataLoader.get_record("course_cannon"), 6), "The enemy finds a reachable firing line for its strongest course gun")
	target = {"pos": [19, 12], "facing": 6}
	var order: Array[Dictionary] = AI.firing_order(vessel, target, weapons, 6)
	_check(not order.is_empty() and order[0]["id"] == "broadside_plasma", "When the strongest gun cannot aim, a stronger eligible secondary precedes the turret")
	_check(AI.plan(vessel, turn, 0, settings, target, weapons).is_empty(), "An enemy with no movement cannot rotate or teleport into a firing sector")
	target = {"pos": [16, 8], "facing": 4}
	var flank_guns: Array[Dictionary] = Loadouts.weapons("pirate_light", ["broadside_plasma"])
	_check(not Conditions.can_fire_weapon(vessel, target, flank_guns[0], 6), "A broadside-only enemy cannot shoot through its bow")
	path = AI.plan(vessel, turn, 5, settings, target, flank_guns)
	final = _follow(vessel, turn, path, 5, settings, target)
	_check(not path.is_empty() and Conditions.can_fire_weapon(final, target, flank_guns[0], 6), "A broadside-only enemy maneuvers to bring its flank to bear")
	target = {"pos": [16, 15], "facing": 0}
	var turret: Dictionary = DataLoader.get_record("cannon_s")
	_check(not Conditions.can_fire_weapon(vessel, target, turret, 6), "The turret's stern blind zone also applies to enemies")
	_check(AI.firing_order(vessel, target, weapons, 6, ["broadside_plasma", "cannon_s", "course_cannon"]).is_empty(), "No enemy gun can fire again after its shot is consumed")


func _check_save_contract() -> void:
	_start()
	EffectApplier.end_combat_turn()
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.restore(snapshot) == OK, "A normal tactical enemy turn produces a valid snapshot")
	for field: String in ["empty_loadout", "unknown_loadout", "changed_loadout", "duplicate_fired", "foreign_fired", "shot_origin", "duplicate_shot", "missing_fired"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match field:
			"empty_loadout": invalid["flight"]["npcs"]["npc_earth_pirate"]["weapons"] = []
			"unknown_loadout": invalid["combat"]["opponent"]["weapons"] = ["missing"]
			"changed_loadout": invalid["combat"]["opponent"]["weapons"] = ["cannon_s"]
			"duplicate_fired": invalid["combat"]["fired"]["player"] = ["cannon_s", "cannon_s"]
			"foreign_fired": invalid["combat"]["fired"]["player"] = ["engine_mk1"]
			"shot_origin": invalid["combat"]["shots"][0]["origin"] = [-1, 0]
			"duplicate_shot": invalid["combat"]["shots"].append(invalid["combat"]["shots"][0].duplicate(true))
			"missing_fired": invalid["combat"].erase("fired")
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid enemy combat save is rejected: " + field)


func _check_data_validation() -> void:
	for field: String in ["empty_profile", "unknown_gun", "duplicate_gun", "unequal_ap", "description"]:
		var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
		match field:
			"empty_profile": groups["enemies"][0]["loadouts"] = [[]]
			"unknown_gun": groups["enemies"][0]["loadouts"] = [["missing"]]
			"duplicate_gun": groups["enemies"][0]["loadouts"] = [["cannon_s", "cannon_s"]]
			"unequal_ap": groups["modules"][2]["ap_cost"] = 3
			"description": groups["enemies"][0]["description"] = 1
		_check(not Validator.validate(groups, {}).is_empty(), "DataLoader catches invalid enemy content: " + field)


func _check_encounter() -> void:
	_fresh()
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] = ["cannon_s", "course_cannon", "broadside_plasma"]
	EffectApplier.start_flight_event("event_pirate_test")
	var flight: Control = load("res://scenes/system_flight.tscn").instantiate()
	add_child(flight)
	flight.set_physics_process(false)
	await get_tree().process_frame
	var encounter: Control = flight.get_node("%FlightEncounter")
	var panel_rect: Rect2 = encounter.get_global_rect()
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	_check(viewport_rect.encloses(panel_rect), "The armed-ship dialog fits inside the viewport")
	var description: String = str(encounter.get_node("%ShipDescription").text)
	_check("Лазган" in description and "Автопушка" in description and "Плазмоган" in description and "Урон" in description, "Before combat the dialog describes the actual three guns and their damage")
	_check(GameState.save_game(SAVE_PATH) == OK, "The open armed-ship encounter can be saved")
	GameState.state["flight"]["npcs"]["npc_earth_pirate"]["weapons"] = ["cannon_s"]
	_check(GameState.load_game(SAVE_PATH) == OK and encounter.get_node("%ShipDescription").text == description, "Loading the same event id refreshes the exact stored loadout description")
	await _capture("encounter")
	GameState.state["money"] = 0
	EffectApplier.flight_changed.emit()
	var before: Dictionary = GameState.serialize()
	_check(encounter.get_node("%EventChoices/Option1").disabled and EffectApplier.choose_flight_event("event_pirate_test", 1) == ERR_UNAVAILABLE and GameState.serialize() == before, "A player without the bribe cannot pay or partially resolve the encounter")
	GameState.state["money"] = 1000
	_check(EffectApplier.choose_flight_event("event_pirate_test", 1) == OK and GameState.state["money"] == 800 and not Conditions.has_combat() and Conditions.event_is_available("event_pirate_test") and GameState.state["flight"]["npcs"]["npc_earth_pirate"]["cooldown"] > 0.0, "Paying the bribe ends the encounter and delays aggression while keeping future interaction available")
	flight.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check_fx() -> void:
	_start(["cannon_s"])
	var view: Control = load("res://scenes/combat.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var board: Node3D = view.find_child("Board", true, false)
	var fx: Node3D = board.get_node("ShotFX")
	fx.explosion_created.connect(func() -> void: _explosions += 1)
	fx.shot_started.connect(func(_shot: Dictionary) -> void: _shown_shots += 1)
	view.find_child("Weapon_course_cannon", true, false).pressed.emit()
	for result: String in ["miss", "hit", "critical"]:
		var original: Dictionary = _force_weapon("course_cannon", 0.0 if result == "miss" else 1.0, 1.0 if result == "critical" else 0.0)
		var before: int = _explosions
		EffectApplier.shoot_combat("course_cannon", Math.cell(GameState.state["combat"]["opponent"]["pos"]))
		_check(board.is_animating() and fx.active and fx.has_node("ShotBeam"), "A shot immediately starts a visible beam and locks combat input")
		_check(view.find_child("Weapon_course_cannon", true, false).disabled and GameState.state["combat"]["fired"]["player"] == ["course_cannon"], "The used gun is disabled while its shot is consumed")
		await get_tree().create_timer(0.08).timeout
		var beam: Node3D = fx.get_node("ShotBeam")
		var beam_mesh: MeshInstance3D = beam.get_child(0)
		var ray: Vector3 = -beam.global_basis.z.normalized() * beam_mesh.mesh.height
		var actual_target: Vector3 = Math.world_position(GameState.state["combat"]["opponent"]["pos"]) + Vector3(0, 0.33, 0)
		var separation: float = (actual_target - beam.global_position).cross(ray).length() / ray.length()
		_check(separation > 0.45 if result == "miss" else separation < 0.001, "A miss beam passes beside the target while a hit beam reaches its center")
		await _capture("beam-" + result)
		if result != "miss":
			await get_tree().create_timer(0.26).timeout
			await _capture("explosion-" + result)
		await _idle(view)
		_check(_explosions - before == (0 if result == "miss" else 2 if result == "critical" else 1), "The visual result has exactly zero, one or two explosions")
		_check(GameState.state["combat"]["last_shot"]["result"] == result, "The visual matches the resolved combat result")
		DataLoader.records["course_cannon"] = original.duplicate(true)
		EffectApplier.end_combat_turn()
		await _idle(view)
	_check(_shown_shots >= 3, "Every player shot was displayed once")
	var snapshot: Dictionary = GameState.serialize()
	var before: int = _shown_shots
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK, "The FX view can save and restore completed volleys")
	await get_tree().create_timer(0.25).timeout
	_check(_shown_shots == before and GameState.serialize() == snapshot, "Loading an old volley does not replay beams or alter damage")
	var original: Dictionary = _force_weapon("course_cannon", 1.0)
	var previous_explosions: int = _explosions
	EffectApplier.shoot_combat("course_cannon", Math.cell(GameState.state["combat"]["opponent"]["pos"]))
	snapshot = GameState.serialize()
	_check(GameState.save_game(SAVE_PATH) == OK and GameState.load_game(SAVE_PATH) == OK and not board.is_animating(), "Loading during a beam cancels the visual and preserves the resolved shot")
	await get_tree().create_timer(0.65).timeout
	_check(_explosions == previous_explosions and GameState.serialize() == snapshot and Conditions.weapon_has_fired("player", "course_cannon"), "A canceled visual cannot duplicate explosions, damage or a weapon shot")
	DataLoader.records["course_cannon"] = original.duplicate(true)
	view.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await _check_enemy_volley()


func _check_enemy_volley() -> void:
	_start()
	var view: Control = load("res://scenes/combat.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var board: Node3D = view.find_child("Board", true, false)
	var displayed: Array[String] = []
	board.get_node("ShotFX").shot_started.connect(func(shot: Dictionary) -> void: displayed.append(str(shot["weapon"])))
	EffectApplier.end_combat_turn()
	var expected: Array[String] = []
	for shot: Dictionary in GameState.state["combat"]["shots"]:
		expected.append(str(shot["weapon"]))
	_check(expected.size() > 1 and displayed.is_empty() and board.is_animating(), "An enemy first moves into position before showing its multiweapon volley")
	await _idle(view)
	_check(displayed == expected and displayed[0] == "course_cannon", "Every enemy beam is shown in resolved order, strongest weapon first")
	view.queue_free()
	await get_tree().process_frame


func _idle(view: Control) -> void:
	for _step: int in range(100):
		if not view.find_child("Board", true, false).is_animating():
			return
		await get_tree().create_timer(0.05).timeout
	_check(false, "Movement and shot animations complete in bounded time")


func _capture(suffix: String) -> void:
	if "--capture-enemies" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty() and image.save_png("res://.godot/enemy-" + suffix + ".png") == OK, "The armed enemy or shot visual is rendered and saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
