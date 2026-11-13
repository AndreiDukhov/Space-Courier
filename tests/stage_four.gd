extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Service = preload("res://scripts/hub_service.gd")
const Validator = preload("res://scripts/data_validator.gd")
const HubView = preload("res://scripts/hub.gd")
const SAVE_TEST_PATH: String = "res://.godot/stage-four-save-test.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All order data loads without errors")
	var delivery_orders: Array[Dictionary] = DataLoader.get_records("orders").filter(func(order: Dictionary) -> bool: return order.get("source") != "shop" and order.get("id") != "ord_slice_test")
	_check(delivery_orders.size() == 6, "Six delivery order templates are loaded")
	var counts: Dictionary = {"private": 0, "state": 0, "crime": 0}
	for order: Dictionary in delivery_orders:
		counts[order["source"]] += 1
		_check(DataLoader.record_sources.has("systems/" + str(order["from"])) and DataLoader.record_sources.has("systems/" + str(order["to"])), "Order system references resolve")
	_check(counts == {"private": 2, "state": 2, "crime": 2}, "Every source has two templates")
	_check_reputation()
	_check_lifecycle()
	_check_capacity()
	_check_deadlines()
	_check_tags()
	_check_validation()
	_check_persistence()
	await _check_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 4 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _office() -> void:
	_new_game()
	_check(Service.travel("hub_office") == OK, "The office is inside the building")


func _deliver_at_destination(order_id: String) -> Error:
	var order: Dictionary = DataLoader.get_record(order_id)
	var previous_system: String = str(GameState.state["current_system"])
	var previous_location: String = str(GameState.state["location"])
	var previous_flight: Dictionary = GameState.state["flight"].duplicate(true)
	GameState.state["current_system"] = order["to"]
	GameState.state["location"] = "ship_bridge"
	GameState.state["flight"]["pos"] = Conditions.space_object(str(order["to_planet"]))["pos"].duplicate()
	GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
	var result: Error = OrderManager.complete_test_order(order_id)
	GameState.state["current_system"] = previous_system
	GameState.state["location"] = previous_location
	GameState.state["flight"] = previous_flight
	EffectApplier.orders_changed.emit()
	return result


func _check_reputation() -> void:
	_new_game()
	_check(GameState.state["reputation"] == {"state": 0, "mafia": 0, "private": 0}, "All reputations start neutral")
	_check(Conditions.evaluate([{"rep": "state", "op": ">=", "value": 0}]), "Reputation comparisons use current state")
	_check(not Conditions.evaluate([{"rep": "crime", "op": ">=", "value": 0}]), "Crime uses mafia reputation rather than a fourth scale")
	_check(EffectApplier.apply_effects([{"rep": "state", "add": 150}]) == OK and GameState.state["reputation"]["state"] == 100, "Reputation gains clamp at 100")
	_check(EffectApplier.apply_effects([{"rep": "state", "add": -300}]) == OK and GameState.state["reputation"]["state"] == -100, "Reputation losses clamp at -100")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.apply_effects([{"money": 10}, {"rep": "state", "add": 0.5}]) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid reputation batches preserve state")
	_check(EffectApplier.apply_effects([{"rep": "crime", "add": 1}]) == ERR_INVALID_DATA, "Unknown reputation names are rejected")


