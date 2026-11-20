extends Node

const Battles = preload("res://scripts/ambient_battle_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Roster = preload("res://scripts/combat_roster.gd")
const CombatState = preload("res://scripts/combat_state.gd")
const Math = preload("res://scripts/combat_math.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Validator = preload("res://scripts/data_validator.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")
const PIRATE: String = "npc_earth_pirate"
const WINGMAN: String = "npc_earth_raider_2"
const POLICE: String = "npc_earth_patrol"
const CIVILIAN: String = "npc_earth_courier"

var failures: Array[String] = []
var check_count: int = 0
var _originals: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Battle profiles, rules and references validate")
	for id: String in [PIRATE, WINGMAN, POLICE, CIVILIAN, "pirate_light", "patrol_ship", "civilian_ship", "cannon_s", "course_cannon"]:
		_originals[id] = DataLoader.get_record(id)
	_check_world()
	_check_travel()
	_check_sides()
	_check_turns()
	_check_results()
	_check_migration()
	_check_invalid()
	await _check_view()
	_restore_definitions()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Battle intervention checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _restore_definitions() -> void:
	for id: String in _originals:
		DataLoader.records[id].clear()
		DataLoader.records[id].merge(_originals[id].duplicate(true))


func _battle(police: bool = true, paired: bool = false) -> String:
	_restore_definitions()
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var allowed: Array[String] = [PIRATE, POLICE if police else CIVILIAN]
	if paired:
		allowed.append(WINGMAN)
	var flight: Dictionary = GameState.state["flight"]
	flight["pos"] = Motion.coordinates(Vector2(1200, 2100))
	flight["target"] = Motion.coordinates(Vector2(1200, 2100))
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["id"] not in allowed:
			flight["defeated_npcs"].append(str(npc["id"]))
		else:
			flight["npcs"][npc["id"]].merge({"status": "cruise", "pos": [600, 1800], "target": "", "destination": "", "timer": 1000.0, "cooldown": 1000.0, "weapons": ["cannon_s"], "pair_timer": 1000.0 if npc["role"] == "pirate" else 0.0}, true)
	if paired:
		for id: String in [PIRATE, WINGMAN]:
			DataLoader.records[id]["pairing"]["chance"] = 1.0
			flight["npcs"][id]["pair_timer"] = 0.0
			flight["npcs"][id]["cooldown"] = 0.0
		flight["npcs"][WINGMAN]["pos"] = [650, 1830]
		EffectApplier.advance_flight(0.01)
	var attacker: String = POLICE if police else PIRATE
	var defender: String = PIRATE if police else CIVILIAN
	var origin: Vector2 = Motion.point(flight["npcs"][defender]["pos"])
	flight["npcs"][attacker].merge({"status": "chase", "target": defender, "pos": Motion.coordinates(origin + Vector2(5, 0)), "cooldown": 0.0, "timer": float(DataLoader.get_record(attacker)["policing" if police else "piracy"]["resolve_seconds" if police else "robbery_seconds"]) - 0.001}, true)
	EffectApplier.advance_flight(0.01)
	_check(flight["battles"].size() == 1, "An actual NPC contact begins a persistent battle")
	return str(flight["battles"][0]["id"]) if not flight["battles"].is_empty() else ""


func _pause(battle_id: String) -> void:
	var battle: Dictionary = Battles.find(battle_id, GameState.state["flight"]["battles"])
	var npc: String = str(battle["sides"][0][0])
	var position: Vector2 = Motion.point(GameState.state["flight"]["npcs"][npc]["pos"]) + Vector2(0, 25)
	GameState.state["flight"]["pos"] = Motion.coordinates(position)
	GameState.state["flight"]["target"] = Motion.coordinates(position)
	_check(EffectApplier.pause_at_npc(npc) == OK, "A close click action pauses beside a fighting NPC")


func _check_world() -> void:
	var id: String = _battle()
	var battle: Dictionary = Battles.find(id, GameState.state["flight"]["battles"])
	_check(battle["remaining"] > 19.0 and battle["sides"] == [[POLICE], [PIRATE]], "The police battle preserves both sides and the intervention window")
	_check(not GameState.state["flight"]["paused"] and not Conditions.can_join_battle(id, 0), "Distant NPC combat does not pause flight or allow remote intervention")
	_round_trip("world")
	_pause(id)
	var saved: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(2.0)
	_check(GameState.serialize() == saved and Conditions.can_join_battle(id, 0) and Conditions.can_join_battle(id, 1), "Paused combat freezes its timer and offers either side")
	_check(not Conditions.can_contact_npc(POLICE) and not Conditions.can_trade_npc(PIRATE), "Fighting ships do not offer ordinary dialogue or trading")
	_round_trip("paused-world")
	id = _battle(false, true)
	battle = Battles.find(id, GameState.state["flight"]["battles"])
	_check(battle["sides"][0].size() == 2 and battle["sides"][1] == [CIVILIAN], "A pirate pair can fight a civilian as another joinable battle")
	_round_trip("pirate-civilian")
	id = _battle()
	DataLoader.records[POLICE]["policing"]["pirate_loss_chance"] = 1.0
	DataLoader.records[POLICE]["policing"]["respawn_seconds"] = 0.4
	EffectApplier.advance_flight(20.1)
	_check(GameState.state["flight"]["battles"].is_empty() and GameState.state["flight"]["npcs"][PIRATE]["status"] == "destroyed", "An unattended battle resolves through the existing police outcome")
	EffectApplier.advance_flight(0.5)
	_check(Conditions.npc_is_active(PIRATE), "An ambient casualty can return to traffic")
	_round_trip("ambient-result")


func _check_travel() -> void:
	var id: String = _battle()
	var battles: Array = GameState.state["flight"]["battles"].duplicate(true)
	_check(EffectApplier.visit_ship() == OK, "The bridge remains accessible while nearby NPCs fight")
	EffectApplier.advance_flight(2.0)
	_check(GameState.state["flight"]["battles"] == battles, "Visiting the bridge freezes ambient battle timers")
	_round_trip("bridge-battle")
	_check(EffectApplier.leave_ship() == OK, "Leaving the bridge returns to the ongoing flight")
	var gate: Dictionary = Conditions.space_object("r_earth_alpha")
	GameState.state["flight"]["pos"] = gate["pos"].duplicate()
	GameState.state["flight"]["target"] = gate["pos"].duplicate()
	_check(EffectApplier.jump_route("r_earth_alpha") == OK and GameState.state["current_system"] == "sys_alpha", "A normal wormhole jump can leave an ambient fight behind")
	_check(GameState.state["flight"]["battles"] == battles and not Battles.find(id, GameState.state["flight"]["battles"]).is_empty(), "The jump preserves the old system's participants and battle record")
	EffectApplier.advance_flight(1.0)
	_check(GameState.state["flight"]["battles"] == battles, "Off-system battles remain frozen with the rest of their traffic")
	_round_trip("off-system-battle")


func _check_sides() -> void:
	for police: bool in [true, false]:
		for side: int in [0, 1]:
			var id: String = _battle(police, true)
			var battle: Dictionary = Battles.find(id, GameState.state["flight"]["battles"]).duplicate(true)
			_pause(id)
			_check(EffectApplier.join_battle(id, side) == OK, "Either faction can be selected for intervention")
			var combat: Dictionary = GameState.state["combat"]
			_check(combat["allies"].size() == battle["sides"][side].size() and combat["opponents"].size() == battle["sides"][1 - side].size(), "All members of both sides enter the tactical board")
			for ally: Dictionary in combat["allies"]:
				_check(ally["source_npc"] in battle["sides"][side] and Roster.friendly(str(ally["id"])), "The chosen ships become AI allies")
			for opponent: Dictionary in combat["opponents"]:
				_check(opponent["source_npc"] in battle["sides"][1 - side] and not Roster.friendly(str(opponent["id"])), "The other ships become the opposing faction")
			_round_trip("side-" + str(police) + str(side))
			var saved: Dictionary = GameState.serialize()
			EffectApplier.advance_flight(3.0)
			_check(GameState.serialize() == saved, "The tactical encounter freezes background battles")


func _place(id: String, cell: Vector2i, facing: int) -> void:
	var ship: Dictionary = Roster.actor(id)
	ship["pos"] = Math.coordinates(cell)
	ship["facing"] = facing
	GameState.state["combat"]["movement"][id] = CombatState.new_turn(ship)


func _join_close() -> void:
	var id: String = _battle()
	_pause(id)
	EffectApplier.join_battle(id, 0)
	_place("player", Vector2i(10, 12), 2)
	_place("ally", Vector2i(13, 12), 2)
	_place("opponent", Vector2i(16, 12), 6)
	for profile: String in ["pirate_light", "patrol_ship", "civilian_ship"]:
		for weapon: Dictionary in DataLoader.records[profile]["weapons"]:
			weapon["accuracy"] = {"close": 1.0, "far": 1.0, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
			weapon["critical"]["chance"] = 0.0
			weapon["dmg"] = [2, 2]
			weapon["range"] = 15


func _check_turns() -> void:
	_join_close()
	var before: Dictionary = GameState.serialize()
	_check(not Conditions.can_shoot_combat("cannon_s", Vector2i(13, 12)) and EffectApplier.shoot_combat("cannon_s", Vector2i(13, 12)) == ERR_UNAVAILABLE and GameState.serialize() == before, "The player cannot fire on the selected allies")
	_check(EffectApplier.end_combat_turn() == OK, "The allied and enemy AI complete a full round")
	var combat: Dictionary = GameState.state["combat"]
	_check(combat["fired"]["ally"] == ["cannon_s"] and combat["fired"]["opponent"] == ["cannon_s"], "Identical guns fire once for each faction's ship")
	_check(Roster.actor("ally")["shield"] < 20 and Roster.actor("opponent")["shield"] < 10, "The two AI factions damage each other")
	_round_trip("ai-round")
	for index: int in range(3):
		EffectApplier.end_combat_turn()
		_round_trip("later-round-" + str(index))
	_join_close()
	Roster.actor("ally")["hull"] = 1.0
	Roster.actor("ally")["shield"] = 0.0
	for weapon: Dictionary in DataLoader.records["pirate_light"]["weapons"]:
		weapon["dmg"] = [200, 200]
	EffectApplier.end_combat_turn()
	_check(Roster.actor("ally")["hull"] == 0 and GameState.state["combat"]["result"] == "active", "Enemies can destroy an ally while the player continues fighting")
	_round_trip("ally-loss")


func _check_results() -> void:
	_join_close()
	Roster.actor("opponent")["hull"] = 1.0
	Roster.actor("opponent")["shield"] = 0.0
	EffectApplier.end_combat_turn()
	_check(GameState.state["combat"]["result"] == "victory" and GameState.state["combat"]["last_shot"]["shooter"] == "ally", "The ally can land the winning shot")
	_round_trip("allied-victory")
	_check(EffectApplier.finish_combat() == OK and GameState.state["flight"]["battles"].is_empty() and not Conditions.npc_is_active(PIRATE) and Conditions.npc_is_active(POLICE), "Victory removes the encounter and defeated enemy while the ally survives")
	_check(GameState.restore(GameState.serialize()) == OK and EffectApplier.finish_combat() == ERR_UNAVAILABLE, "The completed result is valid and cannot pay twice")
	_join_close()
	GameState.state["ship"]["hull"]["current"] = 0.0
	GameState.state["combat"]["result"] = "defeat"
	_round_trip("intervention-defeat")
	_check(EffectApplier.finish_combat() == OK and GameState.state["location"] == "hub_office" and GameState.state["flight"]["battles"].is_empty(), "Player defeat uses the existing rescue and releases surviving NPCs")
	_check(GameState.restore(GameState.serialize()) == OK, "The rescue leaves no dangling battle statuses")


func _check_migration() -> void:
	_battle()
	GameState.state["flight"]["battles"] = []
	for npc: Dictionary in DataLoader.get_records("npcs"):
		var entry: Dictionary = GameState.state["flight"]["npcs"][npc["id"]]
		if entry["status"] == "battle":
			entry.merge({"status": "cruise", "target": "", "timer": 0.0}, true)
	GameState.state["combat"] = CombatState.initial("pirate_light", "")
	var legacy: Dictionary = GameState.serialize()
	legacy["flight"].erase("battles")
	legacy["combat"].erase("allies")
	legacy["combat"].erase("battle_id")
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["role"] != "pirate":
			legacy["flight"]["npcs"][npc["id"]]["weapons"] = []
	_check(GameState.restore(legacy) == OK and GameState.state["combat"]["allies"].is_empty() and GameState.state["flight"]["battles"].is_empty(), "A pre-intervention save gains the empty battle fields")
	for npc_id: String in [POLICE, CIVILIAN]:
		_check(Loadouts.valid(Loadouts.enemy_for_npc(npc_id), GameState.state["flight"]["npcs"][npc_id]["weapons"]), "Legacy non-pirates gain a valid combat loadout")
	_round_trip("legacy")


func _check_invalid() -> void:
	var id: String = _battle()
	var valid: Dictionary = GameState.serialize()
	for kind: String in ["duplicate", "remaining", "source", "status"]:
		var invalid: Dictionary = valid.duplicate(true)
		match kind:
			"duplicate": invalid["flight"]["battles"].append(invalid["flight"]["battles"][0].duplicate(true))
			"remaining": invalid["flight"]["battles"][0]["remaining"] = -1
			"source": invalid["flight"]["battles"][0]["sides"][1][0] = "missing"
			"status": invalid["flight"]["npcs"][PIRATE]["status"] = "cruise"
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == valid, "Malformed world battle " + kind + " is rejected atomically")
	_pause(id)
	EffectApplier.join_battle(id, 0)
	valid = GameState.serialize()
	var invalid: Dictionary = valid.duplicate(true)
	invalid["combat"]["allies"][0]["source_npc"] = PIRATE
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == valid, "A ship cannot change sides inside a loaded battle")
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["combat_profile"] = "missing"
	_check(not Validator.validate(groups, DataLoader.record_sources).is_empty(), "Missing combat profile references are reported")


func _check_view() -> void:
	var id: String = _battle(true, true)
	var battle: Dictionary = Battles.find(id, GameState.state["flight"]["battles"])
	var origin: Vector2 = Motion.point(GameState.state["flight"]["npcs"][POLICE]["pos"])
	GameState.state["flight"]["pos"] = Motion.coordinates(origin + Vector2(0, 30))
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	_check(view.space.get_node("AmbientBattles/BattleBeams").visible and "В бою" in view.get_node("%NPCView").get_node(POLICE + "_label").text, "World battles show beams and a fighting label")
	var previous_label: float = INF
	for npc_id: String in Battles.members(battle):
		var label: Label3D = view.get_node("%NPCView").get_node(npc_id + "_label")
		var screen: Vector2 = view.camera.unproject_position(label.global_position)
		var top: Vector2 = view.camera.unproject_position(label.global_position + view.camera.global_basis.y * label.font_size * label.pixel_size)
		_check(previous_label == INF or absf(previous_label - screen.y) >= absf(screen.y - top.y) * 1.25, "Close combatant label rows leave room for the rendered text")
		previous_label = screen.y
	await _capture("world")
	var point: Vector2 = view.get_node("%SpaceContainer").global_position + view.camera.unproject_position(Motion.world_position(GameState.state["flight"]["npcs"][POLICE]["pos"], 2.8))
	await _click(point)
	var selected: String = view._interactions.selected_npc
	_check(GameState.state["flight"]["paused"] and not selected.is_empty(), "A real nearby ship click pauses beside the battle")
	if selected.is_empty():
		view.queue_free()
		return
	await _click(view._interactions.get_node(selected + "/Battle").get_global_rect().get_center())
	_check(view._battle_panel != null and not view._battle_panel.find_child("Help0", true, false).disabled and not view._battle_panel.find_child("Help1", true, false).disabled, "The overhead action opens both faction choices")
	await _capture("choice")
	await _click(view._battle_panel.find_child("Help0", true, false).get_global_rect().get_center())
	_check(Conditions.has_combat() and GameState.state["combat"]["allies"].size() == 1 and GameState.state["combat"]["opponents"].size() == 2, "A real side-choice click joins the police against the pair")
	view.queue_free()
	await _frames()
	var combat: Control = CombatScene.instantiate()
	add_child(combat)
	await _frames()
	_check(combat._board.has_node("AllyShip") and combat._board.has_node("EnemyShip2") and combat.find_child("Vitals", true, false).has_node("AllyVitals"), "The tactical view renders an ally, both enemies and their status bars")
	var vitals: Control = combat.find_child("Vitals", true, false)
	for row: Control in vitals._rows.values():
		if row.visible:
			_check(Rect2(Vector2.ZERO, vitals.size).encloses(row.get_rect()), "Every actor bar stays inside the tactical map")
	await _capture("combat")
	_round_trip("visible-intervention")
	await _frames()
	_check(combat._board._vessels.size() == 4, "Reloading preserves every tactical actor")
	combat.queue_free()
	await _frames()


func _round_trip(label: String) -> void:
	var saved: Dictionary = GameState.serialize()
	var write_error: Error = GameState.save_game("user://intervention-" + label + ".json")
	var read_error: Error = GameState.load_game("user://intervention-" + label + ".json")
	if GameState.serialize() != saved:
		print("Difference ", label, " ", _difference(saved, GameState.serialize(), "state"))
	_check(write_error == OK and read_error == OK and GameState.serialize() == saved, "The " + label + " state round-trips through JSON (%s, %s)" % [write_error, read_error])


func _difference(left: Variant, right: Variant, path: String) -> String:
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key):
				return path + "." + str(key) + " missing"
			if left[key] != right[key]:
				return _difference(left[key], right[key], path + "." + str(key))
	elif left is Array and right is Array and left.size() == right.size():
		for index: int in range(left.size()):
			if left[index] != right[index]:
				return _difference(left[index], right[index], path + "[" + str(index) + "]")
	return path + " expected " + str(left) + " actual " + str(right)


func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture-intervention" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var suffix: String = "-small" if "--small" in OS.get_cmdline_user_args() else ""
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/intervention-" + label + suffix + ".png") == OK, "The " + label + " view renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
