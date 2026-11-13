extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Math = preload("res://scripts/combat_math.gd")
const State = preload("res://scripts/combat_state.gd")
const Service = preload("res://scripts/hub_service.gd")
const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "The revised content has valid ids")
	_check_abilities()
	_check_combat_migration()
	await _check_hub()
	await _check_flight()
	await _check_combat_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Presentation revision checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _launch() -> void:
	_new_game()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true})
	for npc: Dictionary in GameState.state["flight"]["npcs"].values():
		npc["cooldown"] = 10000.0


func _battle() -> void:
	_launch()
	var pirate: Dictionary = GameState.state["flight"]["npcs"]["npc_earth_pirate"]
	pirate["cooldown"] = 0.0
	pirate["weapons"] = ["cannon_s"]
	GameState.state["flight"]["pos"] = Motion.coordinates(Motion.point(pirate["pos"]) - Vector2(20, 0))
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	_check(EffectApplier.start_flight_event("event_pirate_test") == OK and EffectApplier.choose_flight_event("event_pirate_test", 0) == OK, "A real pirate encounter starts the battle")


func _check_abilities() -> void:
	_battle()
	var combat: Dictionary = GameState.state["combat"]
	_check(Math.distance(Math.cell(combat["player"]["pos"]), Math.cell(combat["opponent"]["pos"])) == 10.0, "New battles begin with ten cells between the ships")
	combat["ap"] = 4
	GameState.state["heroines"]["pilot"]["mood"] = 50.0
	_check(EffectApplier.use_combat_ability("emergency_burn") == OK and combat["ap"] == 0 and combat["move_points"] == 9 and GameState.state["ship"]["fuel"]["current"] == 29.0, "Dash spends all remaining AP and fuel while granting movement")
	_check(EffectApplier.move_combat(Math.cell(combat["player"]["pos"]) + Vector2i.RIGHT) == OK, "Dash movement remains usable with zero AP")
	_check(not Conditions.can_use_combat_ability("evasive_maneuver"), "Dash prevents further AP actions in that turn")
	_battle()
	combat = GameState.state["combat"]
	combat["player"]["shield"] = 2.0
	combat["opponent"]["pos"] = Math.coordinates(Math.cell(combat["player"]["pos"]) + Vector2i(3, 0))
	combat["movement"]["opponent"] = State.new_turn(combat["opponent"])
	_check(EffectApplier.use_combat_ability("shield_reboot") == OK and combat["ap"] == 3 and combat["player"]["shield"] == 2.0, "Shield reboot costs three AP and does not refill early")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://recharge.json") == OK and GameState.load_game("user://recharge.json") == OK and GameState.serialize() == snapshot, "The pending recharge survives an exact JSON round trip")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["combat"]["shield_recharge"]["round"] = invalid["combat"]["round"]
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "A recharge cannot load as already due")
	var original: Array = DataLoader.records["pirate_light"]["weapons"].duplicate(true)
	for weapon: Dictionary in DataLoader.records["pirate_light"]["weapons"]:
		weapon["dmg"] = [1, 1]
		weapon["accuracy"] = {"close": 1.0, "far": 1.0, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
		weapon["critical"]["chance"] = 0.0
	EffectApplier.end_combat_turn()
	DataLoader.records["pirate_light"]["weapons"] = original
	_check(GameState.state["combat"]["player"]["shield"] == 10 and GameState.state["combat"]["shield_recharge"].is_empty(), "Recharge resolves after enemy damage at the start of the next round")
	_check(GameState.state["combat"]["shots"].size() > 0, "The recharge ordering test includes an actual enemy shot")


func _check_combat_migration() -> void:
	_battle()
	var expected: Dictionary = GameState.serialize()
	var old: Dictionary = expected.duplicate(true)
	old["combat"].erase("shield_recharge")
	old["combat"]["cooldowns"].erase("shield_reboot")
	_check(GameState.restore(old) == OK and GameState.serialize() == expected, "Previous battles gain an empty recharge queue and retain positions")


func _check_hub() -> void:
	_new_game()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await get_tree().process_frame
	_check(hub.get_node("%Navigation").get_theme_stylebox("panel").bg_color.a == 0.0, "The location navigation backing is transparent")
	_check(hub.get_node("%Locations/hub_tech/Travel").get_theme_stylebox("normal").bg_color.a == 0.0, "Room buttons have transparent backgrounds")
	var thumbnail: Panel = hub.get_node("%Locations/hub_tech/Travel/Thumbnail")
	_check(thumbnail.get_theme_stylebox("panel").bg_color.a == 1.0 and hub.get_node("%Locations/hub_tech/Travel").clip_children == CanvasItem.CLIP_CHILDREN_DISABLED, "Rounded thumbnails retain an opaque clipping mask inside transparent buttons")
	_check(Service.travel("hub_tech") == OK and hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_tech.png", "The supplied workshop is shown through normal room travel")
	await _capture("workshop")
	Service.travel("hub_kitchen")
	_check(Service.travel("hub_bedroom") == OK and hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_bedroom.png", "The supplied bedroom is a connected player room")
	await _capture("bedroom")
	hub.queue_free()
	await get_tree().process_frame


func _check_flight() -> void:
	_launch()
	_check(Motion.BOUNDS == Vector2(3000, 2280), "The local system is three times larger in both dimensions")
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var camera: Camera3D = view.get_node("%Camera")
	var before: Vector3 = camera.position
	var old_ship: Vector3 = view._player.position
	EffectApplier.set_flight_target(Motion.SPAWN + Vector2(600, 0))
	EffectApplier.advance_flight(1.0)
	_check((camera.position - before).is_equal_approx(view._player.position - old_ship), "The flight camera follows the player's actual displacement")
	_check(camera.size < Motion.BOUNDS.y * Motion.WORLD_SCALE, "The camera shows a local area instead of the full system")
	_check(view.get_node("%NPCView").find_child("Trigger_*", false, false) == null, "Pirate detection zones have no visual ring")
	await _capture("flight")
	var expected: Dictionary = GameState.serialize()
	var old: Dictionary = expected.duplicate(true)
	old["flight"].erase("map_scale")
	for field: String in ["pos", "target"]:
		old["flight"][field] = Motion.coordinates(Motion.point(old["flight"][field]) / Motion.MAP_SCALE)
	for entry: Dictionary in old["flight"]["npcs"].values():
		entry["pos"] = Motion.coordinates(Motion.point(entry["pos"]) / Motion.MAP_SCALE)
	_check(GameState.restore(old) == OK and GameState.serialize() == expected, "Previous flight saves scale player, target and NPC coordinates together")
	view.queue_free()
	await get_tree().process_frame


func _check_combat_view() -> void:
	_battle()
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var gun: Button = view.find_child("Weapon_cannon_s", true, false)
	_check(gun.find_child("Icon", true, false) != null and gun.find_child("Caption", true, false).text == DataLoader.get_record("cannon_s")["name"], "Weapon slots show an icon and the data-defined name below it")
	_check("Урон" in gun.tooltip_text and "ОД" in gun.tooltip_text, "Hover descriptions contain weapon damage and AP cost")
	await _click(gun)
	_check(view._weapon_id == "cannon_s" and not view._moving, "A real click on a weapon card selects its firing mode")
	var vitals: Control = view.find_child("Vitals", true, false)
	var player_bar: ProgressBar = vitals.get_node("PlayerVitals/Hull")
	var enemy_bar: ProgressBar = vitals.get_node("EnemyVitals/Hull")
	_check(player_bar.value == 100 and enemy_bar.value == 30, "Both ship models have visible hull bars")
	_check(vitals.get_node("PlayerVitals").visible and vitals.get_node("EnemyVitals").visible, "The initial framing includes both ships and their status bars")
	await _capture("combat")
	var hover: InputEventMouseMotion = InputEventMouseMotion.new()
	hover.position = gun.get_global_rect().get_center()
	get_viewport().push_input(hover, true)
	await get_tree().create_timer(0.65).timeout
	_check(get_viewport().gui_get_hovered_control() == gun, "Weapon pictures and captions preserve mouse hover on the tooltip button")
	await _capture("combat-tooltip")
	var old_bar: Vector2 = vitals.get_node("PlayerVitals").position
	var old_vessel: Vector3 = view._board.get_node("PlayerShip").position
	view._camera.pan(Vector2(2, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(vitals.get_node("PlayerVitals").position != old_bar and view._board.get_node("PlayerShip").position == old_vessel, "Free camera movement reprojects the health bars without moving ships")
	var camera_position: Vector3 = view._camera.position
	EffectApplier.move_combat(Math.cell(GameState.state["combat"]["player"]["pos"]) + Vector2i.RIGHT)
	await get_tree().create_timer(0.55).timeout
	_check(view._camera.position == camera_position, "Combat camera stays free while the ship moves")
	var vessel: Node3D = view._board.get_node("PlayerShip")
	var expected: Vector2 = view._camera.unproject_position(vessel.global_position + Vector3.UP * 2.0) - Vector2(56, 34)
	_check(vitals.get_node("PlayerVitals").position.distance_to(expected) < 2, "The bars follow the animated model's current position")
	GameState.state["ship"]["hull"]["current"] = 64.0
	GameState.state["combat"]["player"]["shield"] = 3.0
	GameState.state["combat"]["opponent"]["hull"] = 17.0
	GameState.state["combat"]["opponent"]["shield"] = 2.0
	EffectApplier.combat_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(player_bar.value == 64 and enemy_bar.value == 17 and vitals.get_node("PlayerVitals/Shield").value == 3 and vitals.get_node("EnemyVitals/Shield").value == 2, "Damage updates hull and shield bars independently")
	await _click(view.find_child("shield_reboot", true, false))
	_check(GameState.state["combat"]["ap"] == 3 and not GameState.state["combat"]["shield_recharge"].is_empty(), "The shield card activates the delayed recharge through its normal input")
	view.queue_free()
	await get_tree().process_frame


func _click(button: Button) -> void:
	await get_tree().process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-revision" not in OS.get_cmdline_user_args():
		return
	if "--small-revision" in OS.get_cmdline_user_args():
		suffix += "-small"
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/revision-" + suffix + ".png") == OK, "The " + suffix + " screen renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
