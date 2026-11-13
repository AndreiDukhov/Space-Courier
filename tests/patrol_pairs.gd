extends Node

const Motion = preload("res://scripts/flight_motion.gd")
const Loadout = preload("res://scripts/ship_loadout.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")
const SpaceEffects = preload("res://scripts/space_effects.gd")
const Validator = preload("res://scripts/space_content_validator.gd")
const PIRATE: String = "npc_earth_pirate"
const WINGMAN: String = "npc_earth_raider_2"
const COP: String = "npc_earth_patrol"

var failures: Array[String] = []
var check_count: int = 0
var _originals: Dictionary = {}
var _destroyed: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Pairing and policing content validates")
	for npc_id: String in [PIRATE, WINGMAN, COP]:
		_originals[npc_id] = DataLoader.get_record(npc_id)
	EffectApplier.space_effect.connect(func(kind: String, _pos: Vector2, npc_id: String) -> void:
		if kind == "destroyed":
			_destroyed.append(npc_id))
	_check_speed()
	_check_pairs()
	_check_police()
	_check_outcome(1.0, PIRATE)
	_check_outcome(0.0, COP)
	_check_pair_clash()
	_check_migration()
	_check_content_errors()
	await _check_view()
	_restore_definitions()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Patrol and pair checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _restore_definitions() -> void:
	for npc_id: String in _originals:
		DataLoader.records[npc_id].clear()
		DataLoader.records[npc_id].merge(_originals[npc_id].duplicate(true))


func _setup(allowed: Array[String], engine_id: String = "engine_mk1") -> void:
	_restore_definitions()
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	if engine_id != "engine_mk1":
		EffectApplier.install_module(engine_id)
	EffectApplier.launch_flight()
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["id"] not in allowed:
			GameState.state["flight"]["defeated_npcs"].append(str(npc["id"]))
		elif npc["role"] == "pirate":
			_entry(str(npc["id"]))["pair_timer"] = 1000.0
	for npc_id: String in [PIRATE, WINGMAN]:
		DataLoader.records[npc_id]["waypoints"] = [[1000, 1600], [500, 1600]]
	_player(Vector2(1100, 2100), Vector2(1100, 2100))
	_place(PIRATE, Vector2(600, 1600))
	_place(WINGMAN, Vector2(650, 1630))
	_place(COP, Vector2(440, 1600))
	_destroyed.clear()


func _entry(npc_id: String) -> Dictionary:
	return GameState.state["flight"]["npcs"][npc_id]


func _place(npc_id: String, pos: Vector2) -> void:
	_entry(npc_id)["pos"] = Motion.coordinates(pos)
	_entry(npc_id)["waypoint"] = 0


func _player(pos: Vector2, target: Vector2) -> void:
	GameState.state["flight"]["pos"] = Motion.coordinates(pos)
	GameState.state["flight"]["target"] = Motion.coordinates(target)


func _check_speed() -> void:
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["role"] == "pirate":
			_check(float(npc["speed"]) > 210.0 and float(npc["speed"]) < 150.0 * Motion.BOOST_SPEED_MULTIPLIER, "A pirate outruns both normal engines and can be escaped with the basic boost")
	for engine_id: String in ["engine_mk1", "engine_mk2"]:
		_setup([PIRATE], engine_id)
		_player(Vector2(800, 2000), Vector2(2700, 2000))
		_place(PIRATE, Vector2(680, 2000))
		EffectApplier.advance_flight(6.0)
		_check(not GameState.state["flight"]["encounter"].is_empty(), "A pirate catches " + engine_id + " without boost")
		_setup([PIRATE], engine_id)
		_player(Vector2(800, 2000), Vector2(2700, 2000))
		_place(PIRATE, Vector2(680, 2000))
		_entry(PIRATE)["status"] = "chase"
		_entry(PIRATE)["target"] = "player"
		EffectApplier.advance_flight(0.5, true)
		_check(Motion.point(_entry(PIRATE)["pos"]).distance_to(Motion.point(GameState.state["flight"]["pos"])) > 120.0, "Boost increases separation from an active pirate pursuit")
		EffectApplier.advance_flight(3.0, true)
		_check(_entry(PIRATE)["status"] == "cruise" and GameState.state["flight"]["encounter"].is_empty(), "Boost breaks pursuit without opening the interception dialogue")


