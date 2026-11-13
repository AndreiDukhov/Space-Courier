extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Slots = preload("res://scripts/time_slots.gd")


static func validate_location(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var access: Variant = record.get("access", [])
	if access is Array:
		errors.append_array(Conditions.validate(access))
	else:
		errors.append("Location access must be an array")
	var backgrounds: Variant = record.get("backgrounds", {})
	if not backgrounds is Dictionary:
		errors.append("Location backgrounds must be an object")
	else:
		for asset_path: Variant in backgrounds.values():
			if not asset_path is String or str(asset_path).is_empty():
				errors.append("Background paths must be nonempty strings")
				continue
			var path: String = asset_path if str(asset_path).begins_with("res://") else "res://" + str(asset_path)
			if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
				errors.append("Missing background: " + path)
	return errors


static func validate_schedule(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var slots: Variant = record.get("slots")
	if not slots is Dictionary or not slots.has_all(Slots.NAMES):
		errors.append("Schedules must define all four time slots")
	if slots is Dictionary:
		_validate_slots(slots, errors)
	var overrides: Variant = record.get("overrides", [])
	if not overrides is Array:
		errors.append("Schedule overrides must be an array")
		return errors
	for override: Variant in overrides:
		if not override is Dictionary:
			errors.append("Schedule overrides must contain objects")
			continue
		if override.get("if") is Array:
			errors.append_array(Conditions.validate(override["if"]))
		else:
			errors.append("Override conditions must be an array")
		if override.get("slots") is Dictionary:
			_validate_slots(override["slots"], errors)
		else:
			errors.append("Override slots must be an object")
	return errors


static func _validate_slots(slots: Dictionary, errors: Array[String]) -> void:
	for slot: String in slots:
		if slot not in Slots.NAMES:
			errors.append("Unknown schedule slot: " + slot)
		var entries: Variant = slots[slot]
		if not entries is Array or entries.is_empty():
			errors.append("Schedule slots need at least one location")
			continue
		for entry: Variant in entries:
			if not entry is Dictionary:
				errors.append("Weighted locations must be objects")
				continue
			if not entry.get("loc") is String or str(entry["loc"]).is_empty():
				errors.append("Weighted locations require a loc id")
			if not Conditions.is_number(entry.get("weight")) or float(entry["weight"]) <= 0.0:
				errors.append("Schedule weights must be positive numbers")
