extends RefCounted

const Text = preload("res://scripts/ui_text.gd")


static func form(steps: Array) -> int:
	return (1 if "cut" in steps else 0) | (2 if "boil" in steps else 0) | (4 if "fry" in steps else 0)


static func ingredient_name(item_id: String, steps: Array, plated: bool = false) -> String:
	var name: String = str(DataLoader.get_record(item_id).get("name", ""))
	if not steps.is_empty():
		if item_id == "carrot":
			name = Text.get_text("ui_carrot_form_" + str(form(steps)))
		else:
			name = Text.get_text("ui_kitchen_form_" + str(form(steps)), {"name": name})
	return Text.get_text("ui_kitchen_plated", {"name": name}) if plated else name
