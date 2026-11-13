extends RefCounted

const Rules = preload("res://scripts/order_rules.gd")
const ShipLoadout = preload("res://scripts/ship_loadout.gd")


static func validate_weapon(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not record.get("id") is String or str(record["id"]).is_empty():
		errors.append("Weapon requires an id")
	if record.get("type") not in ["kinetic", "laser"] or record.get("mount") not in ["turret", "course", "broadside"] or not record.get("name") is String:
		errors.append("Weapon requires a name, supported damage type and mount")
	var expected_arc: String = "front" if record.get("mount") == "course" else str(record.get("mount"))
	if record.get("arc") != expected_arc or not Rules.finite_number(record.get("arc_degrees")) or record["arc_degrees"] < 0 or record["arc_degrees"] > 360:
		errors.append("Weapon requires a matching arc and valid arc_degrees")
	elif (record.get("mount") == "course" and record["arc_degrees"] > 90) or (record.get("mount") == "broadside" and (record["arc_degrees"] <= 0 or record["arc_degrees"] > 180)):
		errors.append("Course and broadside arcs exceed their mount limits")
	var critical: Variant = record.get("critical")
	if not critical is Dictionary or not Rules.finite_number(critical.get("chance")) or critical["chance"] < 0 or critical["chance"] > 1 or not Rules.finite_number(critical.get("multiplier")) or critical["multiplier"] < 1:
		errors.append("Weapon requires valid critical chance and multiplier")
	if not _range(record.get("dmg"), false):
		errors.append("Weapon damage requires a positive integer range")
	for field: String in ["range", "ap_cost"]:
		if not Rules.whole_number(record.get(field)) or record[field] < 1:
			errors.append("Weapon requires positive " + field)
	var accuracy: Variant = record.get("accuracy")
	if not accuracy is Dictionary or not accuracy.has_all(["close", "far", "hull_penalty", "crew_mood_bonus"]):
		errors.append("Weapon requires accuracy and hull/crew modifiers")
	else:
		for field: String in ["close", "far", "hull_penalty", "crew_mood_bonus"]:
			if not Rules.finite_number(accuracy[field]) or accuracy[field] < 0 or accuracy[field] > 1:
				errors.append("Weapon accuracy must stay in [0, 1]")
	return errors


static func validate_record(record: Dictionary, group: String) -> Array[String]:
	var errors: Array[String] = []
	match group:
		"enemies":
			errors.append_array(validate_movement(record.get("movement")))
			if not record.get("description") is String:
				errors.append("Enemy requires a description")
			if not record.get("name") is String or record.get("ai") != "aggressive" or not record.get("can_negotiate") is bool or not record.get("tags") is Array:
				errors.append("Enemy requires name, aggressive AI, tags and negotiation setting")
			for field: String in ["hull", "shield", "speed"]:
				if not Rules.whole_number(record.get(field)) or record[field] < (0 if field == "shield" else 1):
					errors.append("Enemy requires valid " + field)
			if not record.get("weapons") is Array or record["weapons"].is_empty():
				errors.append("Enemy requires weapons")
			else:
				for weapon: Variant in record["weapons"]:
					if weapon is Dictionary:
						errors.append_array(validate_weapon(weapon))
					else:
						errors.append("Enemy weapon must be an object")
			var loot: Variant = record.get("loot")
			if not loot is Dictionary or not loot.has_all(["money", "fuel"]) or not _range(loot["money"], true) or not _range(loot["fuel"], true):
				errors.append("Enemy loot requires nonnegative money and fuel ranges")
			errors.append_array(_validate_loadouts(record))
		"abilities":
			if not record.get("name") is String or not record.get("owner") is String:
				errors.append("Ability requires a name and owner")
			var cost: Variant = record.get("cost_ap")
			if cost not in ["all", "half"] and (not Rules.whole_number(cost) or cost < 1):
				errors.append("Ability requires a positive cost_ap or all/half")
			if not Rules.whole_number(record.get("cooldown")) or record["cooldown"] < 1:
				errors.append("Ability requires positive cooldown")
			var scale: Variant = record.get("mood_scale")
			if not scale is Dictionary or not scale.has_all(["stat", "min", "max"]):
				errors.append("Ability requires mood_scale")
			elif scale["stat"] != str(record.get("owner")) + ".mood" or not Rules.finite_number(scale["min"]) or not Rules.finite_number(scale["max"]) or scale["min"] <= 0 or scale["max"] < scale["min"]:
				errors.append("Ability requires an owner's mood stat and a positive multiplier range")
			var effect: Variant = record.get("effect")
			if not effect is Dictionary:
				errors.append("Ability requires an effect object")
			elif effect.has("self_evasion"):
				if effect.size() != 2 or not Rules.finite_number(effect["self_evasion"]) or effect["self_evasion"] <= 0 or effect["self_evasion"] > 1 or not Rules.whole_number(effect.get("duration")) or effect["duration"] < 1:
					errors.append("Invalid evasion effect")
			elif effect.has("move_points"):
				if effect.size() != 2 or not Rules.whole_number(effect["move_points"]) or effect["move_points"] < 1 or not Rules.finite_number(effect.get("fuel")) or effect["fuel"] <= 0:
					errors.append("Invalid emergency burn effect")
			elif effect.has("shield_restore"):
				if effect.size() != 2 or not Rules.finite_number(effect["shield_restore"]) or effect["shield_restore"] <= 0 or not Rules.whole_number(effect.get("delay")) or effect["delay"] < 1:
					errors.append("Invalid delayed shield recharge effect")
			else:
				errors.append("Unsupported combat ability effect")
		"modules":
			if record.get("slot") not in ["engine", "weapon", "maneuver_engine", "armor", "shield"]:
				errors.append("Unsupported prototype module slot")
			if not record.get("name") is String or not record.get("description") is String:
				errors.append("Module requires a name and description")
			for field: String in {"engine": ["speed"], "maneuver_engine": ["maneuver_level"], "armor": ["hull_bonus"], "shield": ["shield"]}.get(str(record.get("slot")), []):
				if not Rules.whole_number(record.get(field)) or record[field] < (1 if field in ["speed", "shield"] else 0):
					errors.append("Invalid module parameter: " + field)
			if record.get("slot") == "maneuver_engine" and Rules.whole_number(record.get("maneuver_level")) and record["maneuver_level"] > 100:
				errors.append("Module maneuver level exceeds 100")
			if record.get("slot") == "weapon":
				errors.append_array(validate_weapon(record))
			if record.get("slot") == "engine" and (not Rules.whole_number(record.get("thrust")) or record["thrust"] < 1):
				errors.append("Engine requires positive thrust")
		"ship":
			errors.append_array(validate_movement(record.get("movement")))
			if not ShipLoadout.valid(record):
				errors.append("Ship requires seven single module slots and one module per occupied slot")
	return errors


static func validate_movement(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	var fields: Array[String] = ["maneuver_level", "cone_base", "cone_slope_base", "cone_slope_per_level", "cone_slope_max", "inertia_base", "inertia_per_level", "inertia_min", "turn_steps_base"]
	if not value is Dictionary or value.size() != fields.size() or not value.has_all(fields):
		return ["Movement requires the documented cone and inertia fields"]
	for field: String in fields:
		if not Rules.finite_number(value[field]) or value[field] < 0:
			errors.append("Movement requires nonnegative finite " + field)
	if not errors.is_empty():
		return errors
	if not Rules.whole_number(value["maneuver_level"]) or value["maneuver_level"] > 100 or not Rules.whole_number(value["turn_steps_base"]) or value["turn_steps_base"] < 1 or value["turn_steps_base"] > 4:
		errors.append("Movement levels and turn steps must be bounded integers")
	if value["cone_slope_max"] > 1 or value["cone_slope_base"] > value["cone_slope_max"] or value["inertia_min"] > value["inertia_base"]:
		errors.append("Movement cone and inertia limits are inconsistent")
	return errors


static func validate_links(groups: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var weapons: Dictionary = {}
	var common_ap: int = -1
	for module: Dictionary in groups.get("modules", []):
		if module.get("slot") == "weapon":
			weapons[module["id"]] = true
			if Rules.whole_number(module.get("ap_cost")):
				if common_ap < 0:
					common_ap = int(module["ap_cost"])
				elif common_ap != int(module["ap_cost"]):
					errors.append("All weapons must use the same AP cost")
	for enemy: Dictionary in groups.get("enemies", []):
		if not enemy.get("weapons") is Array:
			continue
		for weapon: Variant in enemy["weapons"]:
			if weapon is Dictionary and not weapons.has(weapon.get("id")):
				errors.append(str(enemy["id"]) + ": unknown weapon module id '" + str(weapon.get("id")) + "'")
			if weapon is Dictionary and Rules.whole_number(weapon.get("ap_cost")) and common_ap >= 0 and int(weapon["ap_cost"]) != common_ap:
				errors.append(str(enemy["id"]) + ": enemy and player weapons must use the same AP cost")
	return errors


static func _validate_loadouts(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var available: Dictionary = {}
	if record.get("weapons") is Array:
		for weapon: Variant in record["weapons"]:
			if weapon is Dictionary and weapon.get("id") is String:
				if available.has(weapon["id"]):
					errors.append("Enemy weapon ids must be unique")
				available[weapon["id"]] = true
	var profiles: Variant = record.get("loadouts")
	if not profiles is Array or profiles.is_empty():
		return ["Enemy requires nonempty loadouts"]
	for profile: Variant in profiles:
		if not profile is Array or profile.is_empty():
			errors.append("Enemy loadout cannot be empty")
			continue
		var seen: Dictionary = {}
		for weapon_id: Variant in profile:
			if not weapon_id is String or not available.has(weapon_id) or seen.has(weapon_id):
				errors.append("Enemy loadout requires unique ids from its weapon pool")
			seen[str(weapon_id)] = true
	return errors


static func _range(value: Variant, zero_allowed: bool) -> bool:
	return value is Array and value.size() == 2 and Rules.whole_number(value[0]) and Rules.whole_number(value[1]) and value[0] >= (0 if zero_allowed else 1) and value[1] >= value[0]
