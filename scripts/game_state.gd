extends Node

signal restored

const Orders = preload("res://scripts/order_rules.gd")
const Galaxy = preload("res://scripts/galaxy_state.gd")
const Flight = preload("res://scripts/flight_state.gd")
const Combat = preload("res://scripts/combat_state.gd")
const Domestic = preload("res://scripts/domestic_state.gd")
const SceneQueue = preload("res://scripts/scene_queue.gd")
const Loadout = preload("res://scripts/ship_loadout.gd")
const SAVE_PATH: String = "user://save.json"
const INITIAL_MONEY: int = 1000
const INITIAL_LOCATION: String = "hub_kitchen"
const SHIP_INTERIOR_FLAG: String = "ship_interior_open"
const HEROINE_STAT_FIELDS: Array[String] = ["attitude", "mood", "arousal"]
const SAVE_FIELDS: Array[String] = ["day", "time_slot", "money", "flags", "known_routes", "heroines", "ship", "location", "reputation", "orders", "current_system", "systems", "public_routes", "flight", "combat", "inventory", "known_recipes", "cooking_skill", "buffs", "served_days", "kitchen", "meal_invites", "pending_scenes"]

var state: Dictionary = {}


func _ready() -> void:
	state = {}


func start_new_game(heroine_records: Array[Dictionary], ship_record: Dictionary) -> void:
	var heroine_states: Dictionary = {}
	for heroine: Dictionary in heroine_records:
		var heroine_id: String = str(heroine.get("id", ""))
		if heroine_id.is_empty():
			continue
		var stats: Dictionary = heroine.get("stats", {})
		heroine_states[heroine_id] = {
			"attitude": float(stats.get("attitude", 0)),
			"mood": float(stats.get("mood", 50)),
			"arousal": float(stats.get("arousal", 0)),
			"aboard": bool(heroine.get("aboard", false)),
			"suspicion": int(heroine.get("suspicion", 0)),
			"contact_block": bool(heroine.get("contact_block", false)),
			"polygamy": str(heroine.get("polygamy", "tolerates")),
			"loc": ""
		}

	state = {
		"day": 1,
		"time_slot": "morning",
		"money": INITIAL_MONEY,
		"known_routes": Galaxy.initial_routes("known"),
		"public_routes": Galaxy.initial_routes("public"),
		"current_system": Galaxy.INITIAL_SYSTEM,
		"systems": Galaxy.initial_systems(),
		"flight": Flight.initial(),
		"combat": {},
		"flags": {},
		"heroines": heroine_states,
		"ship": ship_record.duplicate(true),
		"location": INITIAL_LOCATION,
		"reputation": Orders.initial_reputation(),
		"orders": {}
	}
	state.merge({"inventory": [], "known_recipes": Domestic.initial_recipes(), "cooking_skill": 0, "buffs": {}, "served_days": {}, "kitchen": {}, "meal_invites": {}, "pending_scenes": []})
	_normalize_fuel()
	if ScheduleManager.assign_locations() != OK:
		push_error("GameState: could not initialize schedules")


func serialize() -> Dictionary:
	return state.duplicate(true)


func restore(save_data: Dictionary) -> Error:
	var previous_fields: Array[String] = SAVE_FIELDS.duplicate()
	previous_fields.erase("pending_scenes")
	if save_data.size() == previous_fields.size() and save_data.has_all(previous_fields):
		save_data = save_data.duplicate(true)
		save_data["pending_scenes"] = []
	previous_fields.erase("meal_invites")
	if save_data.size() == previous_fields.size() and save_data.has_all(previous_fields):
		save_data = save_data.duplicate(true)
		save_data["meal_invites"] = {}
		save_data["pending_scenes"] = []
	if save_data.get("flight") is Dictionary and save_data["flight"].size() in [6, 7] and not save_data["flight"].has("map_scale"):
		save_data = save_data.duplicate(true)
		save_data["flight"] = Flight.migrate(save_data["flight"])
		if save_data.get("systems") is Dictionary:
			for system: Dictionary in DataLoader.get_records("systems"):
				if not save_data["systems"].has(system["id"]):
					save_data["systems"][system["id"]] = "hidden"
	if save_data.get("flight") is Dictionary:
		save_data = save_data.duplicate(true)
		save_data["flight"] = Flight.expand_population(save_data["flight"])
		save_data["flight"] = Flight.upgrade_traffic(save_data["flight"])
	save_data = Domestic.migrate(save_data)
	save_data = Loadout.migrate(save_data)
	save_data = Combat.migrate(save_data)
	if not _is_valid_state(save_data):
		return ERR_INVALID_DATA
	state = save_data.duplicate(true)
	state["day"] = int(state["day"])
	state["money"] = int(state["money"])
	_normalize_fuel()
	Flight.normalize_numbers(state["flight"])
	Combat.normalize_numbers(state["combat"])
	Domestic.normalize(state)
	state["ship"]["hull"]["current"] = float(state["ship"]["hull"]["current"])
	for reputation_id: String in Orders.REPUTATIONS:
		state["reputation"][reputation_id] = int(state["reputation"][reputation_id])
	for order: Dictionary in state["orders"].values():
		order["accepted_day"] = int(order["accepted_day"])
	for heroine: Dictionary in state["heroines"].values():
		for stat_name: String in HEROINE_STAT_FIELDS:
			heroine[stat_name] = float(heroine[stat_name])
		heroine["suspicion"] = int(heroine["suspicion"])
	restored.emit()
	return OK


