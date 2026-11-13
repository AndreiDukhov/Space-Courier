extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Indicators = preload("res://scripts/offscreen_indicators.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")
const MapScene = preload("res://scenes/galaxy_map.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Journal content validates")
	await _check_empty()
	await _check_flight()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Quest journal checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_empty() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	var map: Control = MapScene.instantiate()
	add_child(map)
	await _frames()
	var button: Button = map.find_child("OpenQuests", true, false)
	await _click(button)
	var journal: Control = map.get_node("QuestJournal")
	var content: VBoxContainer = journal.find_child("Quests", true, false)
	_check(content.get_child_count() == 1 and content.get_child(0).text == "Принятых заданий пока нет.", "The workshop map opens a journal with an explicit empty state")
	_check(Conditions.active_order_ids().is_empty(), "Available but unaccepted offers do not appear as tasks")
	await _click(journal.find_child("Close", true, false))
	_check(not map.has_node("QuestJournal"), "The journal closes through its button")
	map.queue_free()
	await _frames()


func _check_flight() -> void:
	Clock.advance_slots()
	EffectApplier.move_player("hub_kitchen")
	EffectApplier.move_player("hub_shop")
	_check(EffectApplier.accept_shop_quest("shop_quest_01") == OK, "A shop task is accepted for the mixed journal")
	EffectApplier.move_player("hub_kitchen")
	EffectApplier.move_player("hub_office")
	for order_id: String in ["ord_slice_test", "ord_private_01", "ord_state_01"]:
		_check(EffectApplier.accept_order(order_id) == OK, "The journal accepts the existing delivery " + order_id)
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	var button: Button = view.find_child("OpenQuests", true, false)
	var space: Control = view.get_node("%SpaceContainer")
	_check(button.text == "Задание" and space.get_global_rect().encloses(button.get_global_rect()), "The flight quest button overlays the map")
	_check(button.get_global_rect().position.x > space.get_global_rect().get_center().x and button.get_global_rect().position.y - space.global_position.y < 12, "The button sits at the upper right")
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_check(button.get_theme_stylebox(state) is StyleBoxEmpty, "The quest button has a transparent " + state + " background")
	var indicators: Control = view.find_child("Indicators", true, false)
	await _check_green(indicators, "earth_2", true)
	await _check_green(indicators, "earth_3", false)
	for row: Control in indicators.get_children():
		if row.visible:
			_check(not row.get_global_rect().intersects(button.get_global_rect()), "Planet pointers leave the quest button clear")
	await _capture("flight")
	await _click(button)
	var journal: Control = view.get_node("QuestJournal")
	var content: VBoxContainer = journal.find_child("Quests", true, false)
	_check(content.get_child_count() == 4 and content.has_node("shop_quest_01") and content.has_node("ord_slice_test"), "All accepted delivery and shop tasks share the journal")
	_check(content.get_node("ord_slice_test").find_child("Description", true, false).text == DataLoader.get_record("ord_slice_test")["description"], "The journal reads the order description from JSON")
	_check("Колония-3" in content.get_node("ord_private_01").find_child("Destination", true, false).text, "A remote delivery names its destination system")
	_check("Планета-3" in content.get_node("ord_state_01").find_child("Destination", true, false).text, "The destination planet is named")
	_check("250" in _all_text(content.get_node("ord_slice_test")) and "Осталось 1" in _all_text(content.get_node("ord_slice_test")), "Payment and remaining deadline are readable")
	_check("TODO scene text" in _all_text(content.get_node("shop_quest_01")) and "1" in _all_text(content.get_node("shop_quest_01")), "Shop tasks have a placeholder description and their requirement")
	var flight: Dictionary = GameState.state["flight"]
	var snapshot: Dictionary = GameState.serialize()
	view._physics_process(1.0)
	await _click_at(space.get_global_rect().get_center())
	_key(KEY_SPACE)
	_key(KEY_M)
	await _frames()
	_check(GameState.serialize() == snapshot and not view.has_node("GalaxyMap"), "Reading blocks flight simulation, steering and map hotkeys without changing saved pause state")
	await _capture("journal")
	_check(GameState.save_game("user://journal.json") == OK and GameState.load_game("user://journal.json") == OK, "The journal works with the existing save format")
	await _frames()
	_check(journal.find_child("Quests", true, false).get_child_count() == 4, "Loading refreshes an open journal")
	await _click(journal.find_child("Close", true, false))
	flight = GameState.state["flight"]
	EffectApplier.set_flight_target(Motion.point(flight["pos"]) + Vector2(100, 0))
	var before: Array = flight["pos"].duplicate()
	view._physics_process(0.1)
	_check(flight["pos"] != before and not flight["paused"], "Closing the journal resumes a previously running flight")
	EffectApplier.toggle_flight_pause()
	await _click(button)
	await _click(view.get_node("QuestJournal").find_child("Close", true, false))
	_check(flight["paused"], "Closing the journal preserves an existing manual pause")
	await _click(view.get_node("%Map"))
	var map: Control = view.get_node("GalaxyMap")
	var map_button: Button = map.find_child("OpenQuests", true, false)
	var rect_before: Rect2 = map_button.get_global_rect()
	var scroll: ScrollContainer = map.get_node("%MapSurface/ChartScroll")
	scroll.scroll_horizontal = 200
	scroll.scroll_vertical = 100
	await _frames()
	_check(map_button.get_global_rect() == rect_before, "Scrolling the galaxy chart leaves its quest button pinned")
	await _capture("galaxy")
	await _click(map_button)
	_check(map.get_node("QuestJournal").find_child("Quests", true, false).get_child_count() == 4, "The galaxy map opens the same accepted tasks")
	await _capture("galaxy-journal")
	await _click(map.get_node("QuestJournal").find_child("Close", true, false))
	await _click(map.get_node("%Close"))
	await _check_pointer_updates(view, indicators)
	view.queue_free()
	await _frames()