func _form_pair() -> void:
	for npc_id: String in [PIRATE, WINGMAN]:
		DataLoader.records[npc_id]["pairing"]["chance"] = 1.0
		_entry(npc_id)["pair_timer"] = 0.0
	EffectApplier.advance_flight(0.1)


func _check_pairs() -> void:
	_setup([PIRATE, WINGMAN])
	_form_pair()
	_check(_entry(PIRATE)["partner"] == WINGMAN and _entry(WINGMAN)["partner"] == PIRATE, "Nearby pirates create a reciprocal pair")
	EffectApplier.advance_flight(0.5)
	var distance: float = Motion.point(_entry(PIRATE)["pos"]).distance_to(Motion.point(_entry(WINGMAN)["pos"]))
	_check(distance > 10.0 and distance < 220.0, "Paired ships move together while keeping formation spacing")
	var saved: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://pirate-pair.json") == OK and GameState.load_game("user://pirate-pair.json") == OK and GameState.serialize() == saved, "Pair links and remaining duration round-trip exactly")
	EffectApplier.toggle_flight_pause()
	var paused: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(5.0)
	_check(GameState.serialize() == paused, "The pause freezes pair timers and both ships")
	EffectApplier.toggle_flight_pause()
	for npc_id: String in [PIRATE, WINGMAN]:
		_entry(npc_id)["pair_timer"] = 0.05
	EffectApplier.advance_flight(0.1)
	_check(_entry(PIRATE)["partner"].is_empty() and _entry(WINGMAN)["partner"].is_empty(), "Expired pairs clear both links before their next attempt")
	GameState.restore(saved)
	_player(Motion.point(_entry(PIRATE)["pos"]) + Vector2(20, 0), Motion.point(_entry(PIRATE)["pos"]) + Vector2(20, 0))
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "A paired pirate still opens the existing combat encounter")
	GameState.state["combat"]["result"] = "victory"
	GameState.state["combat"]["opponent"]["hull"] = 0.0
	GameState.state["combat"]["loot"] = {"money": 0, "fuel": 0}
	_check(EffectApplier.finish_combat() == OK and _entry(WINGMAN)["partner"].is_empty(), "Player victory releases the surviving wingman immediately")


func _check_police() -> void:
	_setup([PIRATE, COP])
	EffectApplier.advance_flight(0.1)
	_check(_entry(COP)["status"] == "chase" and _entry(COP)["target"] == PIRATE, "Police acquire a nearby pirate")
	_check(not Conditions.can_police_target(DataLoader.get_record(COP), _entry(COP), "npc_earth_courier", GameState.state["flight"]["npcs"]), "Police do not acquire civilian ships")
	var saved: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://police-pursuit.json") == OK and GameState.load_game("user://police-pursuit.json") == OK and GameState.serialize() == saved, "Police pursuits round-trip through JSON")
	_place(PIRATE, Vector2(2600, 1600))
	EffectApplier.advance_flight(0.1)
	_check(_entry(COP)["status"] == "cruise" and _entry(COP)["target"].is_empty(), "Police release a target outside their pursuit radius")


func _check_outcome(chance: float, victim: String) -> void:
	_setup([PIRATE, COP])
	_place(COP, Vector2(610, 1600))
	var config: Dictionary = DataLoader.records[COP]["policing"]
	config["pirate_loss_chance"] = chance
	config["resolve_seconds"] = 0.2
	config["respawn_seconds"] = 0.4
	EffectApplier.advance_flight(0.21)
	_check(_entry(victim)["status"] == "destroyed" and _destroyed == [victim], "Exactly the configured loser disappears with one explosion event")
	var survivor: String = COP if victim == PIRATE else PIRATE
	_check(_entry(survivor)["status"] != "destroyed", "The other ship survives the clash")
	_check(GameState.save_game("user://npc-clash.json") == OK and GameState.load_game("user://npc-clash.json") == OK, "The aftermath of either clash outcome can be saved")
	EffectApplier.advance_flight(0.5)
	_check(_entry(victim)["status"] == "cruise" and Conditions.npc_is_active(victim), "An ambient clash victim returns to traffic after its timer")


