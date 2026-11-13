extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Effects = preload("res://scripts/effect_applier.gd")
const Locations = preload("res://scripts/location_validator.gd")
const Orders = preload("res://scripts/order_validator.gd")
const Galaxy = preload("res://scripts/galaxy_validator.gd")
const FlightContent = preload("res://scripts/flight_content_validator.gd")
const CombatContent = preload("res://scripts/combat_validator.gd")
const Domestic = preload("res://scripts/domestic_validator.gd")
const Progression = preload("res://scripts/progression_validator.gd")
const Lighting = preload("res://scripts/hub_lighting_validator.gd")

const MIN_HEROINE_AGE: int = 21
const SINGLE_REFERENCES: Dictionary = {
	"location": "locations", "at": "locations", "loc": "locations",
	"heroine": "heroines", "giver": "heroines", "owner": "heroines",
	"schedule": "schedules", "item": "items", "from": "systems", "to": "systems",
	"to_route": "routes", "unlock_route": "routes", "unlock_scene": "scenes",
	"start_order": "orders", "start_combat": "enemies", "event": "events",
	"scene": "scenes", "on_fail": "scenes", "system": "systems", "dish": "items",
	"shop": "shops", "dialogue": "events"
}
const LIST_REFERENCES: Dictionary = {
	"connects": "locations", "crew_aboard": "heroines", "abilities": "abilities",
	"modules": "modules", "others_absent": "heroines", "event_pool": "events",
	"next": "scenes", "reveals_systems": "systems", "reveals_routes": "routes",
	"teaches": "recipes", "learn_recipes": "recipes"
}


