extends Node

signal time_changed(day: int, time_slot: String)
signal day_changed(day: int)

const Slots = preload("res://scripts/time_slots.gd")
const TIME_SLOTS: Array[String] = Slots.NAMES


func current_day() -> int:
	return int(GameState.state.get("day", 1))


func current_slot() -> String:
	return str(GameState.state.get("time_slot", "morning"))


func advance_slots(amount: int = 1) -> void:
	if amount <= 0:
		return

	for _step_index: int in range(amount):
		var day: int = current_day()
		var previous_day: int = day
		var slot_index: int = TIME_SLOTS.find(current_slot())
		if slot_index < 0:
			slot_index = 0
		slot_index += 1
		if slot_index >= TIME_SLOTS.size():
			slot_index = 0
			day += 1
		GameState.state["day"] = day
		GameState.state["time_slot"] = TIME_SLOTS[slot_index]
		if day != previous_day:
			day_changed.emit(day)
		time_changed.emit(day, TIME_SLOTS[slot_index])
