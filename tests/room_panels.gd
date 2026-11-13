extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Service = preload("res://scripts/hub_service.gd")
const HubScene = preload("res://scenes/hub.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Room UI content validates")
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.apply_effects([{"item": "dish_carrot_01", "add": 1}, {"stat": "pilot.attitude", "add": 20}, {"stat": "pilot.arousal", "add": 25}])
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	_check(hub.get_node("%Inventory").is_visible_in_tree() and hub.get_node("%Relationships").is_visible_in_tree(), "Both right-side icons appear in the hub")
	_check(hub.get_node("%Inventory").get_global_rect().position.x > hub.size.x * 0.85, "The room actions sit on the right")
	await _capture("hub")
	await _check_windows(hub, false)
	await _check_compact_panel(hub)
	await _check_computers(hub)
	EffectApplier.launch_flight()
	_check(not Conditions.can_use_room_panels(), "Room panels are unavailable on the exterior flight map")
	_check(EffectApplier.visit_ship() == OK and Conditions.can_open_domestic("inventory"), "Entering the bridge enables the shared inventory")
	await _frames()
	_check(hub.get_node("%Inventory").is_visible_in_tree() and hub.get_node("%Relationships").is_visible_in_tree(), "Both right-side icons appear on the bridge")
	await _capture("bridge")
	await _check_windows(hub, true)
	var away: Dictionary = GameState.serialize()
	away["current_system"] = "sys_alpha"
	away["systems"]["sys_alpha"] = "visited"
	_check(GameState.restore(away) == OK and Conditions.can_open_domestic("inventory"), "The interior inventory remains available away from the hub system")
	await _frames()
	await _click(hub.get_node("%Inventory"))
	_check(hub._domestic != null and hub._domestic.tab == "inventory", "The backpack opens the inventory aboard in another system")
	if hub._domestic != null:
		await _click(hub._domestic.find_child("Close", true, false))
	hub.queue_free()
	await _frames()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Room panels checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_windows(hub: Control, aboard: bool) -> void:
	var saved: Dictionary = GameState.serialize()
	await _click(hub.get_node("%Inventory"))
	_check(hub._domestic != null and hub._domestic.tab == "inventory", "The backpack opens the inventory")
	if hub._domestic == null:
		return
	_check(hub._domestic._title.text == DataLoader.get_record("ui_home_inventory")["text"], "Inventory has its own title")
	_check(hub._domestic._content.find_child("dish_carrot_010", true, false) != null, "The shared player inventory includes the saved dish")
	if aboard:
		_check(not Conditions.can_use_food(0) and not Conditions.can_open_domestic("kitchen") and not Conditions.can_open_domestic("shop"), "Opening inventory on board preserves location rules for food and hub services")
		EffectApplier.advance_flight(2.0)
	_check(GameState.serialize() == saved, "Viewing inventory preserves game state")
	await _capture("inventory-ship" if aboard else "inventory-hub")
	await _click(hub._domestic.find_child("Close", true, false))
	_check(hub._domestic == null and GameState.serialize() == saved, "Closing inventory returns to the same room")
	await _click(hub.get_node("%Relationships"))
	_check(hub._relationships != null, "The heart opens relationships")
	if hub._relationships == null:
		return
	_check(hub._relationships._cards.get_child_count() == DataLoader.get_records("heroines").size(), "Relationships show every current character")
	var attitude: ProgressBar = hub._relationships._cards.get_node("pilot").find_child("attitude", true, false)
	_check(attitude.value == GameState.state["heroines"]["pilot"]["attitude"], "The relationship bar reads the saved attitude")
	var arousal: ProgressBar = hub._relationships._cards.get_node("pilot").find_child("arousal", true, false)
	_check(arousal.value > 0 and arousal.value == GameState.state["heroines"]["pilot"]["arousal"], "Relationships include nonzero saved arousal")
	var previous_arousal: float = arousal.value
	_check(GameState.serialize() == saved, "Opening relationships is read-only")
	await _capture("relationships-ship" if aboard else "relationships-hub")
	EffectApplier.apply_effects([{"stat": "pilot.attitude", "add": 5}, {"stat": "pilot.arousal", "add": 10}])
	await _frames()
	attitude = hub._relationships._cards.get_node("pilot").find_child("attitude", true, false)
	_check(attitude.value == GameState.state["heroines"]["pilot"]["attitude"], "Relationship bars refresh after effects")
	arousal = hub._relationships._cards.get_node("pilot").find_child("arousal", true, false)
	_check(arousal.value > previous_arousal and arousal.value == GameState.state["heroines"]["pilot"]["arousal"], "Arousal increases and refreshes after effects")
	saved = GameState.serialize()
	await _click(hub._relationships.find_child("Close", true, false))
	_check(hub._relationships == null and GameState.serialize() == saved, "Closing relationships returns without spending time")


