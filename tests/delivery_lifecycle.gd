extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Delivery lifecycle content validates")
	await _check_arrival_and_handover()
	await _check_overdue_arrival()
	_check_autopilot()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Delivery lifecycle checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_office")
	_check(EffectApplier.accept_order("ord_private_01") == OK and EffectApplier.accept_order("ord_state_01") == OK, "Two deliveries to the colony are accepted")
	var snapshot: Dictionary = GameState.serialize()
	_check(OrderManager.complete_test_order("ord_private_01") == ERR_UNAVAILABLE and EffectApplier.settle_order("ord_private_01", "completed") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Legacy and generic completion reject the office")
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	for npc: Dictionary in DataLoader.get_records("npcs"):
		GameState.state["flight"]["defeated_npcs"].append(npc["id"])
	EffectApplier.apply_effects([{"flag": "signal_test_done", "set": true}])


func _flight_view() -> Control:
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	return view


func _check_arrival_and_handover() -> void:
	_launch()
	var view: Control = _flight_view()
	await _frames()
	await _travel(view, ["r_earth_alpha", "r_alpha_colony"])
	_check(Clock.current_day() == 3 and OrderManager.status("ord_private_01") == "active" and OrderManager.status("ord_state_01") == "active", "Arrival on the deadline day keeps both deliveries active")
	_check(GameState.state["money"] == 1000 and OrderManager.active_mass() == 6, "Entering the system preserves payment and cargo")
	_check(not Conditions.can_deliver_order("ord_private_01") and not Conditions.can_settle_order("ord_private_01", "completed", false), "Arrival at the wormhole cannot complete a planetary delivery")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.settle_order("ord_private_01", "completed", false) == ERR_UNAVAILABLE and OrderManager.complete_test_order("ord_private_01") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Every completion entry point rejects distant hand-in without changing state")
	_check(GameState.save_game("user://colony-arrival.json") == OK and GameState.load_game("user://colony-arrival.json") == OK and GameState.serialize() == snapshot, "Saving and loading arrival preserves active cargo and reward")
	await _click(view.find_child("OpenQuests", true, false))
	var content: Control = view.get_node("QuestJournal").find_child("Quests", true, false)
	_check(_status(content, "ord_private_01") == "Выполняется" and _status(content, "ord_state_01") == "Выполняется", "The arrival journal still shows both tasks as active")
	await _capture("arrival")
	await _click(view.get_node("QuestJournal").find_child("Close", true, false))
	var planet: Dictionary = Conditions.space_object("colony_3_1")
	await _position(Conditions.space_object("colony_3_2")["pos"])
	_check(EffectApplier.deliver_order("ord_private_01") == ERR_UNAVAILABLE, "Another planet in the correct system cannot accept the delivery")
	var outside: float = float(planet["radius"]) / Motion.WORLD_SCALE + Motion.INTERACTION_RADIUS + 1.0
	await _position(Motion.coordinates(Motion.point(planet["pos"]) + Vector2(outside, 0)))
	_check(EffectApplier.settle_order("ord_private_01", "completed", false) == ERR_UNAVAILABLE, "The generic completion path enforces distance from the destination surface")
	await _position(planet["pos"])
	_check(Conditions.can_deliver_order("ord_private_01"), "The designated planet accepts the still-active delivery")
	var row: Control = view.find_child("ObjectInteractions", true, false).get_node("colony_3_1")
	await _click(row.get_node("Deliver_ord_private_01"))
	_check(OrderManager.status("ord_private_01") == "completed" and GameState.state["money"] == 1600 and OrderManager.active_mass() == 4, "The explicit planet button delivers exactly one cargo and pays its reward")
	snapshot = GameState.serialize()
	_check(EffectApplier.settle_order("ord_private_01", "completed", false) == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Completed cargo cannot pay twice")
	await _click(view.find_child("OpenQuests", true, false))
	content = view.get_node("QuestJournal").find_child("Quests", true, false)
	_check(_status(content, "ord_private_01") == "Выполнено" and _status(content, "ord_state_01") == "Выполняется", "The journal distinguishes hand-in from the remaining active delivery")
	_check(content.get_child(0).name == "ord_state_01", "Active tasks are listed before closed tasks")
	await _capture("handover")
	view.queue_free()
	await _frames()


func _check_overdue_arrival() -> void:
	_launch()
	var view: Control = _flight_view()
	await _frames()
	await _travel(view, ["r_earth_beta", "r_beta_delta", "r_delta_colony"])
	_check(Clock.current_day() == 4 and OrderManager.status("ord_private_01") == "failed" and OrderManager.status("ord_state_01") == "active", "The longer route expires only the short-deadline contract")
	_check(GameState.state["money"] == 880 and GameState.state["reputation"]["private"] == -1 and OrderManager.active_mass() == 4, "Expired arrival applies the configured penalty instead of a delivery reward")
	await _click(view.find_child("OpenQuests", true, false))
	var content: Control = view.get_node("QuestJournal").find_child("Quests", true, false)
	_check(_status(content, "ord_private_01") == "Провалено" and _status(content, "ord_state_01") == "Выполняется", "An expired contract remains readable beside active tasks")
	_check("3" in content.get_node("ord_private_01").find_child("Deadline", true, false).text, "The closed contract retains its original deadline")
	await _capture("expired")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://expired-arrival.json") == OK and GameState.load_game("user://expired-arrival.json") == OK and GameState.serialize() == snapshot, "Reloading an expired arrival does not repeat its penalty")
	await _frames()
	_check(_status(content, "ord_private_01") == "Провалено", "A loaded expired task remains visible in the open journal")
	await _click(view.get_node("QuestJournal").find_child("Close", true, false))
	await _position(Conditions.space_object("colony_3_1")["pos"])
	_check(not Conditions.can_deliver_order("ord_private_01") and not view.find_child("ObjectInteractions", true, false).get_node("colony_3_1").has_node("Deliver_ord_private_01"), "Expired cargo has no planet hand-in action")
	view.queue_free()
	await _frames()


func _check_autopilot() -> void:
	_launch()
	EffectApplier.apply_effects([{"unlock_route": "r_earth_alpha"}, {"unlock_route": "r_alpha_colony"}])
	_check(EffectApplier.start_autopilot("sys_colony_3") == OK, "A known chain can start an automatic flight with active cargo")
	for _second: int in range(45):
		EffectApplier.advance_flight(1.0)
	_check(GameState.state["current_system"] == "sys_colony_3" and GameState.state["flight"]["autopilot"].is_empty(), "Autopilot reaches the destination system")
	_check(OrderManager.status("ord_private_01") == "active" and GameState.state["money"] == 1000 and OrderManager.active_mass() == 6 and not Conditions.can_deliver_order("ord_private_01"), "Autopilot arrival keeps the delivery awaiting its planet hand-in")


func _travel(view: Control, routes: Array[String]) -> void:
	for route_id: String in routes:
		await _position(Conditions.space_object(route_id)["pos"])
		await _click(view.find_child("ObjectInteractions", true, false).get_node(route_id + "/Enter"))
		_check(GameState.state["current_system"] == DataLoader.get_record(route_id)["to"], "The overhead wormhole button enters " + route_id)


func _position(pos: Array) -> void:
	GameState.state["flight"]["pos"] = pos.duplicate()
	GameState.state["flight"]["target"] = pos.duplicate()
	EffectApplier.flight_changed.emit()
	await _frames()


func _status(content: Control, order_id: String) -> String:
	var card: Control = content.get_node_or_null(order_id)
	return "" if card == null else str(card.find_child("Status", true, false).text)


func _click(button: Button) -> void:
	await _frames()
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
	if "--capture-delivery-lifecycle" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/delivery-lifecycle-" + suffix + ".png") == OK, "The " + suffix + " delivery journal renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
