extends RefCounted

const Domestic = preload("res://scripts/domestic_validator.gd")


static func validate_layout(record: Dictionary) -> Array[String]:
	if record.size() != 3 or not record.has_all(["id", "location", "doors"]) or not record["location"] is String or not record["doors"] is Array or record["doors"].is_empty():
		return ["Bedroom door layout requires location and doors"]
	var errors: Array[String] = []
	var ids: Dictionary = {}
	var rooms: Dictionary = {}
	var owners: Dictionary = {}
	for door: Variant in record["doors"]:
		if not door is Dictionary or not door.has_all(["id", "location", "drop_rect"]) or door.size() != (4 if door.has("heroine") else 3):
			errors.append("Bedroom door requires id, location, drop_rect and optional heroine")
			continue
		if not door["id"] is String or str(door["id"]).is_empty() or ids.has(door["id"]):
			errors.append("Bedroom door ids must be unique nonempty strings")
		ids[door["id"]] = true
		if not door["location"] is String or rooms.has(door["location"]):
			errors.append("Bedroom doors must lead to separate locations")
		rooms[door["location"]] = true
		if door.has("heroine"):
			if not door["heroine"] is String or str(door["heroine"]).is_empty() or owners.has(door["heroine"]):
				errors.append("Bedroom owners must be unique heroine ids")
			owners[door["heroine"]] = true
		errors.append_array(Domestic.validate_drop_rect(door["drop_rect"]))
	return errors


static func validate_links(groups: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for record: Dictionary in groups.get("ui", []):
		if record.get("id") != "hub_corridor_doors" or not record.get("doors") is Array:
			continue
		for door: Variant in record["doors"]:
			if not door is Dictionary or not door.get("heroine") is String:
				continue
			for tag: String in ["door_peek", "door_knock", "door_enter_friendly", "door_enter_rejected", "door_enter_knocked"]:
				var count: int = 0
				for scene: Dictionary in groups.get("scenes", []):
					if not scene.get("tags", []) is Array or tag not in scene.get("tags", []) or not scene.get("lines", []) is Array:
						continue
					for line: Variant in scene.get("lines", []):
						if line is Dictionary and line.get("who") == door["heroine"]:
							count += 1
							var expected: String = str(door.get("location", "")) if tag in ["door_enter_friendly", "door_enter_knocked"] else str(record.get("location", ""))
							if scene.get("location") != expected:
								errors.append(str(scene.get("id")) + ": bedroom scene location does not match its door")
							break
				if count != 1:
					errors.append(str(door["heroine"]) + ": bedroom requires exactly one " + tag + " scene")
	return errors
