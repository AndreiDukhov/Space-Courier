extends RefCounted

const Numbers = preload("res://scripts/order_rules.gd")
const Galaxy = preload("res://scripts/galaxy_state.gd")
const FIELDS: Array[String] = ["location", "opening", "limit", "noticed"]


static func migrate(save: Dictionary) -> Dictionary:
	if save.has("peek"):
		return save
	var result: Dictionary = save.duplicate(true)
	result["peek"] = {}
	return result


static func valid_target(location_id: String) -> bool:
	if location_id == "hub_showers":
		return true
	for door: Dictionary in DataLoader.get_record("hub_corridor_doors").get("doors", []):
		if door.has("heroine") and door.get("location") == location_id:
			return true
	return false


static func valid_save(save: Dictionary) -> bool:
	var peek: Variant = save.get("peek")
	if not peek is Dictionary:
		return false
	if peek.is_empty():
		return true
	if peek.size() != FIELDS.size() or not peek.has_all(FIELDS):
		return false
	if not peek["location"] is String or not valid_target(peek["location"]) or not peek["noticed"] is bool:
		return false
	for field: String in ["opening", "limit"]:
		if not Numbers.finite_number(peek[field]):
			return false
	if peek["opening"] < 0 or peek["opening"] > 1 or peek["limit"] <= 0 or peek["limit"] >= 1:
		return false
	if not peek["noticed"] and peek["opening"] > peek["limit"]:
		return false
	var origin: String = "hub_showers" if peek["location"] == "hub_showers" else str(DataLoader.get_record("hub_corridor_doors")["location"])
	return save.get("location") == origin and save.get("current_system") == Galaxy.INITIAL_SYSTEM and save.get("combat") is Dictionary and save["combat"].is_empty() and save.get("kitchen") is Dictionary and save["kitchen"].is_empty()


static func validate_layout(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var zones: Variant = record.get("zones")
	if not zones is Dictionary or not zones.has_all(["frame", "door"]):
		errors.append("Peeking requires frame and door source regions")
	else:
		for zone: String in ["frame", "door"]:
			var entry: Variant = zones[zone]
			if not entry is Dictionary or not _valid_rect(entry.get("drop_rect")):
				errors.append("Peeking " + zone + " requires a normalized source rectangle")
	var rules: Variant = record.get("rules")
	if not rules is Dictionary or rules.size() != 3 or not rules.has_all(["max_speed", "limit", "mood_penalty"]):
		errors.append("Peeking requires max_speed, limit and mood_penalty rules")
		return errors
	if not Numbers.finite_number(rules["max_speed"]) or rules["max_speed"] <= 0:
		errors.append("Peeking speed must be positive and finite")
	if not Numbers.whole_number(rules["mood_penalty"]) or rules["mood_penalty"] < 0 or rules["mood_penalty"] > 100:
		errors.append("Peeking mood penalty must be an integer from zero to one hundred")
	var limits: Variant = rules["limit"]
	if not limits is Array or limits.size() != 2:
		errors.append("Peeking limit requires two numbers")
	elif not Numbers.finite_number(limits[0]) or not Numbers.finite_number(limits[1]) or limits[0] <= 0 or limits[0] >= limits[1] or limits[1] >= 1:
		errors.append("Peeking limits must be ordered strictly between zero and one")
	return errors


static func _valid_rect(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for coordinate: Variant in value:
		if not Numbers.finite_number(coordinate):
			return false
	return value[0] >= 0 and value[1] >= 0 and value[2] > 0 and value[3] > 0 and value[0] + value[2] <= 1.000001 and value[1] + value[3] <= 1.000001