func _check_lifecycle() -> void:
	_new_game()
	var snapshot: Dictionary = GameState.serialize()
	_check(OrderManager.accept("ord_private_01") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Orders cannot be accepted outside the office terminal")
	_check(not Conditions.can_enter("ship_bridge") and not Conditions.can_use_order_terminal(), "The building is separate from the ship")
	_check(Service.travel("hub_office") == OK and Conditions.can_use_order_terminal(), "The office exposes the order terminal")
	_check(not Conditions.can_accept_order("ord_private_02"), "Reputation gates initially lock advanced orders")
	_check(OrderManager.accept("ord_private_01") == OK, "A valid offer can be accepted")
	_check(GameState.state["orders"]["ord_private_01"] == {"status": "active", "accepted_day": 1}, "Only the agreed runtime fields are stored")
	_check(GameState.state["money"] == 1000 and OrderManager.active_mass() == 2, "Accepting reserves cargo without paying a reward")
	snapshot = GameState.serialize()
	_check(OrderManager.accept("ord_private_01") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Repeated acceptance cannot duplicate cargo")
	_check(OrderManager.accept("missing") == ERR_UNAVAILABLE, "Unknown order ids are rejected")
	_check(_deliver_at_destination("ord_private_01") == OK, "The test delivery can be completed")
	_check(OrderManager.status("ord_private_01") == "completed" and GameState.state["money"] == 1600 and GameState.state["reputation"]["private"] == 1, "Completion applies money and reputation rewards")
	_check(OrderManager.active_mass() == 0 and Conditions.can_accept_order("ord_private_02"), "Completion frees cargo and opens the next offer")
	snapshot = GameState.serialize()
	_check(_deliver_at_destination("ord_private_01") == ERR_UNAVAILABLE and OrderManager.fail("ord_private_01") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Closed orders cannot pay out or fail again")
	_check(OrderManager.accept("ord_private_02") == OK and OrderManager.fail("ord_private_02") == OK, "An active order can be failed")
	_check(OrderManager.status("ord_private_02") == "failed" and GameState.state["money"] == 1350 and GameState.state["reputation"]["private"] == -1, "Private failure applies the configured penalty")
	_check(OrderManager.active_mass() == 0, "Failure releases reserved cargo")
	_office()
	_check(OrderManager.accept("ord_private_01") == OK, "The atomic settlement test accepts a fresh order")
	var record: Dictionary = DataLoader.records["ord_private_01"]
	var reward: Array = record["reward"]
	record["reward"] = [{"money": 10}, {"stat": "missing.mood", "add": 1}]
	snapshot = GameState.serialize()
	_check(_deliver_at_destination("ord_private_01") == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid rewards do not close an order or partially pay out")
	record["reward"] = reward
	_check(_deliver_at_destination("ord_private_01") == OK, "Corrected reward data can settle the still-active order")


func _check_capacity() -> void:
	_office()
	_check(OrderManager.accept("ord_private_01") == OK and OrderManager.accept("ord_state_01") == OK and OrderManager.accept("ord_crime_01") == OK, "Multiple orders reserve their combined cargo")
	_check(OrderManager.active_mass() == 8, "Active cargo mass is derived from order definitions")
	_check(EffectApplier.apply_effects([{"rep": "private", "add": 1}]) == OK, "The capacity test opens its reputation gate")
	var snapshot: Dictionary = GameState.serialize()
	_check(not Conditions.can_accept_order("ord_private_02") and OrderManager.accept("ord_private_02") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Capacity prevents accepting an otherwise unlocked order")
	_check(_deliver_at_destination("ord_state_01") == OK and OrderManager.active_mass() == 4, "Delivered cargo immediately frees capacity")
	_check(OrderManager.accept("ord_state_02") == OK and OrderManager.active_mass() == 9, "Freed capacity and reputation unlock a larger contract")
	_check(OrderManager.fail("ord_state_02") == OK and OrderManager.accept("ord_private_02") == OK and OrderManager.active_mass() == 7, "Failed cargo can be replaced by another contract")
	_office()
	GameState.state["ship"]["cargo"]["max_mass"] = 2.5
	_check(OrderManager.accept("ord_private_01") == OK and GameState.restore(GameState.serialize()) == OK, "Fractional cargo capacity remains valid")


func _check_deadlines() -> void:
	_office()
	_check(OrderManager.accept("ord_private_01") == OK and OrderManager.deadline_day("ord_private_01") == 3, "Deadlines are relative to the acceptance day")
	Clock.advance_slots(8)
	_check(Clock.current_day() == 3 and OrderManager.status("ord_private_01") == "active" and OrderManager.remaining_days("ord_private_01") == 0, "The deadline day itself remains usable")
	_check(_deliver_at_destination("ord_private_01") == OK, "A delivery can finish on its deadline day")
	Clock.advance_slots(4)
	_check(GameState.state["money"] == 1600 and OrderManager.status("ord_private_01") == "completed", "Completed orders are not expired later")
	_office()
	_check(OrderManager.accept("ord_private_01") == OK, "The expiration test accepts an order")
	Clock.advance_slots(12)
	_check(OrderManager.status("ord_private_01") == "failed" and GameState.state["money"] == 880 and GameState.state["reputation"]["private"] == -1, "The next day after the deadline applies one failure")
	_check(OrderManager.active_mass() == 0 and GameState.state["location"] == "hub_office", "Expiration releases cargo and keeps the game running")
	Clock.advance_slots(8)
	OrderManager.check_expired()
	_check(GameState.state["money"] == 880 and GameState.state["reputation"]["private"] == -1, "Expired orders cannot apply repeated penalties")
	_office()
	_check(OrderManager.accept("ord_private_01") == OK and OrderManager.accept("ord_state_01") == OK and OrderManager.accept("ord_crime_01") == OK, "Orders with different deadlines can coexist")
	Clock.advance_slots(12)
	_check(OrderManager.status("ord_private_01") == "failed" and OrderManager.status("ord_crime_01") == "failed" and OrderManager.status("ord_state_01") == "active", "Expiration checks every contract independently")
	_check(GameState.state["flags"].get("mafia_hunt", false) and GameState.state["reputation"]["mafia"] == -4 and OrderManager.active_mass() == 4, "Crime failure enables the hunt flag and frees only its cargo")
	Clock.advance_slots(4)
	_check(OrderManager.status("ord_state_01") == "failed" and GameState.state["reputation"]["state"] == -4 and OrderManager.active_mass() == 0, "State failure reduces social reputation")
	_office()
	GameState.state["money"] = 0
	_check(OrderManager.accept("ord_private_01") == OK and OrderManager.fail("ord_private_01") == OK and GameState.state["money"] == -120, "A monetary penalty can create debt without ending the game")


func _check_tags() -> void:
	_office()
	_check(OrderManager.accept("ord_crime_01") == OK and _deliver_at_destination("ord_crime_01") == OK, "A crime delivery uses its success path")
	_check(GameState.state["heroines"]["pilot"]["attitude"] == 25 and GameState.state["heroines"]["medic"]["attitude"] == 20, "Only aboard crew reacts to action tags")
	_check(GameState.state["money"] == 2600 and GameState.state["reputation"]["mafia"] == 2, "Crime rewards affect mafia reputation")
	_office()
	GameState.state["heroines"]["medic"]["aboard"] = true
	GameState.state["ship"]["crew_aboard"].append("medic")
	_check(OrderManager.accept("ord_state_01") == OK and _deliver_at_destination("ord_state_01") == OK, "A state delivery applies legal action tags")
	_check(GameState.state["heroines"]["pilot"]["attitude"] == 18 and GameState.state["heroines"]["medic"]["attitude"] == 22, "The same action uses each heroine's own tag weights")
	_office()
	GameState.state["heroines"]["pilot"]["mood"] = 70
	_check(OrderManager.accept("ord_crime_01") == OK and _deliver_at_destination("ord_crime_01") == OK and is_equal_approx(GameState.state["heroines"]["pilot"]["attitude"], 26.25), "Tag reactions use the central mood multiplier")
	_office()
	_check(OrderManager.accept("ord_crime_01") == OK and OrderManager.fail("ord_crime_01") == OK and GameState.state["heroines"]["pilot"]["attitude"] == 20, "Failure does not replay success action tags")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["cargo"]["mass"] = -1
	_check("cargo mass must be positive" in "\n".join(Validator.validate(groups, {})), "Invalid cargo mass is reported at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["deadline_days"] = 1.5
	_check("deadline_days must be a positive integer" in "\n".join(Validator.validate(groups, {})), "Fractional deadlines are rejected")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["requires"] = [{"rep": "crime", "op": ">=", "value": 0}]
	_check("Invalid reputation comparison" in "\n".join(Validator.validate(groups, {})), "Unknown reputation names are reported in requirements")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["from"] = "missing"
	_check("unknown systems id 'missing'" in "\n".join(Validator.validate(groups, {})), "Order endpoints are validated by id")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["reward"] = [{"rep": "mafia", "add": "invalid"}]
	_check("Invalid reputation effect" in "\n".join(Validator.validate(groups, {})), "Invalid reward schemas are reported before play")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["orders"][0]["action_tags"] = [42]
	_check("action_tags must contain nonempty strings" in "\n".join(Validator.validate(groups, {})), "Action tags are checked structurally")


func _check_persistence() -> void:
	_office()
	_check(OrderManager.accept("ord_private_01") == OK and _deliver_at_destination("ord_private_01") == OK and OrderManager.accept("ord_private_02") == OK and OrderManager.accept("ord_state_01") == OK, "The save test has closed and active orders")
	_check(EffectApplier.apply_effects([{"rep": "mafia", "add": 6}]) == OK, "The save test stores non-neutral reputation")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE_TEST_PATH) == OK, "Orders and reputation save to JSON")
	_new_game()
	_check(GameState.load_game(SAVE_TEST_PATH) == OK and GameState.serialize() == snapshot, "Order states and acceptance days restore exactly")
	_check(OrderManager.active_mass() == 7 and OrderManager.deadline_day("ord_private_02") == 5, "Restored reservations and deadlines retain their original values")
	_check(GameState.load_game(SAVE_TEST_PATH) == OK and GameState.state["money"] == 1600, "Reloading completed orders does not replay rewards")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["reputation"]["state"] = 101
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Out-of-range saved reputation is rejected")
	invalid = snapshot.duplicate(true)
	invalid["reputation"].erase("mafia")
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "All three reputation fields are required")
	invalid = snapshot.duplicate(true)
	invalid["orders"]["ord_private_02"]["status"] = "unknown"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unknown saved order states are rejected")
	invalid = snapshot.duplicate(true)
	invalid["orders"]["ord_private_02"]["accepted_day"] = 2
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Future acceptance days are rejected")
	invalid = snapshot.duplicate(true)
	invalid["orders"]["ord_private_02"]["deadline_day"] = 5
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unapproved runtime fields are rejected")
	invalid = snapshot.duplicate(true)
	invalid["orders"]["missing"] = {"status": "active", "accepted_day": 1}
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unknown order ids cannot enter a save")
	invalid = snapshot.duplicate(true)
	invalid["ship"]["cargo"]["max_mass"] = 6
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "An overloaded saved hold is rejected")
	_check(GameState.serialize() == snapshot, "Invalid order snapshots preserve the current game")
	var expired: Dictionary = snapshot.duplicate(true)
	expired["day"] = 6
	_check(GameState.restore(expired) == OK, "An older active order snapshot can be checked on load")
	_check(OrderManager.status("ord_private_02") == "failed" and OrderManager.status("ord_state_01") == "failed" and GameState.state["money"] == 1350, "Overdue orders settle once after loading")
	var settled: Dictionary = GameState.serialize()
	_check(GameState.restore(settled) == OK and GameState.serialize() == settled, "Restoring settled failures does not repeat penalties")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH)) == OK, "The order verification save is removed")


