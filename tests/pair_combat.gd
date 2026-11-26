extends Node

const Roster = preload("res://scripts/combat_roster.gd")
const Math = preload("res://scripts/combat_math.gd")
const State = preload("res://scripts/combat_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const CombatScene = preload("res://scenes/combat.tscn")
const PIRATE: String = "npc_earth_pirate"
const WINGMAN: String = "npc_earth_raider_2"

var check_count: int = 0
var failures: Array[String] = []
var _originals: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "The expanded combat content validates")
	for id: String in [PIRATE, WINGMAN, "cannon_s", "course_cannon"]:
		_originals[id] = DataLoader.get_record(id)
	_setup()
	_check_spawn()
	_check_targeting()
	_check_enemy_turns()
	_check_long_battle()
	_check_victory()
	_check_partial_defeat()
	_check_saves()
	await _check_view()
	_restore_definitions()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Pair combat checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _restore_definitions() -> void:
	for id: String in _originals:
		DataLoader.records[id].clear()
		DataLoader.records[id].merge(_originals[id].duplicate(true))


func _setup() -> void:
	_restore_definitions()
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var flight: Dictionary = GameState.state["flight"]
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["id"] not in [PIRATE, WINGMAN]:
			flight["defeated_npcs"].append(str(npc["id"]))
	flight["pos"] = [900, 2100]
	flight["target"] = [900, 2100]
	for id: String in [PIRATE, WINGMAN]:
		DataLoader.records[id]["pairing"]["chance"] = 1.0
		flight["npcs"][id]["pos"] = [600, 1800] if id == PIRATE else [650, 1820]
		flight["npcs"][id]["weapons"] = ["cannon_s"]
	EffectApplier.advance_flight(0.1)
	_check(flight["npcs"][PIRATE]["partner"] == WINGMAN, "Two real nearby pirates form a pair before combat")
	var position: Array = flight["npcs"][PIRATE]["pos"]
	flight["pos"] = [float(position[0]) - 20, position[1]]
	flight["target"] = flight["pos"].duplicate()
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "The normal pirate dialogue starts the paired battle")
	for id: String in ["cannon_s", "course_cannon"]:
		DataLoader.records[id]["accuracy"] = {"close": 1.0, "far": 1.0, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
		DataLoader.records[id]["critical"]["chance"] = 0.0
		DataLoader.records[id]["dmg"] = [10, 10]


func _place(id: String, cell: Vector2i, facing: int) -> void:
	var actor: Dictionary = Roster.actor(id)
	actor["pos"] = Math.coordinates(cell)
	actor["facing"] = facing
	GameState.state["combat"]["movement"][id] = State.new_turn(actor)


func _close_positions() -> void:
	_place("player", Vector2i(10, 12), 2)
	_place("opponent", Vector2i(13, 12), 6)
	_place("opponent_2", Vector2i(12, 13), 6)


func _check_spawn() -> void:
	var combat: Dictionary = GameState.state["combat"]
	_check(combat["opponents"].size() == 2 and not combat.has("opponent") and not combat.has("enemy"), "The combat stores two independent opponents without singular aliases")
	_check(Roster.actor("opponent")["source_npc"] == PIRATE and Roster.actor("opponent_2")["source_npc"] == WINGMAN, "Both world ships retain their identities")
	_check(Roster.actor("opponent")["pos"] != Roster.actor("opponent_2")["pos"], "The pair spawns in separate cells")
	_check(Math.distance(Math.cell(combat["player"]["pos"]), Math.cell(Roster.actor("opponent")["pos"])) >= 10, "The pair begins at the existing encounter distance")
	for opponent: Dictionary in combat["opponents"]:
		_check(opponent["weapons"] == GameState.state["flight"]["npcs"][opponent["source_npc"]]["weapons"], "Every opponent keeps its saved world loadout")
	_round_trip("spawn")
	var saved: Dictionary = GameState.serialize()
	for direction: Vector2i in Math.DIRECTIONS:
		var flight: Dictionary = GameState.state["flight"]
		flight["pos"] = [1600, 1800]
		flight["target"] = [1600, 1800]
		flight["npcs"][PIRATE]["pos"] = [1600 + direction.x * 20, 1800 + direction.y * 20]
		flight["npcs"][WINGMAN]["pos"] = [1620 + direction.x * 20, 1830 + direction.y * 20]
		GameState.state["combat"] = State.initial("pirate_light", PIRATE)
		_check(GameState.state["combat"]["opponents"].size() == 2 and GameState.restore(GameState.serialize()) == OK, "The pair spawns without overlap in every encounter direction")
	GameState.restore(saved)


func _check_targeting() -> void:
	_close_positions()
	_check(not Conditions.can_move_combat(Vector2i(13, 12)) and not Conditions.can_move_combat(Vector2i(12, 13)), "Both living enemies block movement destinations")
	var clear: bool = true
	var count: int = 0
	for y: int in range(8, 17):
		for x: int in range(11, 17):
			var route: Array[Vector2i] = Conditions.combat_move_path(Vector2i(x, y))
			count += int(not route.is_empty())
			for point: Vector2i in route:
				clear = clear and point not in [Vector2i(13, 12), Vector2i(12, 13)]
	_check(clear and count > 0, "Every available route avoids both occupied cells")
	var first: Dictionary = Roster.actor("opponent").duplicate(true)
	_check(EffectApplier.shoot_combat("cannon_s", Vector2i(12, 13)) == OK and GameState.state["combat"]["last_shot"]["result"] == "hit", "A shot can target the second pirate by cell")
	_check(Roster.actor("opponent") == first and Roster.actor("opponent_2")["shield"] < first["shield"], "Only the selected enemy takes damage")
	_round_trip("second-hit")


func _check_enemy_turns() -> void:
	_setup()
	_close_positions()
	_check(EffectApplier.end_combat_turn() == OK, "The pair completes its enemy phase")
	var combat: Dictionary = GameState.state["combat"]
	for id: String in ["opponent", "opponent_2"]:
		_check(combat["fired"][id] == ["cannon_s"], "Each enemy independently fires its identical turret once")
	_check(combat["shots"].size() == 2 and combat["shots"][0]["shooter"] != combat["shots"][1]["shooter"], "The volley records a shot from each pirate")
	_check(Roster.actor("opponent")["pos"] != Roster.actor("opponent_2")["pos"] and Roster.at_cell(Math.cell(combat["player"]["pos"])).is_empty(), "The AI keeps all living ships in separate cells")
	_round_trip("enemy-phase")
	_place("player", Vector2i(10, 12), 2)
	_place("opponent", Vector2i(13, 12), 6)
	_place("opponent_2", Vector2i(12, 13), 6)
	Roster.actor("opponent")["hull"] = 1.0
	Roster.actor("opponent")["shield"] = 0.0
	_check(EffectApplier.shoot_combat("cannon_s", Vector2i(13, 12)) == OK and combat["result"] == "active" and combat["loot"].is_empty(), "The first kill leaves the battle active without awarding loot")
	_check(Roster.living().size() == 1 and not Conditions.can_finish_combat(), "The surviving pirate must still be defeated")
	_round_trip("one-survivor")
	_check(EffectApplier.end_combat_turn() == OK and GameState.state["combat"]["fired"]["opponent"].is_empty(), "The destroyed pirate no longer acts")
	for shot: Dictionary in GameState.state["combat"]["shots"]:
		_check(shot["shooter"] == "opponent_2", "Only the surviving pirate fires")
	_round_trip("survivor-phase")


func _check_victory() -> void:
	_setup()
	_close_positions()
	_place("opponent_2", Vector2i(14, 12), 6)
	for opponent: Dictionary in GameState.state["combat"]["opponents"]:
		opponent["hull"] = 1.0
		opponent["shield"] = 0.0
	EffectApplier.shoot_combat("cannon_s", Vector2i(13, 12))
	EffectApplier.shoot_combat("course_cannon", Vector2i(14, 12))
	var combat: Dictionary = GameState.state["combat"]
	_check(combat["result"] == "victory" and Roster.living().is_empty(), "The second kill produces victory")
	for field: String in ["money", "fuel"]:
		var minimum: int = 0
		var maximum: int = 0
		for opponent: Dictionary in combat["opponents"]:
			var bounds: Array = DataLoader.get_record(str(opponent["enemy"]))["loot"][field]
			minimum += int(bounds[0])
			maximum += int(bounds[1])
		_check(combat["loot"][field] >= minimum and combat["loot"][field] <= maximum, "Victory combines both enemies' loot ranges")
	_round_trip("victory")
	var money: int = int(GameState.state["money"])
	var reward: int = int(GameState.state["combat"]["loot"]["money"])
	_check(EffectApplier.finish_combat() == OK and GameState.state["money"] == money + reward, "The combined reward is delivered once")
	for id: String in [PIRATE, WINGMAN]:
		_check(id in GameState.state["flight"]["defeated_npcs"] and not Conditions.npc_is_active(id), "Both defeated world ships disappear")
	_check(EffectApplier.finish_combat() == ERR_UNAVAILABLE, "Repeated result delivery cannot pay again")
	_check(GameState.restore(GameState.serialize()) == OK, "The returned world state remains valid")


func _check_long_battle() -> void:
	_setup()
	_close_positions()
	for round_index: int in range(4):
		GameState.state["ship"]["hull"]["current"] = 100.0
		_check(EffectApplier.end_combat_turn() == OK, "Both opponents continue taking later turns")
		_round_trip("later-enemy-" + str(round_index))
		var origin: Vector2i = Math.cell(Roster.actor("player")["pos"])
		for direction: Vector2i in Math.DIRECTIONS:
			if Conditions.can_move_combat(origin + direction):
				EffectApplier.move_combat(origin + direction)
				break
		_round_trip("later-player-" + str(round_index))


func _check_partial_defeat() -> void:
	_setup()
	_close_positions()
	Roster.actor("opponent")["hull"] = 1.0
	Roster.actor("opponent")["shield"] = 0.0
	EffectApplier.shoot_combat("cannon_s", Vector2i(13, 12))
	GameState.state["ship"]["hull"]["current"] = 0.0
	GameState.state["combat"]["result"] = "defeat"
	_round_trip("partial-defeat")
	_check(EffectApplier.finish_combat() == OK and PIRATE in GameState.state["flight"]["defeated_npcs"] and WINGMAN not in GameState.state["flight"]["defeated_npcs"], "Losing to the survivor preserves the first pirate's destruction")
	_check(GameState.restore(GameState.serialize()) == OK, "The partial-defeat rescue leaves a valid world state")


func _check_saves() -> void:
	_setup()
	var saved: Dictionary = GameState.serialize()
	for kind: String in ["empty", "duplicate", "overlap", "enemy", "source", "history", "shots"]:
		var invalid: Dictionary = saved.duplicate(true)
		match kind:
			"empty": invalid["combat"]["opponents"] = []
			"duplicate": invalid["combat"]["opponents"][1]["id"] = "opponent"
			"overlap": invalid["combat"]["opponents"][1]["pos"] = invalid["combat"]["opponents"][0]["pos"].duplicate()
			"enemy": invalid["combat"]["opponents"][1]["enemy"] = "missing"
			"source": invalid["combat"]["opponents"][1]["source_npc"] = PIRATE
			"history": invalid["combat"]["movement"]["opponent_2"] = {}
			"shots": invalid["combat"]["last_shot"] = {"shooter": "missing", "weapon": "cannon_s", "target": [1, 1], "result": "hit", "damage": 1}
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == saved, "Malformed " + kind + " data is rejected atomically")
	GameState.state["combat"] = State.initial("pirate_light", "")
	var single: Dictionary = GameState.serialize()
	var legacy: Dictionary = single.duplicate(true)
	var opponent: Dictionary = legacy["combat"]["opponents"][0].duplicate(true)
	legacy["combat"]["enemy"] = opponent["enemy"]
	legacy["combat"]["source_npc"] = opponent["source_npc"]
	for key: String in ["id", "enemy", "source_npc"]:
		opponent.erase(key)
	legacy["combat"].erase("opponents")
	legacy["combat"]["opponent"] = opponent
	legacy["combat"].erase("allies")
	legacy["combat"].erase("battle_id")
	_check(GameState.restore(legacy) == OK and GameState.serialize() == single, "An old singular-opponent save migrates exactly")
	_round_trip("migrated-single")


