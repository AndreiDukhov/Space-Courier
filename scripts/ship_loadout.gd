extends RefCounted

const Rules = preload("res://scripts/order_rules.gd")
const SLOTS: Array[String] = ["engine", "maneuver_engine", "turret", "course", "armor", "shield", "broadside"]
const LEGACY_DEFAULTS: Array[String] = ["maneuver_mk1", "armor_mk1", "shield_mk1"]


static func slot_for(module: Dictionary) -> String:
	return str(module.get("mount", "")) if module.get("slot") == "weapon" else str(module.get("slot", ""))


static func installed(ship: Dictionary, slot: String) -> Dictionary:
	var modules: Variant = ship.get("modules", [])
	if not modules is Array:
		return {}
	for module_id: Variant in modules:
		if not module_id is String:
			continue
		var module: Dictionary = DataLoader.get_record(module_id)
		if slot_for(module) == slot:
			return module
	return {}


static func speed(ship: Dictionary) -> float:
	return float(installed(ship, "engine").get("speed", 0.0))


static func shield_max(ship: Dictionary) -> float:
	return float(installed(ship, "shield").get("shield", 0.0))


static func movement_settings(ship: Dictionary) -> Dictionary:
	var source: Variant = ship.get("movement")
	if not source is Dictionary:
		return {}
	var settings: Dictionary = source.duplicate(true)
	if Rules.whole_number(settings.get("maneuver_level")):
		settings["maneuver_level"] = clampi(int(settings["maneuver_level"]) + int(installed(ship, "maneuver_engine").get("maneuver_level", 0)), 0, 100)
	return settings


static func replacement_hull(ship: Dictionary, module: Dictionary) -> Dictionary:
	var hull: Dictionary = ship["hull"].duplicate()
	var damage: float = float(hull["max"]) - float(hull["current"])
	hull["max"] = float(hull["max"]) - float(installed(ship, "armor").get("hull_bonus", 0)) + float(module.get("hull_bonus", 0))
	hull["current"] = maxf(0.0, float(hull["max"]) - damage)
	return hull


static func migrate(save: Dictionary) -> Dictionary:
	var ship: Variant = save.get("ship")
	if not ship is Dictionary or not ship.get("slots") is Dictionary or not ship.get("modules") is Array:
		return save
	var slots: Dictionary = ship["slots"]
	if slots.size() != 3 or not slots.has_all(["engine", "weapon", "utility"]) or slots["engine"] != 1 or slots["weapon"] not in [2, 3] or slots["utility"] != 2:
		return save
	var result: Dictionary = save.duplicate(true)
	result["ship"]["slots"] = {}
	for slot: String in SLOTS:
		result["ship"]["slots"][slot] = 1
	for module_id: String in LEGACY_DEFAULTS:
		if module_id not in result["ship"]["modules"]:
			result["ship"]["modules"].append(module_id)
	return result


static func valid(ship: Dictionary) -> bool:
	var slots: Variant = ship.get("slots")
	var modules: Variant = ship.get("modules")
	if not slots is Dictionary or slots.size() != SLOTS.size() or not slots.has_all(SLOTS) or not modules is Array:
		return false
	for capacity: Variant in slots.values():
		if not Rules.whole_number(capacity) or capacity != 1:
			return false
	var occupied: Dictionary = {}
	for module_id: Variant in modules:
		if not module_id is String or not DataLoader.record_sources.has("modules/" + str(module_id)):
			return false
		var slot: String = slot_for(DataLoader.get_record(module_id))
		if slot not in SLOTS or occupied.has(slot):
			return false
		occupied[slot] = true
	return true
