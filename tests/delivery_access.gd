extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Service = preload("res://scripts/hub_service.gd")
const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Delivery and location data validates")
	await _check_bedroom()
	await _check_colony_delivery()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Delivery access checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _check_bedroom() -> void:
	_new_game()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	for _slot: int in range(4):
		for room: Dictionary in DataLoader.get_records("locations"):
			if room.get("area") != "hub":
				continue
			GameState.state["location"] = room["id"]
			EffectApplier.location_changed.emit(str(room["id"]))
			_check(Conditions.can_enter("hub_bedroom"), "The bedroom is reachable from " + str(room["id"]) + " during " + Clock.current_slot())
			_check(not hub.get_node("%Locations/hub_bedroom/Travel").disabled, "The bedroom card is enabled from " + str(room["id"]) + " during " + Clock.current_slot())
		Clock.advance_slots()
	GameState.state["location"] = "hub_office"
	EffectApplier.location_changed.emit("hub_office")
	await _click(hub.get_node("%Locations/hub_bedroom/Travel"))
	_check(GameState.state["location"] == "hub_bedroom", "A real click enters the bedroom directly from the office")
	_check(Service.travel("hub_office") == OK, "The bedroom has a return path to the office")
	hub.queue_free()
	await _frames()


func _check_colony_delivery() -> void:
	_new_game()
	EffectApplier.move_player("hub_office")
	_check(EffectApplier.accept_order("ord_private_01") == OK, "The regular colony delivery can be accepted")
	_check(EffectApplier.accept_order("ord_state_01") == OK, "A second delivery can target the same planet")
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	for npc: Dictionary in DataLoader.get_records("npcs"):
		GameState.state["flight"]["defeated_npcs"].append(npc["id"])
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true})
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	for route_id: String in ["r_earth_alpha", "r_alpha_colony"]:
		var gate: Dictionary = Conditions.space_object(route_id)
		await _fly_with_mouse(view, gate["pos"])
		var enter: Button = view.find_child("ObjectInteractions", true, false).get_node(route_id + "/Enter")
		_check(enter.is_visible_in_tree() and not enter.disabled, "The physical route reaches " + route_id)
		await _click(enter)
	_check(GameState.state["current_system"] == "sys_colony_3" and Clock.current_day() == 3 and OrderManager.status("ord_private_01") == "active", "The two-day journey reaches the colony before the deadline expires")
	var planet: Dictionary = Conditions.space_object("colony_3_1")
	await _fly_with_mouse(view, planet["pos"])
	var row: Control = view.find_child("ObjectInteractions", true, false).get_node("colony_3_1")
	_check(row.is_visible_in_tree() and row.get_node("Dialogue").is_visible_in_tree(), "Planet dialogue appears after a mouse-driven approach to the colony")
	var surface_distance: float = float(planet["radius"]) / Motion.WORLD_SCALE + Motion.INTERACTION_RADIUS - 2.0
	GameState.state["flight"]["pos"] = Motion.coordinates(Motion.point(planet["pos"]) + Vector2(surface_distance, 0))
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	EffectApplier.flight_changed.emit()
	await _frames()
	_check(row.is_visible_in_tree() and not row.get_node("Dialogue").disabled and Conditions.can_deliver_order("ord_private_01"), "Interaction range is measured from the visible planet surface")
	var delivery: Button = row.get_node_or_null("Deliver_ord_private_01")
	_check(delivery != null and delivery.is_visible_in_tree() and not delivery.disabled, "The colony exposes a direct delivery button above the planet")
	var second: Button = row.get_node_or_null("Deliver_ord_state_01")
	_check(second != null and second.is_visible_in_tree(), "Multiple orders have separate visible hand-in buttons")
	_check(row.size.x <= view.get_node("%SpaceContainer").size.x and row.size.y <= view.get_node("%SpaceContainer").size.y, "Delivery actions fit inside the map")
	await _capture("colony")
	if delivery != null:
		_check(GameState.save_game("user://delivery-edge.json") == OK and GameState.load_game("user://delivery-edge.json") == OK, "Approaching a delivery destination survives save and load")
		delivery = view.find_child("ObjectInteractions", true, false).get_node("colony_3_1/Deliver_ord_private_01")
		await _click(delivery)
		_check(OrderManager.status("ord_private_01") == "completed" and GameState.state["money"] == 1600 and OrderManager.active_mass() == float(DataLoader.get_record("ord_state_01")["cargo"]["mass"]), "The direct button pays the colony reward and releases only that order's cargo")
		_check(EffectApplier.deliver_order("ord_private_01") == ERR_UNAVAILABLE and GameState.state["money"] == 1600, "Repeated delivery cannot duplicate the reward")
		_check(not view.find_child("ObjectInteractions", true, false).get_node("colony_3_1").has_node("Deliver_ord_private_01"), "The completed delivery button is removed")
		second = view.find_child("ObjectInteractions", true, false).get_node("colony_3_1/Deliver_ord_state_01")
		await _click(second)
		_check(OrderManager.status("ord_state_01") == "completed" and OrderManager.active_mass() == 0, "The second order can be handed in independently")
		_check(GameState.save_game("user://delivered.json") == OK and GameState.load_game("user://delivered.json") == OK and OrderManager.active_mass() == 0, "Completed deliveries remain completed after loading")
	view.queue_free()
	await _frames()
	await _check_uninhabited_and_expired()


func _check_uninhabited_and_expired() -> void:
	_new_game()
	var original: String = str(DataLoader.records["ord_slice_test"]["to_planet"])
	DataLoader.records["ord_slice_test"]["to_planet"] = "earth_3"
	EffectApplier.move_player("hub_office")
	EffectApplier.accept_order("ord_slice_test")
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["flight"]["pos"] = Conditions.space_object("earth_3")["pos"].duplicate()
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	var row: Control = view.find_child("ObjectInteractions", true, false).get_node("earth_3")
	_check(row.is_visible_in_tree() and not row.has_node("Trade") and not row.has_node("Dialogue") and row.has_node("Deliver_ord_slice_test"), "A valid delivery to an uninhabited planet has a hand-in action")
	Clock.advance_slots(8)
	await _frames()
	row = view.find_child("ObjectInteractions", true, false).get_node("earth_3")
	_check(OrderManager.status("ord_slice_test") == "failed" and not row.visible and not row.has_node("Deliver_ord_slice_test"), "Expired orders lose their direct hand-in action")
	view.queue_free()
	await _frames()
	DataLoader.records["ord_slice_test"]["to_planet"] = original


func _fly_with_mouse(view: Control, destination: Array) -> void:
	for _step: int in range(40):
		if Motion.point(GameState.state["flight"]["pos"]).distance_to(Motion.point(destination)) < 10.0:
			return
		var space: Control = view.get_node("%SpaceContainer")
		var point: Vector2 = view.camera.unproject_position(Motion.world_position(destination, 0.3))
		point = point.clamp(Vector2(64, 64), space.size - Vector2(64, 64))
		await _click_at(space.global_position + point)
		EffectApplier.advance_flight(1.0)
		await _frames()
	_check(false, "Mouse steering reaches its destination")


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
	if "--capture-delivery" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/delivery-access-" + suffix + ".png") == OK, "The delivery controls render")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