func _check_view() -> void:
	_setup()
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await _frames()
	_check(view._board._vessels.size() == 3 and view._board.has_node("EnemyShip2"), "The real battle renders player and two opponents")
	var vitals: Control = view.find_child("Vitals", true, false)
	_check(vitals.has_node("EnemyVitals2") and vitals.get_node("EnemyVitals2/Hull").value == Roster.actor("opponent_2")["hull"], "The second ship has independent hull and shield bars")
	await _capture("spawn")
	var camera_before: Vector3 = view._camera.position
	var ship_before: Vector3 = view._board.get_node("PlayerShip").position
	var player: Vector2i = Math.cell(GameState.state["combat"]["player"]["pos"])
	var target: Vector2i = player + Vector2i(2, 0)
	_check(EffectApplier.move_combat(target) == OK, "A real paired battle accepts a maneuver")
	var tracked: bool = true
	var moving: bool = false
	while view._board.is_animating():
		await RenderingServer.frame_post_draw
		var delta: Vector3 = view._board.get_node("PlayerShip").position - ship_before
		moving = moving or delta.length() > 0.05
		tracked = tracked and view._camera.position.is_equal_approx(camera_before)
	_check(tracked and moving, "The free camera stays in place throughout smooth player movement")
	var focus: Vector3 = view._camera.position
	var snapshot: Dictionary = GameState.serialize()
	var drag: InputEventMouseButton = InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_RIGHT
	drag.pressed = true
	drag.position = Vector2(1, 1)
	view._camera.handle_input(drag)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(1, 1)
	motion.relative = Vector2(180, 100)
	view._camera.handle_input(motion)
	await _frames()
	_check(view._camera.position != focus and GameState.serialize() == snapshot, "Dragging freely pans the camera without changing state")
	var dragged_focus: Vector3 = view._camera.position
	var zoom: float = view._camera.size
	drag.button_index = MOUSE_BUTTON_WHEEL_UP
	view._camera.handle_input(drag)
	_check(view._camera.size < zoom and view._camera.position == dragged_focus, "Zoom preserves the manually selected focus")
	await _capture("follow")
	_round_trip("view")
	await _frames()
	_check((view._camera.position - view._board.get_node("PlayerShip").position).is_equal_approx(Vector3(0, 16.85, 13)), "Loading a paired battle recenters the free camera over the player")
	_close_positions()
	Roster.actor("opponent_2")["hull"] = 1.0
	Roster.actor("opponent_2")["shield"] = 0.0
	view._board.reset_from_state()
	EffectApplier.combat_changed.emit()
	await _frames()
	await RenderingServer.frame_post_draw
	var rows: Array[Control] = [vitals.get_node("PlayerVitals"), vitals.get_node("EnemyVitals"), vitals.get_node("EnemyVitals2")]
	for first: int in range(rows.size()):
		for second: int in range(first + 1, rows.size()):
			_check(not rows[first].get_global_rect().intersects(rows[second].get_global_rect()), "Nearby ships' hull and shield bars remain readable without overlap")
	await _click(view.find_child("Weapon_cannon_s", true, false).get_global_rect().get_center())
	var cell: Vector3 = Math.world_position(Roster.actor("opponent_2")["pos"])
	cell.y = 0.0
	await _click(view._space.global_position + view._camera.unproject_position(cell))
	_check(Roster.actor("opponent_2")["hull"] == 0 and Roster.actor("opponent")["hull"] > 0, "A real weapon-card and map click hits the selected second enemy")
	while view._board.is_animating():
		await get_tree().process_frame
	_check(view._board.get_node("EnemyShip").visible and not view._board.get_node("EnemyShip2").visible, "The selected dead model disappears while the other pirate remains")
	await _capture("one-survivor")
	_round_trip("visible-survivor")
	EffectApplier.end_combat_turn()
	_check(not view._board.get_node("EnemyShip2").visible, "A later enemy phase cannot resurrect the destroyed model")
	while view._board.is_animating():
		await get_tree().process_frame
	_check(not view._board.get_node("EnemyShip2").visible, "The destroyed model stays hidden after the survivor's shot effects")
	var pair: Dictionary = GameState.serialize()
	var single: Dictionary = pair.duplicate(true)
	single["combat"] = State.initial("pirate_light", "")
	_check(GameState.restore(single) == OK, "An open battle view can load a single-enemy save")
	await _frames()
	_check(not view._board.has_node("EnemyShip2") and not vitals.has_node("EnemyVitals2"), "Loading one enemy removes the extra model and bars")
	_check(GameState.restore(pair) == OK, "The same view can reload the paired battle")
	await _frames()
	_check(view._board.has_node("EnemyShip2") and vitals.has_node("EnemyVitals2") and not view._board.get_node("EnemyShip2").visible, "Reloading restores the second participant and its destroyed state")
	view.queue_free()
	await _frames()


func _round_trip(label: String) -> void:
	var saved: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://pair-" + label + ".json") == OK and GameState.load_game("user://pair-" + label + ".json") == OK and GameState.serialize() == saved, "The " + label + " state round-trips exactly through JSON")


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		get_viewport().push_input(event, true)
	await _frames()


func _capture(label: String) -> void:
	if "--capture-pair-combat" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var suffix: String = "-small" if "--small" in OS.get_cmdline_user_args() else ""
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/pair-combat-" + label + suffix + ".png") == OK, "The " + label + " screen renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