func _normalize_fuel() -> void:
	state["ship"]["fuel"]["current"] = snappedf(float(state["ship"]["fuel"]["current"]), 1.0 / 1073741824.0)
	state["ship"]["fuel"]["max"] = int(state["ship"]["fuel"]["max"])


func save_game(save_path: String = SAVE_PATH) -> Error:
	if not _is_valid_state(state):
		return ERR_INVALID_DATA
	var directory_path: String = ProjectSettings.globalize_path(save_path).get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK:
		return directory_error
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(serialize(), "\t", true, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error


func load_game(save_path: String = SAVE_PATH) -> Error:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return parse_error
	if not parser.data is Dictionary:
		return ERR_INVALID_DATA
	return restore(parser.data)


func _is_valid_state(save_data: Dictionary) -> bool:
	if save_data.size() != SAVE_FIELDS.size() or not save_data.has_all(SAVE_FIELDS):
		return false
	for field_name: String in ["day", "money"]:
		var number: Variant = save_data[field_name]
		if not (number is int or number is float):
			return false
		if not is_finite(float(number)) or floor(float(number)) != float(number):
			return false
	if save_data["day"] < 1:
		return false
	if not save_data["time_slot"] is String or save_data["time_slot"] not in Clock.TIME_SLOTS:
		return false
	for field_name: String in ["flags", "heroines", "ship"]:
		if not save_data[field_name] is Dictionary:
			return false
	if not Galaxy.valid_save(save_data):
		return false
	if not Flight.valid_save(save_data.get("flight"), str(save_data.get("current_system", ""))):
		return false
	for route_id: String in save_data["flight"]["autopilot"].get("routes", []):
		if route_id not in save_data.get("known_routes", []):
			return false
	if not Orders.valid_save(save_data.get("reputation"), save_data.get("orders"), int(save_data["day"]), save_data["ship"]):
		return false
	if not Domestic.valid_save(save_data):
		return false
	if not SceneQueue.valid_save(save_data.get("pending_scenes")):
		return false
	var hull: Variant = save_data["ship"].get("hull")
	if not hull is Dictionary or not Orders.finite_number(hull.get("current")) or not Orders.whole_number(hull.get("max")) or hull["max"] <= 0 or hull["current"] < 0 or hull["current"] > hull["max"]:
		return false
	if not Combat.valid_save(save_data):
		return false
	if not Loadout.valid(save_data["ship"]):
		return false
	if not save_data["flight"]["encounter"].is_empty() and save_data.get("location") != "ship_bridge":
		return false
	for flag_value: Variant in save_data["flags"].values():
		if not flag_value is bool:
			return false
	if save_data["flags"].get(SHIP_INTERIOR_FLAG, false):
		if save_data.get("location") != "ship_bridge" or not save_data["combat"].is_empty() or not save_data["flight"]["encounter"].is_empty():
			return false
	if not save_data["location"] is String or not DataLoader.record_sources.has("locations/" + str(save_data["location"])):
		return false
	if save_data["heroines"].size() != DataLoader.get_records("heroines").size():
		return false
	for heroine_id: String in save_data["heroines"]:
		var heroine_state: Variant = save_data["heroines"][heroine_id]
		if not DataLoader.record_sources.has("heroines/" + heroine_id) or not heroine_state is Dictionary:
			return false
		if not heroine_state.get("loc") is String or not DataLoader.record_sources.has("locations/" + str(heroine_state["loc"])):
			return false
		for stat_name: String in HEROINE_STAT_FIELDS + ["suspicion"]:
			var stat_value: Variant = heroine_state.get(stat_name)
			if not (stat_value is int or stat_value is float) or not is_finite(float(stat_value)):
				return false
			if float(stat_value) < 0.0 or float(stat_value) > 100.0:
				return false
		if float(heroine_state["suspicion"]) != floor(float(heroine_state["suspicion"])):
			return false
		if not heroine_state.get("aboard") is bool or not heroine_state.get("contact_block") is bool or heroine_state.get("polygamy") not in ["accepts", "tolerates", "forbids"]:
			return false
	if not save_data["known_routes"] is Array:
		return false
	for route_id: Variant in save_data["known_routes"]:
		if not route_id is String or str(route_id).is_empty():
			return false
	return true
