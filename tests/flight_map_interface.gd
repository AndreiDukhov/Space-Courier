extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Service = preload("res://scripts/hub_service.gd")
const Validator = preload("res://scripts/data_validator.gd")
const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "The new interface content validates")
	await _check_hub()
	await _check_flight()
	_check_validation()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Flight map interface checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _check_hub() -> void:
	_new_game()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	var shop: Button = hub.get_node("%Locations/hub_shop/Travel")
	_check(shop.disabled and shop.has_node("ClosedShade/Closed") and "Закрыто" == shop.get_node("ClosedShade/Closed").text, "Closed shop cards are disabled and explicitly labelled")
	_check(shop.get_node("ClosedShade").get_theme_stylebox("panel").bg_color.r == shop.get_node("ClosedShade").get_theme_stylebox("panel").bg_color.g, "Closed cards have a neutral grey backing")
	await _click(shop)
	_check(GameState.state["location"] == "hub_kitchen", "Clicking a closed location cannot enter it")
	var frame: StyleBoxFlat = hub.get_node("%Locations/hub_kitchen/Travel/Frame").get_theme_stylebox("panel")
	_check(frame.border_color == Color.BLACK and frame.border_width_left == 6, "Room frames are wider and black")
	_check(hub.get_node("%Locations").get_global_rect().position.y < 16, "Room navigation is moved to the top edge")
	await _capture("closed")
	var hotspot: Control = hub.get_node("KitchenHotspot")
	var cook: Button = hotspot.get_node("Cook")
	_check(hotspot.visible and not hub.find_child("DomesticActions", true, false).has_node("kitchen"), "The kitchen is entered through the pictured counter")
	var hover: InputEventMouseMotion = InputEventMouseMotion.new()
	hover.position = cook.get_global_rect().get_center()
	get_viewport().push_input(hover, true)
	await _frames()
	_check(get_viewport().gui_get_hovered_control() == cook and hotspot.get_node("Hint").visible and hotspot.get_node("Hint").text == "Начать Готовку", "Hovering the counter immediately shows its cooking action")
	_check(hotspot.get_node("Hint").get_global_rect().position.distance_to(hover.position) < 45, "The cooking hint appears beside the pointer")
	await _capture("hall")
	await _click(cook)
	_check(hub.find_child("Domestic", true, false) != null and hub._domestic.tab == "kitchen", "A real counter click opens the existing cooking screen")
	await _click(hub._domestic.find_child("Close", true, false))
	await _click(hub.get_node("%Wait"))
	shop = hub.get_node("%Locations/hub_shop/Travel")
	_check(not shop.disabled and not shop.has_node("ClosedShade"), "Opening time removes the closed state from the card")
	await _click(shop)
	_check(GameState.state["location"] == "hub_shop" and not hotspot.visible, "An open shop is reachable and the counter is inactive outside the hall")
	Service.travel("hub_kitchen")
	Service.travel("hub_office")
	_check(Conditions.location_is_open("hub_shop") and not hub.get_node("%Locations/hub_shop/Travel").has_node("ClosedShade"), "A missing room connection is distinct from closing time")
	await _hover(hub.get_node("OfficeHotspot/Computer"))
	await _capture("office-pc-hover")
	await _click(hub.get_node("OfficeHotspot/Computer"))
	_check(hub.get_node("%Terminal").visible and hub.get_node("%TerminalContent").get_child(0).has_node("%Orders"), "Clicking the pictured office computer opens orders")
	_check(not Conditions.can_launch() and not Conditions.can_use_galaxy_map(), "The office computer is dedicated to orders")
	await _capture("office-computer")
	await _click(hub.get_node("%CloseTerminal"))
	await _click(hub.get_node("%Locations/hub_tech/Travel"))
	await _hover(hub.get_node("TechHotspot/Computer"))
	await _capture("workshop-pc-hover")
	await _click(hub.get_node("TechHotspot/Computer"))
	var menu: Control = hub.get_node("%TerminalContent/ComputerMenu")
	_check(hub.get_node("%Terminal").visible and not menu.get_node("Launch").disabled, "The workshop computer opens the flight menu")
	await _capture("workshop-computer")
	await _click(menu.get_node("Map"))
	_check(hub.has_node("GalaxyMap"), "The workshop computer opens the galaxy map")
	await _click(hub.get_node("GalaxyMap/%Close"))
	Service.travel("hub_kitchen")
	await _check_lighting(hub)
	hub.queue_free()
	await _frames()


