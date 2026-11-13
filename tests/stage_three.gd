extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Service = preload("res://scripts/hub_service.gd")
const Runner = preload("res://scripts/dialogue_runner.gd")
const Validator = preload("res://scripts/data_validator.gd")
const HubView = preload("res://scripts/hub.gd")
const SAVE_TEST_PATH: String = "res://.godot/stage-three-save-test.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Hub data loads without errors")
	_check(DataLoader.get_records("locations").size() == 11, "Ten building rooms and one separate ship room are defined")
	_check(DataLoader.get_records("heroines").size() == 4, "Four adult test heroines are available")
	_check_schedules()
	_check_navigation()
	_check_scene_gates()
	_check_validation()
	_check_persistence()
	await _check_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 3 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _placements() -> Dictionary:
	var result: Dictionary = {}
	for heroine_id: String in GameState.state["heroines"]:
		result[heroine_id] = GameState.state["heroines"][heroine_id]["loc"]
	return result


func _check_schedules() -> void:
	_new_game()
	_check(GameState.state["location"] == "hub_kitchen", "The player starts in the main hall")
	_check(_placements() == {"medic": "hub_kitchen", "pilot": "hub_kitchen", "security": "ship_bridge", "shopkeeper": "hub_shop"}, "Initial placements follow morning schedules")
	var schedule: Dictionary = DataLoader.get_schedule("pilot")
	_check(ScheduleManager.entries_for_slot(schedule, "day")[0]["loc"] == "ship_bridge", "Aboard overrides replace the matching slot")
	GameState.state["heroines"]["pilot"]["aboard"] = false
	_check(ScheduleManager.entries_for_slot(schedule, "day")[0]["loc"] == "hub_tech", "An unmatched override uses the base schedule")
	GameState.state["heroines"]["pilot"]["aboard"] = true
	var entries: Array = schedule["slots"]["evening"]
	_check(ScheduleManager.choose_location(entries, 0.0) == "hub_kitchen", "Weighted selection starts with the first entry")
	_check(ScheduleManager.choose_location(entries, 0.66) == "hub_kitchen", "Weight two occupies two thirds of the interval")
	_check(ScheduleManager.choose_location(entries, 0.67) == "hub_tech", "The final third selects the second entry")
	_check(ScheduleManager.choose_location(entries, 1.0) == "hub_tech", "The upper boundary chooses a valid entry")
	_check(ScheduleManager.choose_location([], 0.5).is_empty(), "Empty weighted lists cannot produce a location")
	var conditional: Dictionary = schedule.duplicate(true)
	conditional["overrides"] = [{"if": [{"flag": "schedule_check", "is": true}], "slots": {"morning": [{"loc": "hub_tech", "weight": 1}]}}]
	_check(ScheduleManager.entries_for_slot(conditional, "morning")[0]["loc"] == "hub_kitchen", "Override flags are evaluated centrally")
	_check(EffectApplier.apply_effects([{"flag": "schedule_check", "set": true}]) == OK, "Schedule test flag can be set")
	_check(ScheduleManager.entries_for_slot(conditional, "morning")[0]["loc"] == "hub_tech", "Matching flag overrides take effect")
	Clock.advance_slots()
	_check(_placements() == {"medic": "hub_tech", "pilot": "ship_bridge", "security": "ship_bridge", "shopkeeper": "hub_shop"}, "Heroines move on the day slot")
	var fixed: Dictionary = _placements()
	for _query_index: int in range(10):
		Service.occupants("hub_kitchen")
		Service.occupants("hub_tech")
	_check(_placements() == fixed, "Presence queries never reroll placements")
	Clock.advance_slots()
	_check(GameState.state["heroines"]["medic"]["loc"] == "hub_showers", "The evening schedule moves the medic")
	_check(GameState.state["heroines"]["pilot"]["loc"] in ["hub_kitchen", "hub_tech"], "Weighted evening choices stay within their entries")
	Clock.advance_slots()
	_check(_placements() == {"medic": "hub_corridor", "pilot": "ship_bridge", "security": "ship_bridge", "shopkeeper": "hub_shop"}, "The night schedule is applied")
	Clock.advance_slots()
	_check(Clock.current_day() == 2 and _placements() == {"medic": "hub_kitchen", "pilot": "hub_kitchen", "security": "ship_bridge", "shopkeeper": "hub_shop"}, "A new day applies morning placements")
	fixed = _placements()
	_check(EffectApplier.apply_schedule({"pilot": "missing", "medic": "hub_tech", "security": "ship_bridge", "shopkeeper": "hub_shop"}) == ERR_INVALID_DATA and _placements() == fixed, "An invalid placement batch is rejected atomically")


