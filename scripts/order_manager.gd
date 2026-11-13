extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Inventory = preload("res://scripts/inventory.gd")


func _ready() -> void:
	Clock.day_changed.connect(_on_day_changed)
	GameState.restored.connect(check_expired)


func status(order_id: String) -> String:
	return str(GameState.state.get("orders", {}).get(order_id, {}).get("status", ""))


func active_mass() -> float:
	return Inventory.total_mass(GameState.state.get("ship", {}), GameState.state.get("orders", {}))


func deadline_day(order_id: String) -> int:
	var entry: Dictionary = GameState.state.get("orders", {}).get(order_id, {})
	if entry.is_empty():
		return -1
	return int(entry["accepted_day"]) + int(DataLoader.get_record(order_id).get("deadline_days", 0))


func remaining_days(order_id: String) -> int:
	return maxi(0, deadline_day(order_id) - Clock.current_day()) if status(order_id) == "active" else -1


func is_overdue(order_id: String) -> bool:
	return DataLoader.get_record(order_id).get("source") != "shop" and status(order_id) == "active" and Clock.current_day() > deadline_day(order_id)


func accept(order_id: String) -> Error:
	return EffectApplier.accept_order(order_id)


func complete_test_order(order_id: String) -> Error:
	return EffectApplier.deliver_order(order_id)


func fail(order_id: String) -> Error:
	return EffectApplier.settle_order(order_id, "failed")


func check_expired() -> void:
	var expired: Array[String] = []
	for order_id: String in GameState.state.get("orders", {}):
		if is_overdue(order_id):
			expired.append(order_id)
	for order_id: String in expired:
		if is_overdue(order_id) and EffectApplier.settle_order(order_id, "failed", false) != OK:
			push_error("OrderManager: could not fail expired order '%s'" % order_id)


func _on_day_changed(_day: int) -> void:
	check_expired()