func _check_migration() -> void:
	_setup([PIRATE, COP])
	var old: Dictionary = GameState.serialize()
	for entry: Dictionary in old["flight"]["npcs"].values():
		entry.erase("partner")
		entry.erase("pair_timer")
	_check(GameState.restore(old) == OK and _entry(PIRATE)["partner"].is_empty(), "Old eight-field NPC entries gain empty pairing state")
	var saved: Dictionary = GameState.serialize()
	var invalid: Dictionary = saved.duplicate(true)
	invalid["flight"]["npcs"][PIRATE]["partner"] = WINGMAN
	invalid["flight"]["npcs"][PIRATE]["pair_timer"] = 10.0
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == saved, "A one-sided pair is rejected atomically")
	invalid = saved.duplicate(true)
	invalid["flight"]["npcs"][PIRATE]["pair_timer"] = -1
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == saved, "Negative pair timing is rejected atomically")


func _check_pair_clash() -> void:
	_setup([PIRATE, WINGMAN, COP])
	_form_pair()
	_place(COP, Motion.point(_entry(PIRATE)["pos"]) + Vector2(10, 0))
	DataLoader.records[COP]["policing"]["pirate_loss_chance"] = 1.0
	DataLoader.records[COP]["policing"]["resolve_seconds"] = 0.2
	EffectApplier.advance_flight(0.21)
	_check(_entry(PIRATE)["status"] == "destroyed" and _entry(WINGMAN)["partner"].is_empty(), "A police victory releases the surviving pirate wingman")
	_check(GameState.save_game("user://paired-clash.json") == OK and GameState.load_game("user://paired-clash.json") == OK, "A police clash involving a pair leaves a valid save")


func _check_content_errors() -> void:
	var invalid: Dictionary = _originals[PIRATE].duplicate(true)
	invalid["pairing"]["chance"] = 1.1
	_check(not Validator.validate_npc(invalid).is_empty(), "Pair probabilities outside zero to one are rejected")
	invalid = _originals[COP].duplicate(true)
	invalid["policing"]["pirate_loss_chance"] = -0.1
	_check(not Validator.validate_npc(invalid).is_empty(), "Invalid police victory probabilities are rejected")
	invalid["policing"]["pirate_loss_chance"] = 0.8
	invalid["policing"]["resolve_seconds"] = 0
	_check(not Validator.validate_npc(invalid).is_empty(), "Police clashes require a positive resolution time")


func _check_view() -> void:
	_setup([PIRATE, WINGMAN])
	_player(Vector2(700, 1900), Vector2(700, 1900))
	_form_pair()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	_check(view.get_node("%NPCView").get_node(PIRATE).visible and view.get_node("%NPCView").get_node(WINGMAN).visible, "Both paired ships render in local space")
	await _capture("pair")
	_setup([PIRATE, COP])
	_player(Vector2(700, 1900), Vector2(700, 1900))
	_place(COP, Vector2(610, 1600))
	DataLoader.records[COP]["policing"]["pirate_loss_chance"] = 1.0
	DataLoader.records[COP]["policing"]["resolve_seconds"] = 0.2
	EffectApplier.galaxy_changed.emit()
	EffectApplier.advance_flight(0.21)
	await _frames()
	_check(not view.get_node("%NPCView").get_node(PIRATE).visible, "A destroyed pirate model disappears")
	var particles: int = 0
	for child: Node in view.space.get_children():
		if child.get_script() == SpaceEffects:
			particles += child.get_child_count()
	_check(particles > 0, "A real police clash creates visible explosion geometry")
	await get_tree().create_timer(0.15).timeout
	await _capture("police-clash")
	view.queue_free()
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-patrol-pairs" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/patrol-pairs-" + suffix + ".png") == OK, "The " + suffix + " view renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
