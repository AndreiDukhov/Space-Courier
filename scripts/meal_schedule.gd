extends RefCounted

const Slots = preload("res://scripts/time_slots.gd")
const Numbers = preload("res://scripts/order_rules.gd")
const Inventory = preload("res://scripts/inventory.gd")


static func turn(day: int, slot: String) -> int:
	return (day - 1) * Slots.NAMES.size() + Slots.NAMES.find(slot)


static func arrival(day: int, slot: String) -> Dictionary:
	var next: int = turn(day, slot) + 1
	if Slots.NAMES[next % Slots.NAMES.size()] == "night":
		next += 1
	return {"day": floori(next / float(Slots.NAMES.size())) + 1, "time_slot": Slots.NAMES[next % Slots.NAMES.size()]}


static func is_due(entry: Dictionary, day: int, slot: String) -> bool:
	return entry.get("day") == day and entry.get("time_slot") == slot


static func valid_save(value: Variant, save: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	var now: int = turn(int(save["day"]), str(save["time_slot"]))
	for heroine_id: String in value:
		var heroine: Variant = save.get("heroines", {}).get(heroine_id)
		var entry: Variant = value[heroine_id]
		if not heroine is Dictionary or not entry is Dictionary or entry.size() != 4 or not entry.has_all(["item", "quality", "day", "time_slot"]):
			return false
		if not entry["item"] is String or Inventory.recipe_for_dish(str(entry["item"])).is_empty() or not Numbers.whole_number(entry["quality"]) or float(entry["quality"]) < 1 or float(entry["quality"]) > 3:
			return false
		if not Numbers.whole_number(entry["day"]) or float(entry["day"]) < 1 or entry["time_slot"] not in ["morning", "day", "evening"]:
			return false
		var due: int = turn(int(entry["day"]), str(entry["time_slot"]))
		if due == now:
			if heroine.get("loc") != "hub_kitchen" or save.get("served_days", {}).get(heroine_id) != save["day"]:
				return false
		elif due > now:
			var expected: Dictionary = arrival(int(save["day"]), str(save["time_slot"]))
			if entry["day"] != expected["day"] or entry["time_slot"] != expected["time_slot"] or int(save.get("served_days", {}).get(heroine_id, 0)) >= int(entry["day"]):
				return false
		else:
			return false
	return true