func _check_navigation() -> void:
	_new_game()
	var fixed: Dictionary = _placements()
	_check(Service.travel("hub_tech") == OK and GameState.state["location"] == "hub_tech", "Travel uses the target location id")
	_check(Clock.current_slot() == "morning" and _placements() == fixed, "Travel does not spend time or move heroines")
	_check(Conditions.evaluate([{"at": "hub_tech"}]) and not Conditions.evaluate([{"at": "hub_kitchen"}]), "Location conditions use the player position")
	var snapshot: Dictionary = GameState.serialize()
	_check(Service.travel("missing") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Unknown destinations preserve state")
	_check(not Conditions.can_enter("hub_showers"), "Time-based access closes the showers in the morning")
	_check(Service.travel("hub_showers") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Locked destinations cannot be entered")
	_check(Service.travel("hub_kitchen") == OK, "The player can return to the main hall")
	_check(not Conditions.evaluate([{"others_absent": ["medic"]}]), "A heroine in the room blocks absence conditions")
	_check(Conditions.evaluate([{"others_absent": []}]), "An empty absence list is valid")
	_check(not Conditions.evaluate([{"others_absent": ["missing"]}]), "Unknown absence targets fail closed")
	_check(Service.wait() == OK and Clock.current_slot() == "day", "Waiting advances exactly one slot")
	_check(Conditions.evaluate([{"others_absent": ["pilot", "medic"]}]), "Absence conditions update after movement")
	_check(not Conditions.is_present("pilot"), "A heroine in another room is not present")
	_check(Service.travel("ship_bridge") == ERR_UNAVAILABLE, "The building does not lead directly to the ship bridge")
	_check(Service.travel("hub_tech") == OK and Conditions.is_present("medic"), "Travel finds a heroine shown on a building location card")
	_check(Service.wait() == OK and Conditions.can_enter("hub_showers"), "Evening opens time-gated access")
	_check(Service.travel("hub_showers") == OK and not Conditions.evaluate([{"others_absent": ["medic"]}]), "Presence follows the destination location")
	Clock.advance_slots(2)
	_check(Clock.current_slot() == "morning" and Conditions.can_enter("hub_showers"), "A room becoming closed does not invalidate staying there")
	_check(Service.travel("hub_kitchen") == OK and not Conditions.can_enter("hub_showers"), "The player can leave a closed room")
	var location: Dictionary = DataLoader.records["hub_kitchen"]
	var connections: Array = location["connects"]
	location["connects"] = []
	_check(not Conditions.can_enter("hub_tech"), "Navigation respects the connection graph")
	location["connects"] = connections
	var target: Dictionary = DataLoader.records["hub_tech"]
	var access: Array = target["access"]
	target["access"] = [{"flag": "access_check", "is": true}]
	_check(not Conditions.can_enter("hub_tech"), "Location access conditions can close a connected room")
	_check(EffectApplier.apply_effects([{"flag": "access_check", "set": true}]) == OK and Conditions.can_enter("hub_tech"), "Changing a flag reopens location access")
	target["access"] = access


func _check_scene_gates() -> void:
	_new_game()
	_check(Runner.is_available(DataLoader.get_record("pilot_test_01")), "The morning scene opens in the main hall")
	_check(Service.travel("hub_tech") == OK and not Runner.is_available(DataLoader.get_record("pilot_test_01")), "The same scene closes in another location")
	_check(Service.travel("hub_kitchen") == OK, "The scene location can be revisited")
	_check(Service.wait() == OK and not Runner.is_available(DataLoader.get_record("pilot_test_01")), "Time conditions close a scene without setting its seen flag")
	_check(Service.dialogues_for("pilot").is_empty(), "A remote heroine cannot start a hub dialogue")
	_check(Service.wait() == OK and Runner.is_available(DataLoader.get_record("pilot_test_01")), "Evening reopens the scene")
	_new_game()
	GameState.state["heroines"]["pilot"]["attitude"] = 30
	GameState.state["heroines"]["pilot"]["mood"] = 70
	_check(EffectApplier.apply_effects([{"flag": "pilot_test_01_seen", "set": true}]) == OK, "The scene gate test sets its prerequisite")
	_check(not Runner.is_available(DataLoader.get_record("pilot_test_02")), "A witness in the room blocks the second scene")
	_check(EffectApplier.apply_schedule({"pilot": "hub_kitchen", "medic": "hub_tech", "security": "ship_bridge", "shopkeeper": "hub_shop"}) == OK, "The witness can be placed in another room")
	_check(Runner.is_available(DataLoader.get_record("pilot_test_02")) and not Service.dialogues_for("pilot").is_empty(), "A scene opens when its witness leaves")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["schedules"][0]["slots"].erase("night")
	_check("all four time slots" in "\n".join(Validator.validate(groups, {})), "Incomplete schedules are reported at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["schedules"][0]["slots"]["morning"][0]["weight"] = 0
	_check("weights must be positive" in "\n".join(Validator.validate(groups, {})), "Zero schedule weights are rejected")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["schedules"][0]["slots"]["morning"][0]["loc"] = "missing"
	_check("unknown locations id 'missing'" in "\n".join(Validator.validate(groups, {})), "Unknown scheduled locations are reported")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["schedules"][0]["overrides"][0]["if"] = false
	_check("Override conditions must be an array" in "\n".join(Validator.validate(groups, {})), "Invalid override conditions are reported")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["locations"][0]["access"] = [{"time": ["invalid"]}]
	_check("Unknown time slot" in "\n".join(Validator.validate(groups, {})), "Access conditions validate slot ids")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["locations"][0]["backgrounds"] = []
	_check("backgrounds must be an object" in "\n".join(Validator.validate(groups, {})), "Background schema errors are reported")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["heroines"][0]["schedule"] = "missing"
	_check("unknown schedules id 'missing'" in "\n".join(Validator.validate(groups, {})), "Unknown schedule ids are reported")


func _check_persistence() -> void:
	_new_game()
	Clock.advance_slots(2)
	_check(EffectApplier.apply_schedule({"pilot": "hub_tech", "medic": "hub_showers", "security": "ship_bridge", "shopkeeper": "hub_shop"}) == OK, "A weighted evening placement can be fixed for the save test")
	_check(Service.travel("hub_tech") == OK, "The player position changes before saving")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_TEST_PATH) == OK, "The extended state saves to JSON")
	_new_game()
	seed(54321)
	_check(GameState.load_game(SAVE_TEST_PATH) == OK, "The extended state loads from JSON")
	_check(GameState.serialize() == snapshot, "Player and heroine positions restore exactly")
	_check(Clock.current_slot() == "evening" and GameState.state["location"] == "hub_tech", "Saved time and location restore together")
	_check(_placements() == {"pilot": "hub_tech", "medic": "hub_showers", "security": "ship_bridge", "shopkeeper": "hub_shop"}, "Loading does not reroll weighted choices")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["location"] = "missing"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unknown saved player locations are rejected")
	invalid = snapshot.duplicate(true)
	invalid["heroines"]["pilot"].erase("loc")
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Saved heroines require their fixed location")
	invalid = snapshot.duplicate(true)
	invalid["heroines"]["medic"]["loc"] = "missing"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unknown saved heroine locations are rejected")
	_check(GameState.serialize() == snapshot, "Invalid position snapshots preserve current state")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH)) == OK, "The hub verification save is removed")


