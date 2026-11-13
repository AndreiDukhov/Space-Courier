extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")


static func current_path() -> String:
	if not GameState.state.get("combat", {}).is_empty():
		return "res://scenes/combat.tscn"
	if GameState.state.get("location") == "ship_bridge":
		if Conditions.is_inside_ship():
			return "res://scenes/hub.tscn"
		return "res://scenes/system_flight.tscn"
	return "res://scenes/hub.tscn"