func _check_view() -> void:
	_new_game()
	var packed_scene: PackedScene = load("res://scenes/hub.tscn")
	var view: HubView = packed_scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	_check(not view.get_node("%Locations").has_node("ship_bridge") and view.get_node("%Locations").has_node("hub_office"), "Building navigation shows the office rather than ship rooms")
	_check(not view.get_node("OfficeHotspot").visible and not view.open_order_terminal(), "The terminal is unavailable in the main hall")
	view.get_node("%Locations/hub_office/Travel").pressed.emit()
	_check(GameState.state["location"] == "hub_office" and view.get_node("OfficeHotspot").visible, "The office exposes its PC action")
	view.get_node("OfficeHotspot/Computer").pressed.emit()
	_check(view.get_node("%Terminal").visible, "The PC opens its terminal overlay")
	_check(not view.get_node("%LocationPanel").visible, "The terminal hides room controls behind its overlay")
	var terminal: Control = view.get_node("%TerminalContent").get_child(0)
	_check(terminal.get_node("%Orders").get_child_count() == 7, "The original six offers and the vertical-slice delivery are shown")
	_check(not _button(terminal, "ord_private_01", "Accept").disabled and _button(terminal, "ord_private_02", "Accept").disabled, "Reputation gates affect the accept controls")
	_check(_button(terminal, "ord_private_01", "Complete") == null, "The office no longer offers instant delivery")
	var old_accept: Button = _button(terminal, "ord_private_01", "Accept")
	old_accept.pressed.emit()
	_check(OrderManager.status("ord_private_01") == "active" and _button(terminal, "ord_private_01", "Accept").disabled, "Accepting updates the card and closes duplicate acceptance")
	old_accept.pressed.emit()
	_check(OrderManager.active_mass() == 2 and GameState.state["orders"].size() == 1, "A stale button cannot accept the same offer twice")
	_deliver_at_destination("ord_private_01")
	_check(GameState.state["money"] == 1600 and GameState.state["reputation"]["private"] == 1, "The settlement fixture applies rewards to test terminal refresh")
	_check(not _button(terminal, "ord_private_02", "Accept").disabled and _button(terminal, "ord_private_01", "Accept").disabled, "The terminal opens new offers and closes resolved actions")
	_check("1600" in terminal.get_node("%Resources").text and "private: 1" in terminal.get_node("%Reputation").text, "Resource and reputation readouts refresh after delivery")
	await get_tree().process_frame
	_check(not terminal.get_node("%Resources").get_global_rect().intersects(view.get_node("%CloseTerminal").get_global_rect()), "The power button does not overlap resource values")
	await _capture(view, "completed")
	_button(terminal, "ord_state_01", "Accept").pressed.emit()
	_button(terminal, "ord_state_01", "Fail").pressed.emit()
	_check(OrderManager.status("ord_state_01") == "failed" and "state: -4" in terminal.get_node("%Reputation").text, "The fail button applies state reputation penalties")
	_button(terminal, "ord_crime_01", "Accept").pressed.emit()
	view.get_node("%CloseTerminal").pressed.emit()
	_check(not view.get_node("%Terminal").visible and OrderManager.status("ord_crime_01") == "active" and OrderManager.active_mass() == 2, "Closing the PC preserves its active orders")
	await get_tree().process_frame
	view.get_node("OfficeHotspot/Computer").pressed.emit()
	terminal = view.get_node("%TerminalContent").get_child(0)
	_check(_button(terminal, "ord_crime_01", "Accept").disabled and not _button(terminal, "ord_crime_01", "Fail").disabled, "Reopening the PC restores active order controls")
	for _turn_index: int in range(12):
		view.get_node("%Wait").pressed.emit()
	_check(view.get_node("%Terminal").visible and OrderManager.status("ord_crime_01") == "failed" and GameState.state["flags"].get("mafia_hunt", false), "A deadline can expire while the PC remains open")
	_check("mafia: -4" in terminal.get_node("%Reputation").text and OrderManager.active_mass() == 0, "Expiration refreshes reputation and cargo controls")
	await get_tree().process_frame
	await _capture(view, "expired")
	view.get_node("%Locations/hub_kitchen/Travel").pressed.emit()
	_check(not view.get_node("%Terminal").visible and not view.get_node("OfficeHotspot").visible, "Leaving the office closes its terminal")
	_check(view.get_node("%LocationPanel").visible, "Leaving the PC restores current room controls")
	_check(not view.open_order_terminal(), "The PC cannot be reopened remotely")
	view.queue_free()
	await get_tree().process_frame


func _button(terminal: Control, order_id: String, action: String) -> Button:
	return terminal.get_node("%Orders").get_node(order_id).find_child(action, true, false) as Button


func _capture(view: Control, suffix: String) -> void:
	if "--capture-orders" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = view.get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "The order terminal viewport is rendered")
	if image != null and not image.is_empty():
		_check(image.save_png("res://.godot/stage-four-" + suffix + ".png") == OK, "The order terminal screenshot is saved")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