func _check_view() -> void:
	_new_game()
	var packed_scene: PackedScene = load("res://scenes/hub.tscn")
	var view: HubView = packed_scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(view.get_node("%Locations").get_child_count() == 10, "All building cards belong to the scrollable navigation row")
	_check(not view.get_node("%Locations").has_node("ship_bridge"), "Ship rooms are absent from building navigation")
	_check(view.get_node("%Background").texture != null, "The supplied hall image is the room background")
	_check(view.get_node("%Locations/hub_kitchen/Travel/Thumbnail/Image").texture != null, "The hall card uses its background image")
	_check(view.get_node("%Locations/hub_kitchen/Travel/Thumbnail").clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW, "Card images are clipped to their rounded frame")
	_check(view.get_node("%Locations/hub_kitchen/Travel/Frame").get_theme_stylebox("panel").border_width_left == 6, "The wider current location frame stays visible above its thumbnail")
	_check(view.get_node("%Locations/hub_kitchen/Travel").size.is_equal_approx(Vector2(90, 90)), "Location images are square")
	_check(view.get_node("%Locations/hub_kitchen").get_global_rect().position.x < 100 and view.get_node("%Locations/hub_kitchen").get_global_rect().position.y < 50, "Location cards begin at the upper left beside the previous arrow")
	_check(view.get_node("%Locations/hub_showers/Travel").disabled, "Closed locations are visibly disabled")
	await _check_icons(view)
	_check(view.get_node("%People").get_child_count() == 2, "Both present heroines appear in the room controls")
	await _capture(view, "morning")
	var fixed: Dictionary = _placements()
	view.get_node("%Locations/hub_tech/Travel").pressed.emit()
	_check(GameState.state["location"] == "hub_tech" and Clock.current_slot() == "morning", "Clicking a square travels without spending time")
	_check(view.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_tech.png", "The workshop uses the supplied background")
	_check(_placements() == fixed and view.get_node("%People").get_child_count() == 0, "Travel preserves placements and refreshes local characters")
	view.get_node("%Locations/hub_kitchen/Travel").pressed.emit()
	_check(view.get_node("%Background").visible and view.get_node("%People").get_child_count() == 2, "Returning restores the hall and its occupants")
	view.get_node("%Wait").pressed.emit()
	_check(Clock.current_slot() == "day" and GameState.state["location"] == "hub_kitchen", "The wait button advances time in the current room")
	_check(view.get_node("%Locations/hub_tech/Occupants").has_node("medic") and GameState.state["heroines"]["pilot"]["loc"] == "ship_bridge", "Building icons update while crew aboard stays outside the building")
	_check(view.get_node("%People").get_child_count() == 0 and "day" in view.get_node("%Time").text, "Room occupants and the clock refresh together")
	await _check_icons(view)
	fixed = _placements()
	for _refresh_index: int in range(5):
		view.refresh()
	_check(_placements() == fixed, "Redrawing cards never rerolls a schedule")
	await get_tree().process_frame
	await _capture(view, "day")
	_new_game()
	view.get_node("%People/pilot").pressed.emit()
	_check(view.get_node("%Conversation").visible, "A present heroine opens a dialogue")
	var dialogue: Control = view.get_node("%DialogueContent").get_child(0)
	_check(not dialogue.get_node("Margin/Columns/Sidebar").visible, "Hub dialogue uses the compact overlay")
	await get_tree().process_frame
	await _capture(view, "dialogue")
	dialogue.get_node("%Choices/raise_mood").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not view.get_node("%Conversation").visible, "A completed action returns to the hub")
	_check(GameState.state["heroines"]["pilot"]["attitude"] == 30 and Clock.current_slot() == "day", "Hub dialogue applies the same choice effects")
	await _check_icons(view)
	_check(not view.open_dialogue("pilot") and not view.open_dialogue("missing"), "Remote and unknown characters cannot open a dialogue")
	_new_game()
	_check(view.open_dialogue("pilot"), "A new morning allows interaction again")
	view.get_node("%CloseDialogue").pressed.emit()
	_check(not view.get_node("%Conversation").visible and Clock.current_slot() == "morning", "Closing dialogue does not spend a turn")
	var snapshot: Dictionary = GameState.serialize()
	view.get_node("%Locations/hub_tech/Travel").pressed.emit()
	view.get_node("%Wait").pressed.emit()
	_check(GameState.restore(snapshot) == OK, "The UI can restore a valid snapshot")
	_check(view.get_node("%Background").visible and view.get_node("%Locations/hub_kitchen/Occupants").get_child_count() == 2, "Restoring refreshes the background and all presence icons")
	view.queue_free()
	await get_tree().process_frame


