extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Effects = preload("res://scripts/effect_applier.gd")
const Rules = preload("res://scripts/order_rules.gd")
const Domestic = preload("res://scripts/domestic_validator.gd")


static func validate(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if record.get("source") == "shop":
		if not record.get("title") is String or not record.get("giver") is String:
			errors.append("Shop orders require a title and giver")
		if record.has("deadline_days") or record.has("failure"):
			errors.append("Shop orders have no deadline or failure penalty")
		if record.has("need_items") == record.has("labor_slots"):
			errors.append("Shop orders require either need_items or labor_slots")
		elif record.has("need_items"):
			errors.append_array(Domestic.validate_counts(record["need_items"]))
		elif not Rules.whole_number(record["labor_slots"]) or float(record["labor_slots"]) < 1:
			errors.append("Shop labor_slots must be a positive integer")
		for field: String in ["requires", "reward"]:
			if not record.get(field) is Array:
				errors.append("Shop order requires condition/reward arrays")
			else:
				errors.append_array(Conditions.validate(record[field]) if field == "requires" else Effects.validate(record[field]))
		return errors
	if record.get("source") not in Rules.SOURCES:
		errors.append("Unsupported order source")
	if not record.get("title") is String:
		errors.append("Order title must be a string")
	if not record.get("description") is String or str(record["description"]).strip_edges().is_empty():
		errors.append("Order description must be a nonempty string")
	if not record.get("to_planet") is String or str(record["to_planet"]).is_empty():
		errors.append("Order requires a to_planet id")
	for field_name: String in ["from", "to"]:
		if not record.get(field_name) is String or str(record[field_name]).is_empty():
			errors.append("Order requires a '%s' system id" % field_name)
	if not Rules.whole_number(record.get("deadline_days")) or int(record["deadline_days"]) < 1:
		errors.append("Order deadline_days must be a positive integer")
	var cargo: Variant = record.get("cargo")
	if not cargo is Dictionary:
		errors.append("Order cargo must be an object")
	else:
		if not Conditions.is_number(cargo.get("mass")) or float(cargo["mass"]) <= 0.0:
			errors.append("Order cargo mass must be positive")
		if not cargo.get("type") is String:
			errors.append("Order cargo type must be a string")
		_validate_tags(cargo.get("tags"), "cargo tags", errors)
	var requires: Variant = record.get("requires")
	if requires is Array:
		errors.append_array(Conditions.validate(requires))
	else:
		errors.append("Order requires must be an array")
	for field_name: String in ["reward", "failure"]:
		var effects: Variant = record.get(field_name)
		if effects is Array:
			errors.append_array(Effects.validate(effects))
		else:
			errors.append("Order %s must be an array" % field_name)
	_validate_tags(record.get("action_tags"), "action_tags", errors)
	_validate_tags(record.get("risk_tags"), "risk_tags", errors)
	return errors


static func _validate_tags(tags: Variant, context: String, errors: Array[String]) -> void:
	if not tags is Array:
		errors.append("Order %s must be an array" % context)
		return
	for tag: Variant in tags:
		if not tag is String or str(tag).is_empty():
			errors.append("Order %s must contain nonempty strings" % context)
