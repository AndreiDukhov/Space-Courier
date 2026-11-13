extends RefCounted

const REPUTATIONS: Array[String] = ["state", "mafia", "private"]
const SOURCES: Array[String] = ["private", "state", "crime", "shop"]
const STATUSES: Array[String] = ["active", "completed", "failed"]
const MIN_REPUTATION: int = -100
const MAX_REPUTATION: int = 100


static func initial_reputation() -> Dictionary:
	return {"state": 0, "mafia": 0, "private": 0}


static func whole_number(value: Variant) -> bool:
	return finite_number(value) and floor(float(value)) == float(value)


static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func valid_save(reputation: Variant, orders: Variant, day: int, ship: Dictionary) -> bool:
	if not reputation is Dictionary or reputation.size() != REPUTATIONS.size() or not reputation.has_all(REPUTATIONS):
		return false
	for value: Variant in reputation.values():
		if not whole_number(value) or value < MIN_REPUTATION or value > MAX_REPUTATION:
			return false
	if not orders is Dictionary:
		return false
	var active_mass: float = 0.0
	for order_id: String in orders:
		if not DataLoader.record_sources.has("orders/" + order_id):
			return false
		var entry: Variant = orders[order_id]
		if not entry is Dictionary or entry.size() != 2 or not entry.has_all(["status", "accepted_day"]):
			return false
		if entry["status"] not in STATUSES or not whole_number(entry["accepted_day"]):
			return false
		if entry["accepted_day"] < 1 or entry["accepted_day"] > day:
			return false
		if entry["status"] == "active":
			active_mass += float(DataLoader.get_record(order_id).get("cargo", {}).get("mass", 0))
	var cargo: Variant = ship.get("cargo")
	if not cargo is Dictionary or not finite_number(cargo.get("max_mass")) or float(cargo["max_mass"]) < 0.0:
		return false
	var item_mass: float = 0.0
	var entries: Variant = cargo.get("items")
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if not entry is Dictionary:
			return false
		item_mass += float(DataLoader.get_record(str(entry.get("item", ""))).get("mass", 0)) * float(entry.get("count", 0))
	return active_mass + item_mass <= float(cargo["max_mass"])
