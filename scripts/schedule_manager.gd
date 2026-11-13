extends Node

signal placements_changed

const Conditions = preload("res://scripts/condition_evaluator.gd")


func _ready() -> void:
	Clock.time_changed.connect(_on_time_changed)


func assign_locations() -> Error:
	var placements: Dictionary = {}
	for heroine: Dictionary in DataLoader.get_records("heroines"):
		var heroine_id: String = str(heroine["id"])
		if Conditions.meal_is_due(heroine_id):
			placements[heroine_id] = "hub_kitchen"
			continue
		if not heroine.has("schedule"):
			placements[str(heroine["id"])] = "hub_shop"
			continue
		var schedule: Dictionary = DataLoader.get_schedule(str(heroine.get("schedule", "")))
		var entries: Array = entries_for_slot(schedule, Clock.current_slot())
		var location_id: String = choose_location(entries, randf())
		if location_id.is_empty():
			return ERR_INVALID_DATA
		placements[str(heroine["id"])] = location_id
	var result: Error = EffectApplier.apply_schedule(placements)
	if result == OK:
		EffectApplier.resolve_meal_invites()
		placements_changed.emit()
	return result


func entries_for_slot(schedule: Dictionary, slot: String) -> Array:
	for override: Dictionary in schedule.get("overrides", []):
		if Conditions.evaluate(override.get("if", [])) and override.get("slots", {}).has(slot):
			return override["slots"][slot].duplicate(true)
	return schedule.get("slots", {}).get(slot, []).duplicate(true)


func choose_location(entries: Array, roll: float) -> String:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("weight", 0))
	if total <= 0.0 or entries.is_empty():
		return ""
	var threshold: float = clampf(roll, 0.0, 1.0) * total
	for entry: Dictionary in entries:
		threshold -= float(entry.get("weight", 0))
		if threshold < 0.0:
			return str(entry["loc"])
	return str(entries.back()["loc"])


func _on_time_changed(_day: int, _time_slot: String) -> void:
	if assign_locations() != OK:
		push_error("ScheduleManager: could not assign locations")