func _check_icons(view: Control) -> void:
	await get_tree().process_frame
	var count: int = 0
	for card: Control in view.get_node("%Locations").get_children():
		var occupants_row: HBoxContainer = card.get_node("Occupants")
		var button: Button = card.get_node("Travel")
		for icon: Control in occupants_row.get_children():
			count += 1
			_check(GameState.state["heroines"][str(icon.name)]["loc"] == str(card.name), "Each icon belongs to its current location")
			_check(occupants_row.get_global_rect().position.y >= button.get_global_rect().end.y, "Character icons appear below the location square")
	var expected_count: int = 0
	var current_area: String = str(DataLoader.get_record(str(GameState.state["location"]))["area"])
	for heroine_id: String in GameState.state["heroines"]:
		var heroine: Dictionary = GameState.state["heroines"][heroine_id]
		if Conditions.heroine_visible(heroine_id) and DataLoader.get_record(str(heroine["loc"])).get("area") == current_area:
			expected_count += 1
	_check(count == expected_count, "Each heroine in the current area has exactly one presence icon")


func _capture(view: Control, suffix: String) -> void:
	if "--capture-hub" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = view.get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "The hub viewport is rendered")
	if image != null and not image.is_empty():
		_check(image.save_png("res://.godot/stage-three-" + suffix + ".png") == OK, "The hub screenshot is saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
