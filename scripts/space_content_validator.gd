extends RefCounted

const Rules = preload("res://scripts/order_rules.gd")


static func validate_system(system: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var background: Variant = system.get("background")
	if not background is String or not str(background).begins_with("res://") or not FileAccess.file_exists(str(background)) or str(background).get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp", "svg"]:
		errors.append("System background must reference an existing project image")
	var config: Variant = system.get("traffic")
	if not config is Dictionary:
		errors.append("System requires traffic configuration")
	else:
		if not Rules.whole_number(config.get("min_active")) or not Rules.whole_number(config.get("max_active")) or config["min_active"] < 0 or config["max_active"] < config["min_active"]:
			errors.append("Invalid traffic population range")
		var delay: Variant = config.get("spawn_delay")
		if not delay is Array or delay.size() != 2 or not Rules.finite_number(delay[0]) or not Rules.finite_number(delay[1]) or delay[0] <= 0 or delay[1] < delay[0]:
			errors.append("Invalid traffic spawn delay")
	var inhabited: int = 0
	for object: Variant in system.get("objects", []):
		if not object is Dictionary:
			continue
		if object.get("type") == "planet":
			if not object.get("inhabited") is bool:
				errors.append("Planet requires inhabited flag")
			elif object["inhabited"]:
				inhabited += 1
				for field: String in ["shop", "dialogue"]:
					if not object.get(field) is String or str(object[field]).is_empty():
						errors.append("Inhabited planet requires " + field + " id")
		elif object.get("type") == "star":
			var hazard: Variant = object.get("hazard")
			if not hazard is Dictionary or not Rules.finite_number(hazard.get("radius")) or not Rules.finite_number(hazard.get("damage_per_second")) or hazard["radius"] <= 0 or hazard["damage_per_second"] <= 0:
				errors.append("Star requires positive hazard radius and damage")
	if inhabited < 1:
		errors.append("Traffic system requires at least one inhabited planet")
	return errors


static func validate_npc(npc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if npc.get("role") not in ["civilian", "patrol", "pirate"]:
		errors.append("NPC requires a supported role")
	if npc.get("role") == "pirate":
		errors.append_array(_settings(npc.get("pairing"), ["radius", "duration", "spacing", "cooldown"], "chance"))
		var config: Variant = npc.get("piracy")
		if not config is Dictionary:
			return ["Pirate requires piracy configuration"]
		for field: String in ["trigger_radius", "lose_radius", "robbery_seconds", "cooldown"]:
			if not Rules.finite_number(config.get(field)) or config[field] <= 0:
				errors.append("Invalid piracy " + field)
		if Rules.finite_number(config.get("trigger_radius")) and Rules.finite_number(config.get("lose_radius")) and config["lose_radius"] < config["trigger_radius"]:
			errors.append("Pirate lose radius must include the trigger radius")
		if not Rules.finite_number(config.get("destroy_chance")) or config["destroy_chance"] < 0 or config["destroy_chance"] > 1:
			errors.append("Piracy destroy chance must be between zero and one")
	if npc.get("role") == "patrol":
		errors.append_array(_settings(npc.get("policing"), ["trigger_radius", "lose_radius", "engage_radius", "resolve_seconds", "cooldown", "respawn_seconds"], "pirate_loss_chance"))
		var policing: Dictionary = npc.get("policing", {}) if npc.get("policing") is Dictionary else {}
		if Rules.finite_number(policing.get("trigger_radius")) and Rules.finite_number(policing.get("lose_radius")) and policing["lose_radius"] < policing["trigger_radius"]:
			errors.append("Police lose radius must include its trigger radius")
	return errors


static func _settings(value: Variant, positive: Array[String], probability: String) -> Array[String]:
	if not value is Dictionary or value.size() != positive.size() + 1 or not value.has_all(positive) or not value.has(probability):
		return ["Missing or invalid traffic behavior settings: " + probability]
	var errors: Array[String] = []
	for field: String in positive:
		if not Rules.finite_number(value[field]) or value[field] <= 0:
			errors.append("Traffic behavior requires positive " + field)
	if not Rules.finite_number(value[probability]) or value[probability] < 0 or value[probability] > 1:
		errors.append("Traffic probability must be between zero and one: " + probability)
	return errors