func _check_lighting(hub: Control) -> void:
	var samples: Dictionary = {}
	for slot: String in ["morning", "day", "evening", "night"]:
		while Clock.current_slot() != slot:
			Clock.advance_slots()
		await _frames()
		await RenderingServer.frame_post_draw
		var pixels: Image = get_viewport().get_texture().get_image()
		var ambient: float = _sample_luminance(hub, pixels, Vector2(0.58, 0.71))
		var lamp: float = _sample_luminance(hub, pixels, Vector2(0.108, 0.337))
		samples[slot] = Vector2(ambient, lamp)
		await _capture("hall-" + slot)
	_check(samples["evening"].x < samples["day"].x * 0.7, "Evening darkens the room outside light sources")
	_check(samples["evening"].y >= samples["day"].y * 0.8, "Evening preserves bright light sources")
	_check(samples["night"].x < samples["evening"].x * 0.4 and samples["night"].y < samples["evening"].y * 0.2, "Night darkens both the room and its lights")
	Clock.advance_slots()
	Clock.advance_slots(2)
	for room: String in ["hub_office", "hub_tech", "hub_bedroom"]:
		Service.travel("hub_kitchen")
		Service.travel(room)
		await _capture(room + "-evening")


func _sample_luminance(hub: Control, pixels: Image, uv: Vector2) -> float:
	var dimensions: Vector2 = hub.get_node("%Background").texture.get_size()
	var rendered: Vector2 = dimensions * maxf(hub.size.x / dimensions.x, hub.size.y / dimensions.y)
	var point: Vector2 = (hub.size - rendered) * 0.5 + uv * rendered
	point *= Vector2(pixels.get_size()) / hub.size
	var color: Color = pixels.get_pixel(int(point.x), int(point.y))
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


