extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Effects = preload("res://scripts/effect_applier.gd")
const Numbers = preload("res://scripts/order_rules.gd")
const Slots = preload("res://scripts/time_slots.gd")
const ITEM_TYPES: Array[String] = ["quest", "ingredient", "gift", "loot", "dish", "cookbook"]


static func validate_kitchen_layout(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var background: Variant = record.get("background")
	if not background is String or not str(background).begins_with("res://") or not FileAccess.file_exists(str(background)):
		errors.append("Kitchen background must reference an existing project image")
	var zones: Variant = record.get("zones")
	if not zones is Dictionary or zones.size() != 4 or not zones.has_all(["cut", "boil", "fry", "plate"]):
		errors.append("Kitchen must define all four zones")
		return errors
	for zone_id: String in zones:
		if not zones[zone_id] is Dictionary:
			errors.append("Kitchen zone must be an object")
			continue
		errors.append_array(validate_drop_rect(zones[zone_id].get("drop_rect")))
	return errors


static func validate_hub_hotspot(record: Dictionary) -> Array[String]:
	var zones: Variant = record.get("zones")
	if not record.get("location") is String or not zones is Dictionary or zones.size() != 1:
		return ["Hub hotspot requires a location id and one zone"]
	var zone: String = str(zones.keys()[0])
	if zone not in ["cook", "computer"] or not zones[zone] is Dictionary:
		return ["Hub hotspot requires a cook or computer zone"]
	return validate_drop_rect(zones[zone].get("drop_rect"))


static func validate_drop_rect(rect: Variant) -> Array[String]:
	if not rect is Array or rect.size() != 4:
		return ["Kitchen drop_rect requires four normalized numbers"]
	for number: Variant in rect:
		if not Numbers.finite_number(number):
			return ["Kitchen drop_rect must contain finite numbers"]
	if rect[0] < 0 or rect[1] < 0 or rect[2] <= 0 or rect[3] <= 0 or rect[0] + rect[2] > 1 or rect[1] + rect[3] > 1:
		return ["Kitchen drop_rect must stay inside its background"]
	return []


static func validate_record(record: Dictionary, group: String) -> Array[String]:
	var errors: Array[String] = []
	match group:
		"items":
			if not record.get("name") is String or record.get("type") not in ITEM_TYPES:
				errors.append("Item requires a name and a supported type")
			if record.get("type") not in ["ingredient", "dish"] and (not Numbers.finite_number(record.get("mass")) or float(record.get("mass", -1)) < 0.0):
				errors.append("Item mass must be nonnegative")
			if record.has("preparations"):
				if not record["preparations"] is Array or record["preparations"].is_empty():
					errors.append("Preparations must be a nonempty array")
				else:
					for preparation: Variant in record["preparations"]:
						if preparation not in ["cut", "boil", "fry"]:
							errors.append("Unknown ingredient preparation")
			if not Numbers.whole_number(record.get("sell_price")) or float(record.get("sell_price", -1)) < 0:
				errors.append("Item sell_price must be a nonnegative integer")
			if record.get("type") == "cookbook" and (not record.get("teaches") is Array or record.get("teaches", []).is_empty()):
				errors.append("Cookbooks must teach at least one recipe")
		"shops":
			if record.has("owner") and not record["owner"] is String:
				errors.append("Shop requires an owner")
			if not record.get("open_slots") is Array or record.get("open_slots", []).is_empty():
				errors.append("Shop requires open_slots")
			else:
				for slot: Variant in record["open_slots"]:
					if slot not in Slots.NAMES:
						errors.append("Unknown shop opening slot")
			if not Numbers.finite_number(record.get("sell_ratio")) or float(record.get("sell_ratio", -1)) < 0 or float(record.get("sell_ratio", 2)) > 1:
				errors.append("Shop sell_ratio must be between zero and one")
			if not record.get("buys") is Array:
				errors.append("Shop buys must be an array of item types")
			else:
				for item_type: Variant in record["buys"]:
					if item_type not in ITEM_TYPES:
						errors.append("Unknown type in shop buys")
			if not record.get("items") is Array or record.get("items", []).is_empty():
				errors.append("Shop requires stock")
			else:
				var seen: Dictionary = {}
				for entry: Variant in record["items"]:
					if not entry is Dictionary:
						errors.append("Stock entries must be objects")
						continue
					if not entry.get("item") is String or seen.has(entry.get("item")):
						errors.append("Stock item ids must be unique")
					seen[entry.get("item", "")] = true
					if not Numbers.whole_number(entry.get("price")) or float(entry.get("price", -1)) < 0:
						errors.append("Stock price must be a nonnegative integer")
					if entry.has("min_attitude") and (not Numbers.finite_number(entry["min_attitude"]) or float(entry["min_attitude"]) < 0 or float(entry["min_attitude"]) > 100):
						errors.append("Stock min_attitude must be between zero and one hundred")
		"heroines":
			if record.has("food"):
				if not record["food"] is Dictionary:
					errors.append("Food preferences must be an object")
				else:
					for field: String in ["likes", "dislikes"]:
						if not _tags(record["food"].get(field)):
							errors.append("Food preferences require arrays of tags")
		"recipes":
			if not record.get("dish") is String:
				errors.append("Recipe requires a dish id")
			if not record.get("name") is String or not _tags(record.get("tags")):
				errors.append("Recipe requires a name and tags")
			if not Numbers.whole_number(record.get("slots")) or float(record.get("slots", 0)) < 1:
				errors.append("Recipe slots must be a positive integer")
			if record.has("starter") and not record["starter"] is bool:
				errors.append("Recipe starter must be boolean")
			errors.append_array(validate_counts(record.get("ingredients")))
			for field: String in ["self_effects", "serve_effects"]:
				if record.get(field) is Array:
					errors.append_array(Effects.validate(record[field]))
				else:
					errors.append("Recipe effects must be arrays")
	return errors


static func validate_counts(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Array or value.is_empty():
		return ["Ingredients/items must be a nonempty array"]
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary:
			errors.append("Ingredients/items must contain objects")
			continue
		if entry.size() != 2 or not entry.get("item") is String or seen.has(entry.get("item")) or not Numbers.whole_number(entry.get("count")) or float(entry.get("count", 0)) < 1:
			errors.append("Ingredients/items require unique item ids and positive counts")
		seen[entry.get("item", "")] = true
	return errors


static func _tags(value: Variant) -> bool:
	if not value is Array:
		return false
	for tag: Variant in value:
		if not tag is String or tag.is_empty():
			return false
	return true


static func validate_links(groups: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var items: Dictionary = {}
	for item: Dictionary in groups.get("items", []):
		items[str(item["id"])] = item
	var dishes: Array[String] = []
	for recipe: Dictionary in groups.get("recipes", []):
		var dish_id: String = str(recipe.get("dish", ""))
		if items.get(dish_id, {}).get("type") != "dish" or dish_id in dishes:
			errors.append(str(recipe["id"]) + ": dish must reference a unique dish item")
		dishes.append(dish_id)
		if recipe.get("starter", false):
			continue
		var taught: bool = false
		for item: Dictionary in items.values():
			if recipe["id"] in item.get("teaches", []):
				taught = true
		if not taught:
			errors.append(str(recipe["id"]) + ": nonstarter recipe has no teaching book")
	for item: Dictionary in items.values():
		if item.get("type") != "cookbook":
			continue
		var available: bool = false
		for shop: Dictionary in groups.get("shops", []):
			for entry: Dictionary in shop.get("items", []):
				available = available or entry.get("item") == item["id"]
		for order: Dictionary in groups.get("orders", []):
			for effect: Dictionary in order.get("reward", []):
				available = available or (effect.get("item") == item["id"] and float(effect.get("add", 0)) > 0)
		for system: Dictionary in groups.get("systems", []):
			for object: Dictionary in system.get("objects", []):
				for entry: Dictionary in object.get("loot", []):
					available = available or (entry.get("item") == item["id"] and float(entry.get("chance", 0)) > 0)
		if not available:
			errors.append(str(item["id"]) + ": cookbook has no shop, salvage or reward source")
	for shop: Dictionary in groups.get("shops", []):
		if not shop.has("owner"):
			var linked: bool = false
			for system: Dictionary in groups.get("systems", []):
				for object: Dictionary in system.get("objects", []):
					linked = linked or (object.get("type") == "planet" and object.get("inhabited", false) and object.get("shop") == shop["id"])
			if not linked:
				errors.append(str(shop["id"]) + ": ownerless shop requires an inhabited planet")
		var owner: Dictionary = {}
		for heroine: Dictionary in groups.get("heroines", []):
			if heroine["id"] == shop.get("owner"):
				owner = heroine
		if owner.get("aboard", false):
			errors.append(str(shop["id"]) + ": shop owner must stay off the ship")
	return errors
