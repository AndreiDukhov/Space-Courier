extends RefCounted

const Flight = preload("res://scripts/flight_state.gd")
const Rules = preload("res://scripts/order_rules.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Effects = preload("res://scripts/effect_applier.gd")
const SpaceContent = preload("res://scripts/space_content_validator.gd")


static func validate_npc(record: Dictionary) -> Array[String]:
	var errors: Array[String] = SpaceContent.validate_npc(record)
	for field: String in ["system", "event"]:
		if not record.get(field) is String or str(record[field]).is_empty():
			errors.append("NPC requires a nonempty " + field + " id")
	if record.has("shop") and (not record["shop"] is String or str(record["shop"]).is_empty() or record.get("role") != "civilian"):
		errors.append("Transport shop requires a nonempty shop id and civilian role")
	if not record.get("name") is String or not Flight.valid_point(record.get("pos")):
		errors.append("NPC requires a name and bounded starting position")
	if not Rules.finite_number(record.get("speed")) or record["speed"] <= 0:
		errors.append("NPC speed must be positive and finite")
	var points: Variant = record.get("waypoints")
	if not points is Array or points.size() < 2:
		errors.append("NPC requires at least two waypoints")
	else:
		var distinct: Dictionary = {}
		for point: Variant in points:
			if not Flight.valid_point(point):
				errors.append("NPC waypoints must stay inside the system")
			else:
				distinct[JSON.stringify(point)] = true
		if distinct.size() < 2:
			errors.append("NPC patrol requires distinct waypoints")
	return errors


static func validate_event(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if record.get("trigger") not in ["encounter", "approach", "enter_system"]:
		errors.append("Unsupported event trigger")
	if not Rules.finite_number(record.get("chance")) or record["chance"] < 0 or record["chance"] > 1:
		errors.append("Event chance must be between zero and one")
	if not record.get("conditions") is Array:
		errors.append("Event conditions must be an array")
	else:
		errors.append_array(Conditions.validate(record["conditions"]))
	if not record.get("options") is Array or record["options"].is_empty():
		errors.append("Event requires options")
		return errors
	for option: Variant in record["options"]:
		if not option is Dictionary:
			errors.append("Event options must be objects")
			continue
		if not option.get("text") is String:
			errors.append("Event option text must be a string")
		if not option.get("effects") is Array:
			errors.append("Event option effects must be an array")
		else:
			errors.append_array(Effects.validate(option["effects"]))
		if not option.get("tags") is Array:
			errors.append("Event option tags must be an array")
		else:
			for tag: Variant in option["tags"]:
				if not tag is String or str(tag).is_empty():
					errors.append("Event tags must be nonempty strings")
	return errors


static func validate_links(groups: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var shops: Dictionary = {}
	for shop: Dictionary in groups.get("shops", []):
		shops[shop["id"]] = shop
	var events: Dictionary = {}
	for event: Dictionary in groups.get("events", []):
		events[event["id"]] = event
	for npc: Dictionary in groups.get("npcs", []):
		if npc.has("shop") and shops.get(npc["shop"], {}).has("owner"):
			errors.append(str(npc["id"]) + ": transport shop must be independent of a heroine")
		if events.has(npc.get("event")) and events[npc["event"]].get("trigger") != "encounter":
			errors.append(str(npc["id"]) + ": NPC event requires the encounter trigger")
		if events.has(npc.get("event")):
			var enemy_ids: Dictionary = {}
			for option: Variant in events[npc["event"]].get("options", []):
				if not option is Dictionary or not option.get("effects") is Array:
					continue
				for effect: Variant in option["effects"]:
					if effect is Dictionary and effect.get("start_combat") is String:
						enemy_ids[effect["start_combat"]] = true
			if enemy_ids.size() > 1:
				errors.append(str(npc["id"]) + ": NPC encounter must use one enemy blueprint")
			if npc.get("role") == "pirate" and enemy_ids.size() != 1:
				errors.append(str(npc["id"]) + ": pirate encounter requires an enemy blueprint")
	for system: Dictionary in groups.get("systems", []):
		var objects: Variant = system.get("objects", [])
		if not objects is Array:
			continue
		for object: Variant in objects:
			if object is Dictionary and object.get("type") == "planet" and object.get("inhabited", false) and events.has(object.get("dialogue")) and events[object["dialogue"]].get("trigger") != "approach":
				errors.append(str(object.get("id", "")) + ": planet dialogue requires the approach trigger")
			if object is Dictionary and object.get("type") == "event_marker":
				if events.has(object.get("event")) and events[object["event"]].get("trigger") != "approach":
					errors.append(str(system["id"]) + ": marker event requires the approach trigger")
	return errors