func _check_flight() -> void:
	_new_game()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	var objects: Array = DataLoader.records["sys_earth"]["objects"]
	var station: Dictionary = {"type": "station", "id": "station_ui_test", "name": "TODO Station", "pos": [100, 150], "color": "#88bbdd", "radius": 1.2}
	objects.append(station)
	_check(Validator.validate(DataLoader.records_by_group, DataLoader.record_sources).is_empty(), "The approved station format validates with the existing system")
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	_check(view.find_child("SidebarScroll", true, false) == null and view.find_child("NPCList", true, false) == null, "The flight view has no right sidebar or contact list")
	_check(view.get_node("%SpaceContainer").size.x > view.size.x * 0.9, "The map uses the freed horizontal space")
	var indicators: Control = view.find_child("Indicators", true, false)
	_check(indicators.get_child_count() == 4 and indicators.has_node("station_ui_test"), "Edge indicators include every planet and the station")
	_check(not indicators.has_node("star_earth") and not indicators.has_node("npc_earth_courier") and not indicators.has_node("r_earth_alpha"), "Ships, stars and wormholes do not receive edge indicators")
	for pointer: Control in indicators.get_children():
		if pointer.visible:
			_check(Rect2(Vector2.ZERO, indicators.size).encloses(pointer.get_rect()), "Visible edge labels remain inside the map")
	await _capture("flight")
	var interactions: Control = view.find_child("ObjectInteractions", true, false)
	var distant_ship: Vector2 = view.camera.unproject_position(Motion.world_position(GameState.state["flight"]["npcs"]["npc_earth_courier"]["pos"], 2.8))
	await _click_at(view.get_node("%SpaceContainer").global_position + distant_ship)
	_check(not GameState.state["flight"]["paused"] and not interactions.get_node("npc_earth_courier").visible, "Clicking a distant ship keeps flight running and its actions hidden")
	_check(EffectApplier.pause_at_npc("npc_earth_courier") == ERR_UNAVAILABLE, "The pause action also rejects a distant ship")
	var flight: Dictionary = GameState.state["flight"]
	var npc: Dictionary = flight["npcs"]["npc_earth_transport"]
	npc["timer"] = 10000.0
	flight["pos"] = Motion.coordinates(Motion.point(npc["pos"]) + Vector2(65, 0))
	flight["target"] = flight["pos"].duplicate()
	EffectApplier.flight_changed.emit()
	EffectApplier.set_flight_target(Motion.point(npc["pos"]))
	EffectApplier.advance_flight(0.4)
	_check(not flight["paused"] and flight["encounter"].is_empty(), "Passing a ship keeps the local simulation running")
	_check(not interactions.get_node("npc_earth_transport").visible, "Ship action buttons wait for selection")
	var ship_point: Vector2 = view.camera.unproject_position(Motion.world_position(npc["pos"], 2.8))
	var target_before: Array = flight["target"].duplicate()
	await _click_at(view.get_node("%SpaceContainer").global_position + ship_point)
	_check(flight["paused"] and flight["target"] == target_before, "Clicking the actual ship pauses without changing the current course")
	var snapshot: Dictionary = GameState.serialize()
	EffectApplier.advance_flight(2.0)
	_check(GameState.serialize() == snapshot, "Selection pause freezes the entire local simulation")
	_check(GameState.save_game("user://nearship.json") == OK and GameState.load_game("user://nearship.json") == OK and GameState.serialize() == snapshot, "Selection pause survives the existing save format")
	ship_point = view.camera.unproject_position(Motion.world_position(GameState.state["flight"]["npcs"]["npc_earth_transport"]["pos"], 2.8))
	await _click_at(view.get_node("%SpaceContainer").global_position + ship_point)
	var row: Control = interactions.get_node("npc_earth_transport")
	await _frames()
	_check(row.visible and not row.get_node("Trade").disabled and not row.get_node("Dialogue").disabled, "Transport actions appear above its ship while paused")
	_check(not interactions.get_node("npc_earth_courier").has_node("Trade"), "Ordinary ships offer dialogue without a transport shop")
	await _capture("ship")
	await _click(row.get_node("Trade"))
	var trade: Control = view.get_node_or_null("NPCTrade")
	_check(trade != null and trade.find_child("Buy_carrot", true, false) != null, "The overhead Trade button opens the data-defined transport shop")
	if trade != null:
		await _capture("trade")
		await _click(trade.find_child("Buy_carrot", true, false))
		_check(GameState.state["money"] == 990 and GameState.state["inventory"].size() == 1, "Transport purchases use the shared money and inventory effects")
		await _click(trade.find_child("Close", true, false))
	await _click(row.get_node("Dialogue"))
	_check(view.get_node("%EncounterLayer").visible and GameState.state["flight"]["encounter"] == "event_transport_test", "The overhead Dialogue button opens the existing encounter while paused")
	await _capture("dialogue")
	await _click(view.get_node("%FlightEncounter/%EventChoices/Option0"))
	_check(GameState.state["flight"]["paused"] and GameState.state["flight"]["encounter"].is_empty(), "Closing dialogue leaves the player in control of resuming flight")
	await _click(view.get_node("%Pause"))
	_check(not GameState.state["flight"]["paused"], "The toolbar resumes flight after selecting a ship")
	GameState.state["flight"]["pos"] = Conditions.space_object("earth_1")["pos"].duplicate()
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	EffectApplier.flight_changed.emit()
	await _frames()
	_check(not indicators.get_node("earth_1").visible, "A planet's edge indicator disappears when the planet enters the view")
	_check(not interactions.get_node("npc_earth_transport").is_visible_in_tree() and not Conditions.can_trade_npc("npc_earth_transport"), "Leaving the ship removes its actions and trade access")
	var point: Vector2 = view.get_node("%SpaceContainer").get_global_rect().get_center() + Vector2(130, 60)
	await _click_at(point)
	_check(GameState.state["flight"]["target"] != GameState.state["flight"]["pos"], "Pointer overlays preserve map steering through normal mouse input")
	await _capture("planet")
	view.queue_free()
	await _frames()
	objects.erase(station)


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["npcs"][0]["shop"] = "missing_shop"
	_check("missing_shop" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Transport shop references are validated")
	groups = DataLoader.records_by_group.duplicate(true)
	for record: Dictionary in groups["ui"]:
		if record["id"] == "hub_kitchen_hotspot":
			record["zones"]["cook"]["drop_rect"] = [0, 0, 2, 1]
	_check("drop_rect must stay inside" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "The hall hotspot must stay within its image")
	groups = DataLoader.records_by_group.duplicate(true)
	for record: Dictionary in groups["ui"]:
		if record["id"] == "hub_lighting":
			record["slots"]["night"]["ambient"] = -1
			record["locations"]["missing_room"] = {"light_rects": []}
	var errors: String = "\n".join(Validator.validate(groups, DataLoader.record_sources))
	_check("nonnegative finite ambient" in errors and "missing_room" in errors, "Lighting validates brightness and location references")


func _click(button: Button) -> void:
	await _frames()
	await _click_at(button.get_global_rect().get_center())


func _hover(button: Button) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = button.get_global_rect().get_center()
	get_viewport().push_input(event, true)
	await _frames()


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
	if "--capture-map-interface" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/map-interface-" + suffix + ".png") == OK, "The " + suffix + " interface renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