func _check_pointer_updates(view: Control, indicators: Control) -> void:
	var order: Dictionary = DataLoader.records["ord_private_01"]
	var original: Dictionary = order.duplicate(true)
	order["to"] = "sys_earth"
	order["to_planet"] = "earth_2"
	_check(Conditions.planet_has_active_delivery("earth_2"), "Multiple active deliveries can point to one planet")
	GameState.state["flight"]["pos"] = Conditions.space_object("earth_2")["pos"].duplicate()
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	_check(EffectApplier.deliver_order("ord_slice_test") == OK, "The local delivery can be handed in")
	GameState.state["flight"]["pos"] = [300.0, 540.0]
	GameState.state["flight"]["target"] = [300.0, 540.0]
	EffectApplier.flight_changed.emit()
	await _frames()
	await _check_green(indicators, "earth_2", true)
	_check(EffectApplier.settle_order("ord_private_01", "failed", false) == OK, "The last local task can be removed")
	await _frames()
	await _check_green(indicators, "earth_2", false)
	await _click(view.find_child("OpenQuests", true, false))
	var content: VBoxContainer = view.get_node("QuestJournal").find_child("Quests", true, false)
	_check(content.get_node("ord_slice_test").find_child("Status", true, false).text == "Выполнено" and content.get_node("ord_private_01").find_child("Status", true, false).text == "Провалено", "Completed and failed tasks retain their explicit status in the journal")
	Clock.advance_slots(20)
	await _frames()
	_check(content.get_node("ord_state_01").find_child("Status", true, false).text == "Провалено" and content.get_node("shop_quest_01").find_child("Status", true, false).text == "Выполняется", "Deadline expiry updates the journal status while shop tasks remain active")
	order.merge(original, true)


func _check_green(indicators: Control, planet_id: String, green: bool) -> void:
	var row: Control = indicators.get_node(planet_id)
	var color: Color = row.get_node("Content/Name").get_theme_color("font_color")
	_check(row.visible and (color == Indicators.QUEST_COLOR) == green, "The " + planet_id + " pointer has the correct quest color")
	if row.visible:
		await RenderingServer.frame_post_draw
		var arrow: Control = row.get_node("Content/Arrow")
		var pixels: Image = get_viewport().get_texture().get_image()
		var point: Vector2 = arrow.get_global_rect().get_center() * Vector2(pixels.get_size()) / get_viewport().get_visible_rect().size
		var rendered: Color = pixels.get_pixel(int(point.x), int(point.y))
		_check((rendered.g > rendered.b + 0.2) == green, "The rendered arrow matches the target's quest state")


func _all_text(node: Node) -> String:
	var result: String = node.text if node is Label else ""
	for child: Node in node.get_children():
		result += "\n" + _all_text(child)
	return result


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)


func _click(button: Button) -> void:
	await _frames()
	await _click_at(button.get_global_rect().get_center())


func _click_at(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-journal" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/quest-" + suffix + ".png") == OK, "The " + suffix + " journal interface renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
