extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Service = preload("res://scripts/hub_service.gd")
const HubScene = preload("res://scenes/hub.tscn")
const Navigation = preload("res://scripts/room_navigation.gd")
const BEDROOMS: Array[String] = ["hub_pilot_bedroom", "hub_medic_bedroom", "hub_security_bedroom"]

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Navigation and crew rooms have valid references")
	_check_bedrooms()
	await _check_navigation()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Room navigation checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _check_bedrooms() -> void:
	_new_game()
	for _slot: int in range(4):
		for source: Dictionary in DataLoader.get_records("locations"):
			if source.get("area") != "hub":
				continue
			for bedroom: String in BEDROOMS:
				GameState.state["location"] = source["id"]
				_check(Conditions.can_enter(bedroom) and Service.travel(bedroom) == OK, "The crew bedroom is reachable from " + str(source["id"]) + " during " + Clock.current_slot())
				_check(Conditions.can_enter("hub_bedroom") and Conditions.can_enter("hub_corridor"), "Each crew bedroom connects to the player's bedroom and corridor")
		Clock.advance_slots()
	for bedroom: String in BEDROOMS:
		GameState.state["location"] = bedroom
		var saved: Dictionary = GameState.serialize()
		_check(GameState.save_game("user://crew-bedroom.json") == OK and GameState.load_game("user://crew-bedroom.json") == OK and GameState.serialize() == saved, "A crew bedroom round-trips without changing the save schema")


func _check_navigation() -> void:
	_new_game()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _settled()
	var nav: Navigation = hub.get_node("%RoomNavigation")
	_check(nav.rooms.get_child_count() == 10 and _visible_rooms(nav).size() == 6, "Exactly six full location buttons are visible initially")
	_check(nav.previous.visible and nav.previous.disabled and nav.next.visible and not nav.next.disabled, "Both chevrons frame the row with the left boundary disabled")
	_check(nav.previous.get_global_rect().end.x <= nav.viewport.get_global_rect().position.x and nav.next.get_global_rect().position.x >= nav.viewport.get_global_rect().end.x, "The arrows sit on opposite sides of the clipped row")
	_check(hub.get_node("%Navigation").get_global_rect().end.x < hub.get_node("ClockPanel").get_global_rect().position.x, "Six cards and their arrows fit beside the clock")
	_check(nav.rooms.get_node("hub_shop/Travel").disabled and nav.rooms.get_node("hub_shop/Travel/ClosedShade/Closed").visible, "Closed rooms retain their disabled grey cards")
	await _capture("first")
	var saved: Dictionary = GameState.serialize()
	await _click(nav.next)
	await get_tree().create_timer(0.08).timeout
	_check(nav.viewport.scroll_horizontal > 0 and nav.viewport.scroll_horizontal < 102, "A click animates through intermediate positions")
	await _capture("moving")
	await _settled()
	_check(nav.viewport.scroll_horizontal == 102 and _visible_rooms(nav).size() == 6, "A completed click advances exactly one room with six full cards")
	_check(not nav.previous.disabled and GameState.serialize() == saved, "Scrolling enables the previous arrow and preserves gameplay state")
	for _press: int in range(6):
		await _click(nav.next)
	await _settled()
	_check(nav.viewport.scroll_horizontal == 408 and nav.next.disabled and not nav.previous.disabled, "Rapid clicks stop at the last valid six-room window")
	_check(_visible_rooms(nav).size() == 6 and "hub_security_bedroom" in _visible_rooms(nav), "The final window includes the last crew bedroom")
	await _capture("last")
	await _click(nav.previous)
	await _settled()
	_check(nav.viewport.scroll_horizontal == 306 and not nav.next.disabled and _visible_rooms(nav).size() == 6, "The previous chevron scrolls back by one room")
	await _click(nav.next)
	await _settled()
	for bedroom: String in BEDROOMS:
		await _click(nav.rooms.get_node(bedroom + "/Travel"))
		await _settled()
		_check(GameState.state["location"] == bedroom and bedroom in _visible_rooms(nav), "A real click enters " + bedroom + " and keeps it visible")
		_check(hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_bedroom.png", "Crew bedrooms use the temporary shared background")
	await _capture("bedroom")
	var offset: int = nav.viewport.scroll_horizontal
	EffectApplier.apply_effects([{"advance_time": 1}])
	await _settled()
	_check(nav.viewport.scroll_horizontal == offset and not nav.rooms.get_node("hub_shop/Travel").disabled, "A time refresh keeps the scroll position and updates access")
	var placements: Dictionary = {}
	for heroine_id: String in GameState.state["heroines"]:
		placements[heroine_id] = GameState.state["heroines"][heroine_id]["loc"]
	placements["security"] = "hub_security_bedroom"
	_check(EffectApplier.apply_schedule(placements) == OK, "Crew bedrooms accept existing placement effects")
	ScheduleManager.placements_changed.emit()
	await _settled()
	_check(nav.rooms.get_node("hub_security_bedroom/Occupants").has_node("security") and hub.get_node("%People").has_node("security"), "Presence icons and local conversations work in a crew bedroom")
	var bedroom_save: Dictionary = GameState.serialize()
	EffectApplier.move_player("hub_kitchen")
	await _settled()
	_check(nav.viewport.scroll_horizontal == 0 and "hub_kitchen" in _visible_rooms(nav), "Programmatic travel reveals the newly selected room")
	_check(GameState.restore(bedroom_save) == OK, "A saved crew bedroom can be restored")
	await _settled()
	_check("hub_security_bedroom" in _visible_rooms(nav) and nav.viewport.scroll_horizontal == 408, "Loading reveals the selected room in the last window")
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	_check(EffectApplier.visit_ship() == OK, "The existing bridge remains reachable")
	await _settled()
	_check(nav.rooms.get_child_count() == 1 and not nav.previous.visible and not nav.next.visible and nav.viewport.scroll_horizontal == 0, "The single ship room uses the same navigation without arrows")
	hub.queue_free()
	await _frames()


func _visible_rooms(nav: Navigation) -> Array[String]:
	var visible: Array[String] = []
	var area: Rect2 = nav.viewport.get_global_rect()
	for card: Control in nav.rooms.get_children():
		if area.encloses(card.get_node("Travel").get_global_rect()):
			visible.append(str(card.name))
	return visible


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _settled() -> void:
	await get_tree().create_timer(Navigation.SCROLL_SECONDS + 0.05).timeout
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-room-navigation" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/room-navigation-" + suffix + ".png") == OK, "The " + suffix + " navigation renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
