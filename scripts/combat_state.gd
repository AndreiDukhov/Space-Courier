extends RefCounted

const Math = preload("res://scripts/combat_math.gd")
const Rules = preload("res://scripts/order_rules.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Routes = preload("res://scripts/combat_routes.gd")
const Validator = preload("res://scripts/combat_validator.gd")
const ShipLoadout = preload("res://scripts/ship_loadout.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const FIELDS: Array[String] = ["enemy", "source_npc", "round", "ap", "move_points", "player", "opponent", "cooldowns", "evasion", "result", "loot", "movement", "last_shot", "fired", "shots", "shield_recharge"]


static func initial(enemy_id: String, source_npc: String) -> Dictionary:
	var enemy: Dictionary = DataLoader.get_record(enemy_id)
	var delta: Vector2 = Vector2.UP
	if not source_npc.is_empty():
		delta = Motion.point(GameState.state["flight"]["npcs"][source_npc]["pos"]) - Motion.point(GameState.state["flight"]["pos"])
	var facing: int = Math.facing_toward(delta)
	var center: Vector2i = Vector2i(Math.WIDTH / 2, Math.HEIGHT / 2)
	var direction: Vector2i = Math.DIRECTIONS[facing]
	var cooldowns: Dictionary = {}
	for ability: Dictionary in DataLoader.get_records("abilities"):
		cooldowns[ability["id"]] = 0
	var player: Dictionary = {"pos": Math.coordinates(center - direction * 5), "facing": facing, "shield": Math.player_shield_max()}
	var weapon_ids: Array = Loadouts.roll(enemy_id) if source_npc.is_empty() else GameState.state["flight"]["npcs"][source_npc]["weapons"].duplicate()
	var opponent: Dictionary = {"pos": Math.coordinates(center + direction * 5), "facing": (facing + 4) % 8, "hull": float(enemy["hull"]), "shield": float(enemy["shield"]), "weapons": weapon_ids}
	return {
		"enemy": enemy_id, "source_npc": source_npc, "round": 1,
		"ap": Math.ACTION_POINTS, "move_points": Math.movement_budget(),
		"player": player, "opponent": opponent,
		"cooldowns": cooldowns, "evasion": {"value": 0.0, "rounds": 0}, "result": "active", "loot": {},
		"movement": {"player": new_turn(player), "opponent": new_turn(opponent)}, "last_shot": {},
		"fired": {"player": [], "opponent": []}, "shots": [], "shield_recharge": {}
	}


static func migrate(save: Dictionary) -> Dictionary:
	var result: Dictionary = save.duplicate(true)
	var combat: Variant = result.get("combat")
	if combat is Dictionary and not combat.is_empty() and combat.size() == FIELDS.size() - 1 and not combat.has("shield_recharge"):
		combat["shield_recharge"] = {}
		if combat.get("cooldowns") is Dictionary:
			combat["cooldowns"]["shield_reboot"] = 0
	if combat is Dictionary and combat.get("movement") is Dictionary and result.get("ship") is Dictionary:
		for actor: String in ["player", "opponent"]:
			var turn: Variant = combat["movement"].get(actor)
			var vessel: Variant = combat.get(actor)
			var settings: Variant = ShipLoadout.movement_settings(result["ship"]) if actor == "player" else DataLoader.get_record(str(combat.get("enemy", ""))).get("movement")
			if turn is Dictionary and vessel is Dictionary and valid_cell(vessel.get("pos")) and settings is Dictionary and Validator.validate_movement(settings).is_empty():
				_migrate_turn(turn, vessel["pos"], settings)
	return result


static func new_turn(vessel: Dictionary) -> Dictionary:
	return {"origin": vessel["pos"].duplicate(), "facing": int(vessel["facing"]), "history": []}


static func _migrate_turn(turn: Dictionary, position: Array, settings: Dictionary) -> void:
	var history: Variant = turn.get("history")
	if not history is Array or not Rules.whole_number(turn.get("facing")) or turn["facing"] < 0 or turn["facing"] > 7:
		return
	for entry: Variant in history:
		if not entry is Dictionary or entry.size() != 2 or not entry.has_all(["pos", "move_points"]) or not valid_cell(entry["pos"]):
			return
	var facing: int = int(turn["facing"])
	for index: int in range(history.size()):
		var destination: Array = history[index + 1]["pos"] if index + 1 < history.size() else position
		history[index]["facing"] = facing
		facing = Movement.next_facing(Math.cell(history[index]["pos"]), Math.cell(destination), facing, settings)


static func valid_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Rules.whole_number(value[0]) and Rules.whole_number(value[1]) and Math.inside(Math.cell(value))


static func valid_save(save: Dictionary) -> bool:
	if not Validator.validate_movement(save["ship"].get("movement")).is_empty():
		return false
	var modules: Variant = save["ship"].get("modules")
	if not modules is Array:
		return false
	var seen_modules: Dictionary = {}
	for module_id: Variant in modules:
		if not module_id is String or not DataLoader.record_sources.has("modules/" + str(module_id)) or seen_modules.has(module_id):
			return false
		seen_modules[module_id] = true
	var value: Variant = save.get("combat")
	if not value is Dictionary:
		return false
	if value.is_empty():
		return float(save["ship"]["hull"]["current"]) > 0.0
	if value.size() != FIELDS.size() or not value.has_all(FIELDS):
		return false
	if save.get("location") != "ship_bridge" or not save["flight"]["encounter"].is_empty():
		return false
	if not value["enemy"] is String or not DataLoader.record_sources.has("enemies/" + str(value["enemy"])):
		return false
	var source: Variant = value["source_npc"]
	if not source is String:
		return false
	if not source.is_empty():
		if not DataLoader.record_sources.has("npcs/" + str(source)) or source in save["flight"]["defeated_npcs"]:
			return false
		if DataLoader.get_record(source).get("system") != save["current_system"]:
			return false
		var event: Dictionary = DataLoader.get_record(str(DataLoader.get_record(source)["event"]))
		var matches: bool = false
		for option: Dictionary in event.get("options", []):
			for effect: Dictionary in option.get("effects", []):
				matches = matches or effect.get("start_combat") == value["enemy"]
		if not matches:
			return false
	for field: String in ["round", "ap", "move_points"]:
		if not Rules.whole_number(value[field]) or value[field] < 0:
			return false
	var movement_max: int = Math.movement_budget_for(save["ship"], save["orders"])
	var duration_max: int = 0
	for ability: Dictionary in DataLoader.get_records("abilities"):
		var effect: Dictionary = ability["effect"]
		movement_max += ceili(float(effect.get("move_points", 0)) * float(ability["mood_scale"]["max"]))
		duration_max = maxi(duration_max, int(effect.get("duration", 0)))
	if value["round"] < 1 or value["ap"] > Math.ACTION_POINTS or value["move_points"] > movement_max:
		return false
	var pending: Variant = value["shield_recharge"]
	if not pending is Dictionary:
		return false
	if not pending.is_empty():
		var recharge: Dictionary = DataLoader.get_record("shield_reboot")["effect"]
		if pending.size() != 2 or not Rules.finite_number(pending.get("amount")) or pending["amount"] != recharge["shield_restore"] or not Rules.whole_number(pending.get("round")) or pending["round"] <= value["round"] or pending["round"] > value["round"] + recharge["delay"]:
			return false
	for field: String in ["player", "opponent"]:
		var vessel: Variant = value[field]
		var fields: Array = ["pos", "facing", "shield"] if field == "player" else ["pos", "facing", "shield", "hull", "weapons"]
		if not vessel is Dictionary or vessel.size() != fields.size() or not vessel.has_all(fields):
			return false
		if not valid_cell(vessel["pos"]) or not Rules.whole_number(vessel["facing"]) or vessel["facing"] < 0 or vessel["facing"] > 7:
			return false
		var limit: float = ShipLoadout.shield_max(save["ship"]) if field == "player" else float(DataLoader.get_record(value["enemy"])["shield"])
		if not Rules.finite_number(vessel["shield"]) or vessel["shield"] < 0 or vessel["shield"] > limit:
			return false
	if Math.cell(value["player"]["pos"]) == Math.cell(value["opponent"]["pos"]):
		return false
	if not Loadouts.valid(str(value["enemy"]), value["opponent"]["weapons"]):
		return false
	if not source.is_empty() and value["opponent"]["weapons"] != save["flight"]["npcs"][source]["weapons"]:
		return false
	if not _valid_turns(value, ShipLoadout.movement_settings(save["ship"]), movement_max) or not _valid_shot(value, save["ship"]) or not _valid_volley(value, save["ship"]):
		return false
	var hull: Variant = value["opponent"]["hull"]
	if not Rules.finite_number(hull) or hull < 0 or hull > DataLoader.get_record(value["enemy"])["hull"]:
		return false
	if not value["cooldowns"] is Dictionary or value["cooldowns"].size() != DataLoader.get_records("abilities").size():
		return false
	for ability: Dictionary in DataLoader.get_records("abilities"):
		var cooldown: Variant = value["cooldowns"].get(ability["id"])
		if not Rules.whole_number(cooldown) or cooldown < 0 or cooldown > ability["cooldown"]:
			return false
	var evasion: Variant = value["evasion"]
	if not evasion is Dictionary or evasion.size() != 2 or not evasion.has_all(["value", "rounds"]):
		return false
	if not Rules.finite_number(evasion["value"]) or evasion["value"] < 0 or evasion["value"] > 1 or not Rules.whole_number(evasion["rounds"]) or evasion["rounds"] < 0 or evasion["rounds"] > duration_max:
		return false
	if evasion["rounds"] == 0 and evasion["value"] != 0:
		return false
	if value["result"] not in ["active", "victory", "defeat"] or not value["loot"] is Dictionary:
		return false
	var player_hull: float = float(save["ship"]["hull"]["current"])
	match value["result"]:
		"active": return player_hull > 0 and hull > 0 and value["loot"].is_empty()
		"defeat": return player_hull == 0 and hull > 0 and value["loot"].is_empty()
		"victory":
			if player_hull <= 0 or hull != 0 or value["loot"].size() != 2 or not value["loot"].has_all(["money", "fuel"]):
				return false
			var ranges: Dictionary = DataLoader.get_record(value["enemy"])["loot"]
			for field: String in ["money", "fuel"]:
				var amount: Variant = value["loot"][field]
				if not Rules.whole_number(amount) or amount < ranges[field][0] or amount > ranges[field][1]:
					return false
	return true


static func normalize_numbers(value: Dictionary) -> void:
	if value.is_empty():
		return
	for field: String in ["round", "ap", "move_points"]:
		value[field] = int(value[field])
	for field: String in ["player", "opponent"]:
		value[field]["pos"] = Math.coordinates(Math.cell(value[field]["pos"]))
		value[field]["facing"] = int(value[field]["facing"])
		value[field]["shield"] = float(value[field]["shield"])
	value["opponent"]["hull"] = float(value["opponent"]["hull"])
	if not value["shield_recharge"].is_empty():
		value["shield_recharge"]["amount"] = float(value["shield_recharge"]["amount"])
		value["shield_recharge"]["round"] = int(value["shield_recharge"]["round"])
	for key: String in value["cooldowns"]:
		value["cooldowns"][key] = int(value["cooldowns"][key])
	value["evasion"]["rounds"] = int(value["evasion"]["rounds"])
	value["evasion"]["value"] = float(Vector2(float(value["evasion"]["value"]), 0).x)
	for key: String in value["loot"]:
		value["loot"][key] = int(value["loot"][key])
	for turn: Dictionary in value["movement"].values():
		turn["origin"] = Math.coordinates(Math.cell(turn["origin"]))
		turn["facing"] = int(turn["facing"])
		for entry: Dictionary in turn["history"]:
			entry["pos"] = Math.coordinates(Math.cell(entry["pos"]))
			entry["move_points"] = int(entry["move_points"])
			entry["facing"] = int(entry["facing"])
	if not value["last_shot"].is_empty():
		value["last_shot"]["target"] = Math.coordinates(Math.cell(value["last_shot"]["target"]))
		value["last_shot"]["damage"] = float(value["last_shot"]["damage"])
	for shot: Dictionary in value["shots"]:
		shot["origin"] = Math.coordinates(Math.cell(shot["origin"]))
		shot["target"] = Math.coordinates(Math.cell(shot["target"]))
		shot["damage"] = float(shot["damage"])


static func _valid_turns(combat: Dictionary, player_settings: Dictionary, movement_max: int) -> bool:
	var turns: Variant = combat["movement"]
	if not turns is Dictionary or turns.size() != 2 or not turns.has_all(["player", "opponent"]):
		return false
	for actor: String in ["player", "opponent"]:
		var limit: int = movement_max if actor == "player" else int(DataLoader.get_record(str(combat["enemy"]))["speed"])
		var turn: Variant = turns[actor]
		if not turn is Dictionary or turn.size() != 3 or not turn.has_all(["origin", "facing", "history"]):
			return false
		if not valid_cell(turn["origin"]) or not Rules.whole_number(turn["facing"]) or turn["facing"] < 0 or turn["facing"] > 7 or not turn["history"] is Array or turn["history"].size() > limit:
			return false
		var settings: Dictionary = player_settings if actor == "player" else DataLoader.get_record(str(combat["enemy"]))["movement"]
		var origin: Vector2i = Math.cell(turn["origin"])
		var facing: int = int(turn["facing"])
		var history: Array = turn["history"]
		for entry: Variant in history:
			if (
				not entry is Dictionary
				or entry.size() != 3
				or not entry.has_all(["pos", "move_points", "facing"])
				or not valid_cell(entry["pos"])
				or not Rules.whole_number(entry["move_points"])
				or entry["move_points"] < 1
				or entry["move_points"] > limit
			):
				return false
			if not Rules.whole_number(entry["facing"]) or entry["facing"] < 0 or entry["facing"] > 7:
				return false
		var occupied: Vector2i = Math.cell(combat["opponent"]["pos"]) if actor == "player" else Math.cell(turns["player"]["origin"])
		for index: int in range(history.size()):
			var entry: Dictionary = history[index]
			if int(entry["facing"]) != facing or (index == 0 and Math.cell(entry["pos"]) != origin):
				return false
			var destination: Array = history[index + 1]["pos"] if index + 1 < history.size() else combat[actor]["pos"]
			if not valid_cell(destination) or not Movement.cone_contains(Math.cell(entry["pos"]), Math.cell(destination), origin, facing, int(entry["move_points"]), settings, int(turn["facing"]), true):
				return false
			var next_facing: int = int(history[index + 1]["facing"]) if index + 1 < history.size() else int(combat[actor]["facing"])
			# Migrated turns retain the course used before path-based facing.
			var legacy_facing: int = Movement.next_facing(Math.cell(entry["pos"]), Math.cell(destination), facing, settings)
			if next_facing != legacy_facing:
				var path: Array[Vector2i] = Routes.path({"pos": entry["pos"], "facing": facing}, Math.cell(destination), turn, int(entry["move_points"]), settings, occupied)
				if next_facing != Routes.arrival_facing(path):
					return false
			facing = next_facing
		if history.is_empty() and Math.cell(combat[actor]["pos"]) != origin:
			return false
		if int(combat[actor]["facing"]) != facing:
			return false
	return true


static func _valid_shot(combat: Dictionary, ship: Dictionary) -> bool:
	var shot: Variant = combat["last_shot"]
	if not shot is Dictionary:
		return false
	if shot.is_empty():
		return true
	if shot.size() != 5 or not shot.has_all(["shooter", "weapon", "target", "result", "damage"]):
		return false
	if shot["shooter"] not in ["player", "opponent"] or not shot["weapon"] is String or not DataLoader.record_sources.has("modules/" + str(shot["weapon"])) or DataLoader.get_record(shot["weapon"]).get("slot") != "weapon":
		return false
	var owned: bool = shot["weapon"] in ship["modules"]
	if shot["shooter"] == "opponent":
		owned = shot["weapon"] in combat["opponent"]["weapons"]
	if not owned:
		return false
	return valid_cell(shot["target"]) and shot["result"] in ["miss", "hit", "critical"] and Rules.finite_number(shot["damage"]) and shot["damage"] >= 0 and (shot["result"] != "miss" or shot["damage"] == 0)


static func _valid_volley(combat: Dictionary, ship: Dictionary) -> bool:
	var fired: Variant = combat["fired"]
	if not fired is Dictionary or fired.size() != 2 or not fired.has_all(["player", "opponent"]):
		return false
	for actor: String in ["player", "opponent"]:
		var used: Variant = fired[actor]
		if not used is Array:
			return false
		var seen: Dictionary = {}
		for weapon_id: Variant in used:
			if not weapon_id is String or seen.has(weapon_id) or not DataLoader.record_sources.has("modules/" + str(weapon_id)) or DataLoader.get_record(weapon_id).get("slot") != "weapon":
				return false
			var owned: Array = ship["modules"] if actor == "player" else combat["opponent"]["weapons"]
			if weapon_id not in owned:
				return false
			seen[weapon_id] = true
	var shots: Variant = combat["shots"]
	if not shots is Array or shots.size() > Math.ACTION_POINTS:
		return false
	var actor: String = ""
	var weapons: Dictionary = {}
	for shot: Variant in shots:
		if not shot is Dictionary or shot.size() != 6 or not shot.has_all(["shooter", "weapon", "origin", "target", "result", "damage"]) or not valid_cell(shot["origin"]):
			return false
		var check: Dictionary = combat.duplicate(false)
		check["last_shot"] = shot.duplicate(true)
		check["last_shot"].erase("origin")
		if not _valid_shot(check, ship) or (not actor.is_empty() and actor != shot["shooter"]) or weapons.has(shot["weapon"]):
			return false
		actor = str(shot["shooter"])
		if shot["weapon"] not in fired[actor]:
			return false
		weapons[shot["weapon"]] = true
	if not shots.is_empty():
		var last: Dictionary = shots.back().duplicate(true)
		last.erase("origin")
		if last != combat["last_shot"]:
			return false
	return true
