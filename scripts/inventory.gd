extends RefCounted


static func is_food(item_id: String) -> bool:
	return DataLoader.get_record(item_id).get("type") in ["ingredient", "dish"]


static func entries(item_id: String) -> Array:
	return GameState.state.get("inventory", []) if is_food(item_id) else GameState.state.get("ship", {}).get("cargo", {}).get("items", [])


static func recipe_for_dish(item_id: String) -> Dictionary:
	for recipe: Dictionary in DataLoader.get_records("recipes"):
		if recipe.get("dish") == item_id:
			return recipe
	return {}


static func change(entries_to_change: Array, item_id: String, amount: int, quality: int = 0) -> void:
	if amount > 0:
		for entry: Dictionary in entries_to_change:
			if entry["item"] == item_id and int(entry.get("quality", 0)) == quality:
				entry["count"] = int(entry["count"]) + amount
				return
		var entry: Dictionary = {"item": item_id, "count": amount}
		if quality > 0:
			entry["quality"] = quality
		entries_to_change.append(entry)
	else:
		var remaining: int = -amount
		for index: int in range(entries_to_change.size() - 1, -1, -1):
			var entry: Dictionary = entries_to_change[index]
			if entry["item"] != item_id or (quality > 0 and int(entry.get("quality", 0)) != quality):
				continue
			var removed: int = mini(remaining, int(entry["count"]))
			remaining -= removed
			entry["count"] = int(entry["count"]) - removed
			if entry["count"] == 0:
				entries_to_change.remove_at(index)
			if remaining == 0:
				break

static func count(item_id: String, entries: Array) -> int:
	var total: int = 0
	for entry: Dictionary in entries:
		if entry.get("item") == item_id:
			total += int(entry.get("count", 0))
	return total


static func mass(entries: Array) -> float:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(DataLoader.get_record(str(entry.get("item", ""))).get("mass", 0)) * int(entry.get("count", 0))
	return total


static func order_mass(orders: Dictionary) -> float:
	var total: float = 0.0
	for order_id: String in orders:
		if orders[order_id].get("status") == "active":
			total += float(DataLoader.get_record(order_id).get("cargo", {}).get("mass", 0))
	return total


static func total_mass(ship: Dictionary, orders: Dictionary) -> float:
	return mass(ship.get("cargo", {}).get("items", [])) + order_mass(orders)
