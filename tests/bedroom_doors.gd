extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Service = preload("res://scripts/hub_service.gd")
const Scenes = preload("res://scripts/scene_queue.gd")
const Validator = preload("res://scripts/data_validator.gd")
const DoorValidator = preload("res://scripts/bedroom_validator.gd")
const HubScene = preload("res://scenes/hub.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Bedroom data loads without reference errors")
	_check_rules()
	_check_validation()
	await _check_interface()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Bedroom door checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_corridor")


func _check_rules() -> void:
	var doors: Array = DataLoader.get_record("hub_corridor_doors")["doors"]
	_check(doors.size() == 5, "There are five numbered doors")
	_check(doors.map(func(door: Dictionary) -> String: return str(door.get("heroine", "player"))) == ["pilot", "medic", "security", "mechanic", "player"], "The shopkeeper does not live here and the player has door five")
	for door: Dictionary in doors:
		_new_game()
		var id: String = str(door["id"])
		var destination: String = str(door["location"])
		_check(not Conditions.room_is_in_navigation(destination), "Bedroom cards are hidden for " + id)
		if not door.has("heroine"):
			_check(not Conditions.can_use_bedroom_door(id, "peek") and not Conditions.can_use_bedroom_door(id, "knock"), "The player's door has no inappropriate actions")
			_check(EffectApplier.use_bedroom_door(id, "enter") == OK and GameState.state["location"] == destination, "The player's door enters the bedroom")
			continue
		var owner: String = str(door["heroine"])
		var heroine: Dictionary = GameState.state["heroines"][owner]
		_check(int(DataLoader.get_record(owner)["age"]) >= 21, "The bedroom owner is adult")
		heroine["loc"] = "hub_tech"
		var empty: Dictionary = GameState.serialize()
		for action: String in ["peek", "knock"]:
			var result: Error = EffectApplier.use_bedroom_door(id, action)
			EffectApplier.end_peeking()
			_check(result == OK and GameState.serialize() == empty, "An absent owner does not grant permission or change stats")
		_check(EffectApplier.use_bedroom_door(id, "enter") == OK and GameState.state["location"] == destination, "An empty room can be entered")
		EffectApplier.move_player("hub_corridor")
		heroine["loc"] = destination
		heroine["attitude"] = 49.0
		heroine["mood"] = 50.0
		var time: Array = [GameState.state["day"], GameState.state["time_slot"]]
		_check(Conditions.bedroom_entry_is_rejected(Conditions.bedroom_action_scene(id, "enter")), "Attitude 49 selects rejection")
		_check(EffectApplier.use_bedroom_door(id, "enter") == OK and GameState.state["location"] == "hub_corridor" and heroine["mood"] == 45, "Uninvited entry is rejected with mood minus five")
		_check([GameState.state["day"], GameState.state["time_slot"]] == time, "Door actions do not spend a turn")
		heroine["mood"] = 2.0
		EffectApplier.use_bedroom_door(id, "enter")
		_check(heroine["mood"] == 0, "Rejection clamps mood at zero")
		heroine["mood"] = 50.0
		heroine["attitude"] = 50.0
		_check(not Conditions.bedroom_entry_is_rejected(Conditions.bedroom_action_scene(id, "enter")), "Attitude 50 selects a friendly placeholder")
		_check(EffectApplier.use_bedroom_door(id, "enter") == OK and GameState.state["location"] == destination and heroine["mood"] == 50, "Friendly entry preserves mood")
		EffectApplier.move_player("hub_corridor")
		heroine["attitude"] = 0.0
		var peek: Dictionary = GameState.serialize()
		_check(EffectApplier.use_bedroom_door(id, "peek") == OK and not GameState.state["peek"].is_empty(), "Peeking starts the saved door challenge")
		EffectApplier.end_peeking()
		_check(GameState.serialize() == peek, "Closing the unopened door changes no stats or time")
		_check(EffectApplier.use_bedroom_door(id, "knock") == OK and Conditions.bedroom_has_permission(id), "Knocking at an occupied room grants permission")
		var saved: Dictionary = GameState.serialize()
		_check(saved.size() == GameState.SAVE_FIELDS.size() and GameState.save_game("user://bedroom-check.json") == OK and GameState.load_game("user://bedroom-check.json") == OK and GameState.serialize() == saved, "Permission round-trips in existing flags with the current save contract")
		_check(EffectApplier.use_bedroom_door(id, "enter") == OK and GameState.state["location"] == destination and GameState.state["heroines"][owner]["mood"] == 50, "Permission allows entry at low attitude")
		_check(not GameState.state["flags"].has(Conditions.bedroom_permission_flag(id)), "Entering consumes the current corridor visit permission")
		EffectApplier.move_player("hub_corridor")
		EffectApplier.use_bedroom_door(id, "knock")
		EffectApplier.move_player("hub_kitchen")
		EffectApplier.move_player("hub_corridor")
		_check(not Conditions.bedroom_has_permission(id), "Leaving the corridor clears permission")
		EffectApplier.use_bedroom_door(id, "knock")
		EffectApplier.apply_effects([{"advance_time": 1}])
		_check(not GameState.state["flags"].has(Conditions.bedroom_permission_flag(id)), "A new time slot clears permission")
	_new_game()
	var unchanged: Dictionary = GameState.serialize()
	_check(EffectApplier.use_bedroom_door("missing", "enter") == ERR_UNAVAILABLE and EffectApplier.use_bedroom_door("door_pilot", "invalid") == ERR_UNAVAILABLE and GameState.serialize() == unchanged, "Invalid door actions preserve state")
	EffectApplier.move_player("hub_kitchen")
	unchanged = GameState.serialize()
	_check(EffectApplier.use_bedroom_door("door_pilot", "enter") == ERR_UNAVAILABLE and GameState.serialize() == unchanged, "Remote doors cannot be used")
	for slot: int in range(4):
		_new_game()
		Clock.advance_slots(slot)
		var legacy: Dictionary = GameState.serialize()
		var expected_location: String = str(legacy["heroines"]["mechanic"]["loc"])
		legacy["heroines"].erase("mechanic")
		var previous: Dictionary = legacy["heroines"].duplicate(true)
		_check(GameState.restore(legacy) == OK and GameState.state["heroines"]["mechanic"]["loc"] == expected_location, "Legacy saves add the mechanic at the saved time slot")
		var upgraded: Dictionary = GameState.state["heroines"].duplicate(true)
		upgraded.erase("mechanic")
		_check(upgraded == previous, "Migration preserves all existing heroines")