static func validate(groups: Dictionary, sources: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var index: Dictionary = {}
	var shop_owners: Array[String] = []
	for shop: Dictionary in groups.get("shops", []):
		shop_owners.append(str(shop.get("owner", "")))
	for group: String in groups:
		index[group] = {}
		for record: Dictionary in groups[group]:
			var id_field: String = "heroine" if group == "schedules" else "id"
			index[group][str(record.get(id_field, ""))] = true

	for group: String in groups:
		for record: Dictionary in groups[group]:
			var record_id: String = str(record.get("id", record.get("heroine", "")))
			var context: String = "%s [%s]" % [sources.get(group + "/" + record_id, group), record_id]
			if group == "heroines":
				_validate_age(record, context, errors)
				for message: String in Progression.validate_sprite(record):
					errors.append(context + ": " + message)
				if not record.get("schedule") is String and record_id not in shop_owners:
					errors.append(context + ": heroine requires a schedule id")
				var weights: Variant = record.get("tag_weights", {})
				if not weights is Dictionary:
					errors.append(context + ": tag_weights must be an object")
				else:
					for weight: Variant in weights.values():
						if not Conditions.is_number(weight):
							errors.append(context + ": tag weights must be finite numbers")
			if group == "scenes":
				_validate_dialogue(record, context, errors)
			if group in ["items", "shops", "recipes", "heroines"]:
				for message: String in Domestic.validate_record(record, group):
					errors.append(context + ": " + message)
			if group == "ui" and record_id == "kitchen_layout":
				for message: String in Domestic.validate_kitchen_layout(record):
					errors.append(context + ": " + message)
			if group == "ui" and record_id in ["hub_kitchen_hotspot", "hub_office_hotspot", "hub_tech_hotspot"]:
				for message: String in Domestic.validate_hub_hotspot(record):
					errors.append(context + ": " + message)
			if group == "ui" and record_id == "hub_lighting":
				for message: String in Lighting.validate(record, index.get("locations", {})):
					errors.append(context + ": " + message)
			if group == "orders":
				for message: String in Orders.validate(record):
					errors.append(context + ": " + message)
			if group in ["enemies", "abilities", "modules", "ship"]:
				for message: String in CombatContent.validate_record(record, group):
					errors.append(context + ": " + message)
			if group in ["npcs", "events"]:
				var content_errors: Array[String] = FlightContent.validate_npc(record) if group == "npcs" else FlightContent.validate_event(record)
				for message: String in content_errors:
					errors.append(context + ": " + message)
			if group in ["locations", "schedules"]:
				var messages: Array[String] = Locations.validate_location(record) if group == "locations" else Locations.validate_schedule(record)
				for message: String in messages:
					errors.append(context + ": " + message)
			_walk(record, index, context, errors)
	errors.append_array(Galaxy.validate(groups))
	errors.append_array(FlightContent.validate_links(groups))
	errors.append_array(CombatContent.validate_links(groups))
	errors.append_array(Domestic.validate_links(groups))
	errors.append_array(Progression.validate_links(groups))
	return errors


static func _validate_dialogue(record: Dictionary, context: String, errors: Array[String]) -> void:
	var conditions: Variant = record.get("conditions", [])
	if conditions is Array:
		for message: String in Conditions.validate(conditions):
			errors.append(context + ": " + message)
	else:
		errors.append(context + ": conditions must be an array")
	var effect_lists: Array = [record.get("on_end", [])]
	var choices: Variant = record.get("choices", [])
	var choice_ids: Dictionary = {}
	if choices is Array:
		for choice: Variant in choices:
			if choice is Dictionary:
				var choice_id: Variant = choice.get("id")
				if not choice_id is String or str(choice_id).is_empty():
					errors.append(context + ": choices require nonempty ids")
				elif choice_ids.has(choice_id):
					errors.append(context + ": duplicate choice id '" + str(choice_id) + "'")
				else:
					choice_ids[choice_id] = true
				if not choice.get("text") is String:
					errors.append(context + ": choice text must be a string")
				effect_lists.append(choice.get("effects", []))
			else:
				errors.append(context + ": choices must contain objects")
	else:
		errors.append(context + ": choices must be an array")
	var lines: Variant = record.get("lines", [])
	if not lines is Array:
		errors.append(context + ": lines must be an array")
	else:
		for line: Variant in lines:
			if not line is Dictionary:
				errors.append(context + ": lines must contain objects")
			elif not line.get("who") is String or not line.get("text", "") is String:
				errors.append(context + ": line speaker and text must be strings")
	for effects: Variant in effect_lists:
		if effects is Array:
			for message: String in Effects.validate(effects):
				errors.append(context + ": " + message)
		else:
			errors.append(context + ": effects must be an array")


static func _validate_age(record: Dictionary, context: String, errors: Array[String]) -> void:
	var age: Variant = record.get("age")
	if not (age is int or age is float):
		errors.append("%s: age must be an integer >= %d" % [context, MIN_HEROINE_AGE])
	elif not is_finite(float(age)) or float(age) != floor(float(age)) or int(age) < MIN_HEROINE_AGE:
		errors.append("%s: age must be an integer >= %d" % [context, MIN_HEROINE_AGE])


static func _walk(value: Variant, index: Dictionary, context: String, errors: Array[String]) -> void:
	if value is Array:
		for element_index: int in range(value.size()):
			_walk(value[element_index], index, "%s/%d" % [context, element_index], errors)
	elif value is Dictionary:
		for key: String in value:
			var entry: Variant = value[key]
			var entry_context: String = context + "/" + key
			if SINGLE_REFERENCES.has(key):
				_check_reference(entry, str(SINGLE_REFERENCES[key]), index, entry_context, errors)
			elif LIST_REFERENCES.has(key):
				if entry is Array:
					for target: Variant in entry:
						_check_reference(target, str(LIST_REFERENCES[key]), index, entry_context, errors)
				else:
					errors.append("%s: expected an array of ids" % entry_context)
			elif key == "who" and entry != "hero":
				_check_reference(entry, "heroines", index, entry_context, errors)
			elif key in ["aboard", "contact_block"] and entry is String:
				_check_reference(entry, "heroines", index, entry_context, errors)
			elif key == "on_success" and entry is String:
				_check_reference(entry, "scenes", index, entry_context, errors)
			elif key == "stat" and entry is String:
				var heroine_id: String = entry.get_slice(".", 0)
				if heroine_id not in ["owner", "{target}"]:
					_check_reference(heroine_id, "heroines", index, entry_context, errors)
			_walk(entry, index, entry_context, errors)


static func _check_reference(target: Variant, group: String, index: Dictionary, context: String, errors: Array[String]) -> void:
	if not target is String or str(target).is_empty():
		errors.append("%s: expected a nonempty id" % context)
		return
	var group_ids: Dictionary = index.get(group, {})
	if not group_ids.has(target):
		errors.append("%s: unknown %s id '%s'" % [context, group, target])
