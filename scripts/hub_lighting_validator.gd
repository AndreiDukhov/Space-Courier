extends RefCounted

const Rules = preload("res://scripts/order_rules.gd")
const Slots = preload("res://scripts/time_slots.gd")
const Domestic = preload("res://scripts/domestic_validator.gd")


static func validate(record: Dictionary, locations: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var profiles: Variant = record.get("slots")
	if not profiles is Dictionary or profiles.size() != Slots.NAMES.size() or not profiles.has_all(Slots.NAMES):
		errors.append("Hub lighting requires all four time slots")
	else:
		for slot: String in profiles:
			if not profiles[slot] is Dictionary:
				errors.append("Hub lighting slot must be an object")
				continue
			for field: String in ["ambient", "light_gain"]:
				if not Rules.finite_number(profiles[slot].get(field)) or profiles[slot][field] < 0:
					errors.append("Hub lighting requires nonnegative finite " + field)
	var rooms: Variant = record.get("locations")
	if not rooms is Dictionary:
		errors.append("Hub lighting requires location settings")
		return errors
	for location_id: Variant in rooms:
		if not location_id is String or not locations.has(location_id):
			errors.append("Hub lighting references unknown location '" + str(location_id) + "'")
		var room: Variant = rooms[location_id]
		if not room is Dictionary or not room.get("light_rects") is Array:
			errors.append("Hub lighting location requires light_rects")
			continue
		for rect: Variant in room["light_rects"]:
			errors.append_array(Domestic.validate_drop_rect(rect))
	return errors