func _check_validation() -> void:
	var layout: Dictionary = DataLoader.get_record("hub_corridor_doors").duplicate(true)
	layout["doors"][1]["id"] = layout["doors"][0]["id"]
	_check(not DoorValidator.validate_layout(layout).is_empty(), "Duplicate door ids are rejected")
	layout = DataLoader.get_record("hub_corridor_doors").duplicate(true)
	layout["doors"][0]["drop_rect"] = [0.9, 0.2, 0.4, 0.4]
	_check(not DoorValidator.validate_layout(layout).is_empty(), "Out-of-bounds hit areas are rejected")
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	for record: Dictionary in groups["ui"]:
		if record["id"] == "hub_corridor_doors":
			record["doors"][0]["heroine"] = "missing"
	_check("unknown heroines id 'missing'" in "\n".join(Validator.validate(groups, {})), "Door owner references are checked at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	for scene: Dictionary in groups["scenes"]:
		if scene["id"] == "pilot_door_knock_test":
			scene["tags"] = []
	_check(not DoorValidator.validate_links(groups).is_empty(), "Missing door scenes are reported at startup")


func _check_interface() -> void:
	_new_game()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	var doors: Control = hub.get_node("BedroomDoors")
	_check(hub.get_node("%Locations").get_child_count() == 6, "Six shared rooms appear in the upper bar")
	_check(hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_corridor.png", "The new corridor background is used")
	for id: String in ["door_pilot", "door_medic", "door_security", "door_mechanic", "door_player"]:
		await _click(doors.get_node(id))
		var menu: PanelContainer = doors.get_node("DoorMenu")
		_check(menu.visible and get_viewport().get_visible_rect().encloses(menu.get_global_rect()), "A real click opens an on-screen menu for " + id)
		_check(menu.size.y < 290, "Door action menus remain compact")
		_check(menu.find_child("Enter", true, false) != null and (menu.find_child("Knock", true, false) == null) == (id == "door_player"), "Only owned bedrooms offer knock and peek")
		if id == "door_pilot":
			await _capture("menu")
		await _escape()
		_check(not menu.visible, "Esc closes the door menu")
	await _click(doors.get_node("door_pilot"))
	await _click(hub.get_node("%Relationships"))
	_check(hub.has_node("RelationshipsPanel") and not doors.get_node("DoorMenu").visible, "Opening another panel closes the door menu before it can overlay the panel")
	await _escape()
	_check(not hub.has_node("RelationshipsPanel"), "Esc closes the panel without reopening the door menu")
	GameState.state["heroines"]["pilot"]["loc"] = "hub_pilot_bedroom"
	GameState.state["heroines"]["pilot"]["attitude"] = 0
	hub.refresh()
	await _frames()
	await _click(doors.get_node("door_pilot"))
	await _click(doors.get_node("DoorMenu").find_child("Enter", true, false))
	_check(GameState.state["location"] == "hub_corridor" and hub.has_node("BedroomFeedback"), "A real uninvited click shows rejection in the corridor")
	var rejected: Dictionary = GameState.serialize()
	await _capture("rejected")
	await _escape()
	_check(not hub.has_node("BedroomFeedback") and GameState.serialize() == rejected, "Closing the rejection cannot repeat its penalty")
	await _click(doors.get_node("door_pilot"))
	await _click(doors.get_node("DoorMenu").find_child("Knock", true, false))
	_check(Conditions.bedroom_has_permission("door_pilot") and hub.has_node("BedroomFeedback"), "The knock button shows the invitation placeholder")
	await _escape()
	await _click(doors.get_node("door_pilot"))
	await _click(doors.get_node("DoorMenu").find_child("Enter", true, false))
	_check(GameState.state["location"] == "hub_pilot_bedroom" and hub.get_node("%Conversation").visible, "An invited click enters and opens a conversation")
	var view: Control = hub.get_node("%DialogueContent").get_child(0)
	_check(view.get("_selected_scene_id") == "pilot_door_enter_knocked_test" and view.get_node("%Lines").get_child_count() > 0, "The conversation uses the selected door placeholder")
	await _capture("invited")
	var exit: Button = doors.get_node("Exit")
	_check(exit.visible and hub.get_node("%Conversation").get_global_rect().end.y < exit.get_global_rect().position.y, "The exit remains available below the bedroom conversation")
	await _click(exit)
	await _frames()
	_check(GameState.state["location"] == "hub_corridor" and not hub.get_node("%Conversation").visible, "The exit also closes the conversation when leaving")
	GameState.state["heroines"]["pilot"]["attitude"] = 50.0
	await _click(doors.get_node("door_pilot"))
	await _click(doors.get_node("DoorMenu").find_child("Enter", true, false))
	view = hub.get_node("%DialogueContent").get_child(0)
	_check(GameState.state["location"] == "hub_pilot_bedroom" and view.get("_selected_scene_id") == "pilot_door_enter_friendly_test", "A friendly uninvited click opens its distinct placeholder")
	EffectApplier.move_player("hub_corridor")
	GameState.state["heroines"]["pilot"]["loc"] = "hub_corridor"
	_check(Service.dialogues_for("pilot").all(func(scene: Dictionary) -> bool: return not Scenes.is_bedroom(scene)), "Ordinary conversations cannot select any door scene")
	for scene: Dictionary in Service.dialogues_for("pilot"):
		_check(not Scenes.is_bedroom(scene), "Ordinary dialogue lists exclude door actions")
	for _slot: int in range(4):
		hub.refresh()
		await _frames()
		await _capture(Clock.current_slot())
		Clock.advance_slots()
	EffectApplier.move_player("hub_corridor")
	await _frames()
	await _click(doors.get_node("door_player"))
	await _click(doors.get_node("DoorMenu").find_child("Enter", true, false))
	_check(GameState.state["location"] == "hub_bedroom" and not hub.get_node("%Conversation").visible, "Door five enters the player's room without a conversation")
	await _check_exits(hub)
	hub.queue_free()
	await _frames()


func _check_exits(hub: Control) -> void:
	var exit: Button = hub.get_node("BedroomDoors/Exit")
	for door: Dictionary in DataLoader.get_record("hub_corridor_doors")["doors"]:
		EffectApplier.move_player(str(door["location"]))
		await _frames()
		exit.release_focus()
		await _hover(Vector2(12, 240))
		_check(exit.visible and exit.text.is_empty() and exit.get_draw_mode() == BaseButton.DRAW_NORMAL, "The bedroom exit is transparent until hovered")
		var area: Rect2 = exit.get_global_rect()
		_check(get_viewport().get_visible_rect().encloses(area) and area.position.y > get_viewport().get_visible_rect().size.y * 0.8 and not area.intersects(hub.get_node("%LocationPanel").get_global_rect()), "The exit occupies the lower screen without covering the room panel")
		await _hover(area.get_center())
		_check(exit.get_draw_mode() == BaseButton.DRAW_HOVER and exit.text == "В коридор", "Hover highlights the exit and displays its destination")
		if door["id"] == "door_player":
			await _capture("exit")
		var expected: Dictionary = GameState.serialize()
		expected["location"] = "hub_corridor"
		await _click(exit)
		_check(GameState.serialize() == expected, "The exit only changes location for " + str(door["id"]))
		_check(not exit.is_visible_in_tree() and not Conditions.can_exit_bedroom(), "The exit is hidden outside bedrooms")
	var saved: Dictionary = GameState.serialize()
	_check(EffectApplier.exit_bedroom() == ERR_UNAVAILABLE and GameState.serialize() == saved, "Remote bedroom exit calls cannot change state")


func _hover(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	get_viewport().push_input(event, true)
	await _frames()


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _escape() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-doors" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/bedroom-doors-" + suffix + ".png") == OK, "The door screen renders at " + suffix)


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