func _check_computers(hub: Control) -> void:
	Service.travel("hub_office")
	await _frames()
	await _click(hub.get_node("OfficeHotspot/Computer"))
	var monitor: Control = hub.get_node("%Terminal")
	_check(monitor.visible and monitor.get_node("Artwork").texture != null, "The office PC opens the monitor artwork")
	_check(hub.get_node("%CloseTerminal").icon != null and hub.get_node("%CloseTerminal").get_global_rect().position.y > hub.get_node("%TerminalContent").get_global_rect().end.y, "The monitor exits through a power icon below the screen")
	var orders: Control = hub.get_node("%TerminalContent").get_child(0)
	_check(monitor.get_node("Artwork").get_global_rect().encloses(hub.get_node("%TerminalContent").get_global_rect()), "Office controls fit inside the monitor")
	await _capture("office-monitor")
	await _click(orders.get_node("%Orders/ord_private_01").find_child("Accept", true, false))
	_check(OrderManager.status("ord_private_01") == "active", "An order can be accepted inside the monitor")
	await _click(hub.get_node("%CloseTerminal"))
	_check(not monitor.visible, "The bezel close button closes the office monitor")
	Service.travel("hub_tech")
	await _frames()
	await _click(hub.get_node("TechHotspot/Computer"))
	var menu: Control = hub.get_node("%TerminalContent/ComputerMenu")
	_check(monitor.visible and not menu.get_node("Launch").disabled, "The workshop monitor contains the flight controls")
	_check(hub.get_node("%TerminalContent").get_global_rect().encloses(menu.get_node("Map").get_global_rect()) and hub.get_node("%TerminalContent").get_global_rect().encloses(menu.get_node("Launch").get_global_rect()), "Both workshop buttons fit on the monitor screen")
	await _capture("workshop-monitor")
	await _click(menu.get_node("Map"))
	_check(hub.has_node("GalaxyMap"), "The monitor map button opens the galaxy map")
	await _click(hub.get_node("GalaxyMap/%Close"))
	_check(not hub.has_node("GalaxyMap"), "The galaxy map closes back to the workshop")


func _check_compact_panel(hub: Control) -> void:
	var saved: Dictionary = GameState.serialize()
	Clock.advance_slots()
	var placements: Dictionary = {}
	for heroine_id: String in GameState.state["heroines"]:
		placements[heroine_id] = "hub_kitchen"
	EffectApplier.apply_schedule(placements)
	ScheduleManager.placements_changed.emit()
	await _frames()
	var people: Control = hub.get_node("%People")
	_check(people.get_child_count() == 4, "The compact room panel accommodates all current characters")
	for button: Control in people.get_children():
		_check(hub.get_node("%LocationPanel").get_global_rect().encloses(button.get_global_rect()), "Every character button stays inside the compact panel")
		for content: Control in button.get_child(0).get_child(0).get_children():
			_check(button.get_global_rect().encloses(content.get_global_rect()), "%s %s stays inside compact button %s instead of %s" % [button.name, content.get_class(), button.get_global_rect(), content.get_global_rect()])
	await _capture("compact-panel")
	_check(GameState.restore(saved) == OK, "The room state restores after checking the compact layout")
	await _frames()


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-room-panels" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/room-panels-" + suffix + ".png") == OK, "The " + suffix + " view renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
