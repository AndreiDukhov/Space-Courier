extends RefCounted

const Numbers = preload("res://scripts/order_rules.gd")


static func count(module_id: String) -> int:
	return int(GameState.state.get("module_storage", {}).get(module_id, 0))


static func pending(module_id: String) -> int:
	var amount: int = 0
	for entry: Dictionary in GameState.state.get("module_deliveries", []):
		if entry["module"] == module_id:
			amount += int(entry["count"])
	return amount


static func migrate(save: Dictionary, fields: Array[String]) -> Dictionary:
	if save.has("module_storage") or save.has("module_deliveries"):
		return save
	var previous: Array[String] = fields.duplicate()
	previous.erase("module_storage")
	previous.erase("module_deliveries")
	for optional: String in ["", "pending_scenes", "meal_invites"]:
		previous.erase(optional)
		if save.size() == previous.size() and save.has_all(previous):
			var result: Dictionary = save.duplicate(true)
			result["module_storage"] = {}
			result["module_deliveries"] = []
			return result
	return save


static func valid(save: Dictionary) -> bool:
	var storage: Variant = save.get("module_storage")
	var deliveries: Variant = save.get("module_deliveries")
	if not storage is Dictionary or not deliveries is Array:
		return false
	for module_id: Variant in storage:
		if not module_id is String or not DataLoader.record_sources.has("modules/" + str(module_id)) or not Numbers.whole_number(storage[module_id]) or storage[module_id] <= 0:
			return false
	for entry: Variant in deliveries:
		if not entry is Dictionary or entry.size() != 3 or not entry.has_all(["module", "count", "arrival_day"]):
			return false
		if not entry["module"] is String or not DataLoader.record_sources.has("modules/" + str(entry["module"])) or not Numbers.whole_number(entry["count"]) or entry["count"] <= 0:
			return false
		if not Numbers.whole_number(entry["arrival_day"]) or entry["arrival_day"] <= save["day"]:
			return false
	return true


static func normalize(save: Dictionary) -> void:
	for module_id: String in save["module_storage"]:
		save["module_storage"][module_id] = int(save["module_storage"][module_id])
	for entry: Dictionary in save["module_deliveries"]:
		entry["count"] = int(entry["count"])
		entry["arrival_day"] = int(entry["arrival_day"])
