extends RefCounted

const Inventory = preload("res://scripts/inventory.gd")
const Numbers = preload("res://scripts/order_rules.gd")
const Meals = preload("res://scripts/meal_schedule.gd")
const ZONES: Array[String] = ["cut", "boil", "fry", "plate"]


static func initial_recipes() -> Array[String]:
	var result: Array[String] = []
	for recipe: Dictionary in DataLoader.get_records("recipes"):
		if recipe.get("starter", false):
			result.append(str(recipe["id"]))
	return result


static func valid_entries(value: Variant, food: bool) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("item") is String or not DataLoader.record_sources.has("items/" + str(entry["item"])):
			return false
		var item_id: String = str(entry["item"])
		if Inventory.is_food(item_id) != food or not Numbers.whole_number(entry.get("count")) or float(entry["count"]) < 1:
			return false
		var dish: bool = DataLoader.get_record(item_id).get("type") == "dish"
		if entry.size() != (3 if dish else 2):
			return false
		if dish and (not Numbers.whole_number(entry.get("quality")) or float(entry["quality"]) < 1 or float(entry["quality"]) > 3):
			return false
		var key: String = item_id + ":" + str(int(entry.get("quality", 0)))
		if seen.has(key):
			return false
		seen[key] = true
	return true


static func valid_save(save: Dictionary) -> bool:
	if not valid_entries(save.get("inventory"), true) or not valid_entries(save.get("ship", {}).get("cargo", {}).get("items"), false):
		return false
	if not Numbers.whole_number(save.get("cooking_skill")) or float(save["cooking_skill"]) < 0:
		return false
	if not save.get("known_recipes") is Array:
		return false
	var seen: Dictionary = {}
	for recipe_id: Variant in save["known_recipes"]:
		if not recipe_id is String or not DataLoader.record_sources.has("recipes/" + recipe_id) or seen.has(recipe_id):
			return false
		seen[recipe_id] = true
	for recipe_id: String in initial_recipes():
		if recipe_id not in save["known_recipes"]:
			return false
	if not save.get("buffs") is Dictionary or not save.get("served_days") is Dictionary:
		return false
	for buff_id: String in save["buffs"]:
		if buff_id != "steady_hands" or not Numbers.whole_number(save["buffs"][buff_id]) or int(save["buffs"][buff_id]) <= int(save["day"]):
			return false
	for heroine_id: String in save["served_days"]:
		var day: Variant = save["served_days"][heroine_id]
		if not save.get("heroines", {}).has(heroine_id) or not Numbers.whole_number(day) or int(day) < 1 or int(day) > int(save["day"]):
			return false
	return valid_kitchen(save.get("kitchen"), save) and Meals.valid_save(save.get("meal_invites"), save)


static func valid_kitchen(value: Variant, save: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if value.size() != 2 or not value.has_all(["recipe", "entries"]):
		return false
	if not value["recipe"] is String or value["recipe"] not in save.get("known_recipes", []) or not value["entries"] is Array or value["entries"].is_empty():
		return false
	if save.get("location") != "hub_kitchen" or not save.get("combat", {}).is_empty():
		return false
	var recipe: Dictionary = DataLoader.get_record(str(value["recipe"]))
	var required: Dictionary = {}
	for ingredient: Dictionary in recipe.get("ingredients", []):
		required[ingredient["item"]] = int(ingredient["count"])
	var counts: Dictionary = {}
	for entry: Variant in value["entries"]:
		if not entry is Dictionary or entry.size() != 3 or not entry.get("item") is String or not entry.get("steps") is Array or entry.get("zone") not in ZONES:
			return false
		var item_id: String = str(entry["item"])
		counts[item_id] = int(counts.get(item_id, 0)) + 1
		if counts[item_id] > int(required.get(item_id, 0)) or counts[item_id] > Inventory.count(item_id, save["inventory"]):
			return false
		var preparations: Array = DataLoader.get_record(item_id).get("preparations", [])
		var seen: Array = []
		for step: Variant in entry["steps"]:
			if step not in preparations or step in seen:
				return false
			seen.append(step)
		if entry["zone"] == "plate" and seen.is_empty():
			return false
	return true


static func reserved(item_id: String, kitchen: Dictionary) -> int:
	var total: int = 0
	for entry: Dictionary in kitchen.get("entries", []):
		if entry["item"] == item_id:
			total += 1
	return total


static func migrate(save: Dictionary) -> Dictionary:
	var result: Dictionary = save.duplicate(true)
	var kitchen: Variant = result.get("kitchen")
	if kitchen is Dictionary and kitchen.size() == 4 and kitchen.has_all(["recipe", "item", "steps", "zone"]):
		result["kitchen"] = {"recipe": kitchen["recipe"], "entries": [{"item": kitchen["item"], "steps": kitchen["steps"], "zone": kitchen["zone"]}]}
	var known: Variant = result.get("known_recipes")
	if known is Array and "recipe_carrot_01" in known and "recipe_carrot_noodles" not in known:
		known.append("recipe_carrot_noodles")
	return result


static func normalize(save: Dictionary) -> void:
	save["cooking_skill"] = int(save["cooking_skill"])
	for entries: Array in [save["inventory"], save["ship"]["cargo"]["items"]]:
		for entry: Dictionary in entries:
			entry["count"] = int(entry["count"])
			if entry.has("quality"):
				entry["quality"] = int(entry["quality"])
	for field: String in ["buffs", "served_days"]:
		for key: String in save[field]:
			save[field][key] = int(save[field][key])
	for entry: Dictionary in save["meal_invites"].values():
		entry["day"] = int(entry["day"])
		entry["quality"] = int(entry["quality"])
