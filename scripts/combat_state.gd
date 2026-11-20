extends RefCounted

const Math = preload("res://scripts/combat_math.gd")
const Rules = preload("res://scripts/order_rules.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Routes = preload("res://scripts/combat_routes.gd")
const Validator = preload("res://scripts/combat_validator.gd")
const ShipLoadout = preload("res://scripts/ship_loadout.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const Roster = preload("res://scripts/combat_roster.gd")
const Battles = preload("res://scripts/ambient_battle_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const FIELDS: Array[String] = ["round", "ap", "move_points", "player", "opponents", "cooldowns", "evasion", "result", "loot", "movement", "last_shot", "fired", "shots", "shield_recharge", "allies", "battle_id"]


static func initial(enemy_id: String, source_npc: String) -> Dictionary:
	var delta: Vector2 = Vector2.UP
	if not source_npc.is_empty():
		delta = Motion.point(GameState.state["flight"]["npcs"][source_npc]["pos"]) - Motion.point(GameState.state["flight"]["pos"])
	var facing: int = Math.facing_toward(delta)
	var center: Vector2i = Vector2i(Math.WIDTH / 2, Math.HEIGHT / 2)
	var direction: Vector2i = Math.DIRECTIONS[facing]
	var player: Dictionary = {"pos": Math.coordinates(center - direction * 5), "facing": facing, "shield": Math.player_shield_max()}
	var sources: Array[String] = Conditions.combat_npcs(source_npc)
	if sources.is_empty():
		sources.append("")
	var opponents: Array[Dictionary] = []
	var turns: Dictionary = {"player": new_turn(player)}
	var fired: Dictionary = {"player": []}
	for index: int in range(sources.size()):
		var source: String = sources[index]
		var definition: String = enemy_id if index == 0 else Loadouts.enemy_for_npc(source)
		var enemy: Dictionary = DataLoader.get_record(definition)
		var actor_id: String = "opponent" if index == 0 else "opponent_2"
		var position: Vector2i = center + direction * 5 + Vector2i(-direction.y, direction.x) * (index * 5)
		var weapons: Array = Loadouts.roll(definition) if source.is_empty() else GameState.state["flight"]["npcs"][source]["weapons"].duplicate()
		var opponent: Dictionary = {"id": actor_id, "enemy": definition, "source_npc": source, "pos": Math.coordinates(position), "facing": (facing + 4) % 8, "hull": float(enemy["hull"]), "shield": float(enemy["shield"]), "weapons": weapons}
		opponents.append(opponent)
		turns[actor_id] = new_turn(opponent)
		fired[actor_id] = []
	var cooldowns: Dictionary = {}
	for ability: Dictionary in DataLoader.get_records("abilities"):
		cooldowns[ability["id"]] = 0
	return {
		"round": 1, "ap": Math.ACTION_POINTS, "move_points": Math.movement_budget(),
		"player": player, "opponents": opponents, "allies": [], "battle_id": "",
		"cooldowns": cooldowns, "evasion": {"value": 0.0, "rounds": 0}, "result": "active", "loot": {},
		"movement": turns, "last_shot": {}, "fired": fired, "shots": [], "shield_recharge": {}
	}


static func intervention(battle: Dictionary, side: int) -> Dictionary:
	var hostile: Array = battle["sides"][1 - side]
	var combat: Dictionary = initial(Loadouts.enemy_for_npc(str(hostile[0])), str(hostile[0]))
	combat["opponents"] = []
	combat["allies"] = []
	combat["battle_id"] = battle["id"]
	combat["movement"] = {"player": new_turn(combat["player"])}
	combat["fired"] = {"player": []}
	var facing: int = int(combat["player"]["facing"])
	var direction: Vector2i = Math.DIRECTIONS[facing]
	var lateral: Vector2i = Vector2i(-direction.y, direction.x)
	var center: Vector2i = Vector2i(Math.WIDTH / 2, Math.HEIGHT / 2)
	for group: String in ["allies", "opponents"]:
		var sources: Array = battle["sides"][side] if group == "allies" else hostile
		for index: int in range(sources.size()):
			var npc_id: String = str(sources[index])
			var enemy_id: String = Loadouts.enemy_for_npc(npc_id)
			var enemy: Dictionary = DataLoader.get_record(enemy_id)
			var prefix: String = "ally" if group == "allies" else "opponent"
			var actor_id: String = prefix if index == 0 else prefix + "_2"
			var position: Vector2i = Math.cell(combat["player"]["pos"]) + lateral * (3 if index == 0 else -3) if group == "allies" else center + direction * 5 + lateral * (index * 5)
			var ship: Dictionary = {"id": actor_id, "enemy": enemy_id, "source_npc": npc_id, "pos": Math.coordinates(position), "facing": facing if group == "allies" else (facing + 4) % 8, "hull": float(enemy["hull"]), "shield": float(enemy["shield"]), "weapons": GameState.state["flight"]["npcs"][npc_id]["weapons"].duplicate()}
			combat[group].append(ship)
			combat["movement"][actor_id] = new_turn(ship)
			combat["fired"][actor_id] = []
	return combat


static func migrate(save: Dictionary) -> Dictionary:
	var result: Dictionary = save.duplicate(true)
	var combat: Variant = result.get("combat")
	if not combat is Dictionary or combat.is_empty():
		return result
	if combat.size() in [15, 16] and combat.has_all(["enemy", "source_npc", "opponent"]) and not combat.has("opponents") and combat["opponent"] is Dictionary:
		var opponent: Dictionary = combat["opponent"].duplicate(true)
		opponent.merge({"id": "opponent", "enemy": combat["enemy"], "source_npc": combat["source_npc"]})
		combat["opponents"] = [opponent]
		for field: String in ["enemy", "source_npc", "opponent"]:
			combat.erase(field)
	if combat.size() == 13 and not combat.has("shield_recharge"):
		combat["shield_recharge"] = {}
		if combat.get("cooldowns") is Dictionary:
			combat["cooldowns"]["shield_reboot"] = 0
	if combat.size() == 14 and not combat.has("allies") and not combat.has("battle_id"):
		combat["allies"] = []
		combat["battle_id"] = ""
	if not combat.get("opponents") is Array:
		return result
	if not combat.get("allies") is Array:
		return result
	for opponent: Variant in combat["opponents"] + combat["allies"]:
		if not opponent is Dictionary or not opponent.get("id") is String:
			return result
	if combat.get("movement") is Dictionary and result.get("ship") is Dictionary:
		for actor_id: String in Roster.ids(combat):
			var turn: Variant = combat["movement"].get(actor_id)
			var vessel: Dictionary = Roster.actor(actor_id, combat)
			var settings: Variant = ShipLoadout.movement_settings(result["ship"]) if actor_id == "player" else DataLoader.get_record(str(vessel.get("enemy", ""))).get("movement")
			if turn is Dictionary and valid_cell(vessel.get("pos")) and settings is Dictionary and Validator.validate_movement(settings).is_empty():
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
	if not _valid_opponents(value, save):
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
	var player: Variant = value["player"]
	if not player is Dictionary or player.size() != 3 or not player.has_all(["pos", "facing", "shield"]):
		return false
	if not _valid_vessel(player, ShipLoadout.shield_max(save["ship"])):
		return false
	for opponent: Dictionary in Roster.ships(value):
		if opponent["hull"] > 0 and Math.cell(player["pos"]) == Math.cell(opponent["pos"]):
			return false
	if not _valid_turns(value, ShipLoadout.movement_settings(save["ship"]), movement_max) or not _valid_shot(value, save["ship"]) or not _valid_volley(value, save["ship"]):
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
	var survivors: bool = not Roster.living(value).is_empty()
	match value["result"]:
		"active": return player_hull > 0 and survivors and value["loot"].is_empty()
		"defeat": return player_hull == 0 and survivors and value["loot"].is_empty()
		"victory":
			if player_hull <= 0 or survivors or value["loot"].size() != 2 or not value["loot"].has_all(["money", "fuel"]):
				return false
			for field: String in ["money", "fuel"]:
				var minimum: int = 0
				var maximum: int = 0
				for opponent: Dictionary in value["opponents"]:
					var bounds: Array = DataLoader.get_record(str(opponent["enemy"]))["loot"][field]
					minimum += int(bounds[0])
					maximum += int(bounds[1])
				var amount: Variant = value["loot"][field]
				if not Rules.whole_number(amount) or amount < minimum or amount > maximum:
					return false
	return true


static func _valid_vessel(vessel: Dictionary, shield_max: float) -> bool:
	return valid_cell(vessel["pos"]) and Rules.whole_number(vessel["facing"]) and vessel["facing"] >= 0 and vessel["facing"] <= 7 and Rules.finite_number(vessel["shield"]) and vessel["shield"] >= 0 and vessel["shield"] <= shield_max


static func _valid_opponents(combat: Dictionary, save: Dictionary) -> bool:
	if not combat["opponents"] is Array or combat["opponents"].is_empty() or combat["opponents"].size() > 2 or not combat["allies"] is Array or combat["allies"].size() > 2 or not combat["battle_id"] is String:
		return false
	var sources: Dictionary = {}
	var positions: Dictionary = {}
	for group: String in ["allies", "opponents"]:
		for index: int in range(combat[group].size()):
			var opponent: Variant = combat[group][index]
			var prefix: String = "ally" if group == "allies" else "opponent"
			var expected_id: String = prefix if index == 0 else prefix + "_2"
			if not opponent is Dictionary or opponent.size() != 8 or not opponent.has_all(["id", "enemy", "source_npc", "pos", "facing", "hull", "shield", "weapons"]) or opponent["id"] != expected_id:
				return false
			if not opponent["enemy"] is String or not DataLoader.record_sources.has("enemies/" + str(opponent["enemy"])) or not opponent["source_npc"] is String:
				return false
			var enemy: Dictionary = DataLoader.get_record(opponent["enemy"])
			if not _valid_vessel(opponent, float(enemy["shield"])) or not Rules.finite_number(opponent["hull"]) or opponent["hull"] < 0 or opponent["hull"] > enemy["hull"]:
				return false
			var cell: Vector2i = Math.cell(opponent["pos"])
			if (opponent["hull"] > 0 and positions.has(cell)) or not Loadouts.valid(str(opponent["enemy"]), opponent["weapons"]):
				return false
			if opponent["hull"] > 0:
				positions[cell] = true
			var source: String = str(opponent["source_npc"])
			if source.is_empty():
				if group != "opponents" or combat["opponents"].size() != 1 or not combat["allies"].is_empty() or not combat["battle_id"].is_empty():
					return false
				continue
			if sources.has(source) or not DataLoader.record_sources.has("npcs/" + source) or source in save["flight"]["defeated_npcs"]:
				return false
			sources[source] = true
			var npc: Dictionary = DataLoader.get_record(source)
			if npc.get("system") != save["current_system"] or opponent["weapons"] != save["flight"]["npcs"][source]["weapons"] or Loadouts.enemy_for_npc(source) != opponent["enemy"]:
				return false
	if combat["battle_id"].is_empty():
		return combat["allies"].is_empty()
	var battle: Dictionary = Battles.find(combat["battle_id"], save["flight"]["battles"])
	if battle.is_empty() or battle["system"] != save["current_system"]:
		return false
	for side: int in range(2):
		if _same_sources(combat["allies"], battle["sides"][side]) and _same_sources(combat["opponents"], battle["sides"][1 - side]):
			return true
	return false


static func _same_sources(ships: Array, sources: Array) -> bool:
	if ships.size() != sources.size():
		return false
	for ship: Dictionary in ships:
		if ship["source_npc"] not in sources:
			return false
	return true


static func normalize_numbers(value: Dictionary) -> void:
	if value.is_empty():
		return
	for field: String in ["round", "ap", "move_points"]:
		value[field] = int(value[field])
	for actor_id: String in Roster.ids(value):
		var vessel: Dictionary = Roster.actor(actor_id, value)
		vessel["pos"] = Math.coordinates(Math.cell(vessel["pos"]))
		vessel["facing"] = int(vessel["facing"])
		vessel["shield"] = float(vessel["shield"])
		if actor_id != "player":
			vessel["hull"] = float(vessel["hull"])
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
	if not turns is Dictionary or turns.size() != Roster.ids(combat).size() or not turns.has_all(Roster.ids(combat)):
		return false
	for turn: Variant in turns.values():
		if not turn is Dictionary or turn.size() != 3 or not turn.has_all(["origin", "facing", "history"]) or not valid_cell(turn["origin"]) or not Rules.whole_number(turn["facing"]) or turn["facing"] < 0 or turn["facing"] > 7 or not turn["history"] is Array:
			return false
	for actor: String in Roster.ids(combat):
		var vessel: Dictionary = Roster.actor(actor, combat)
		var limit: int = movement_max if actor == "player" else int(DataLoader.get_record(str(vessel["enemy"]))["speed"])
		var turn: Variant = turns[actor]
		if not turn is Dictionary or turn.size() != 3 or not turn.has_all(["origin", "facing", "history"]):
			return false
		if not valid_cell(turn["origin"]) or not Rules.whole_number(turn["facing"]) or turn["facing"] < 0 or turn["facing"] > 7 or not turn["history"] is Array or turn["history"].size() > limit:
			return false
		var settings: Dictionary = player_settings if actor == "player" else DataLoader.get_record(str(vessel["enemy"]))["movement"]
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
		var occupied: Array[Vector2i] = Roster.history_blocked(actor, combat)
		for index: int in range(history.size()):
			var entry: Dictionary = history[index]
			if int(entry["facing"]) != facing or (index == 0 and Math.cell(entry["pos"]) != origin):
				return false
			var destination: Array = history[index + 1]["pos"] if index + 1 < history.size() else vessel["pos"]
			if not valid_cell(destination) or not Movement.cone_contains(Math.cell(entry["pos"]), Math.cell(destination), origin, facing, int(entry["move_points"]), settings, int(turn["facing"]), true):
				return false
			var next_facing: int = int(history[index + 1]["facing"]) if index + 1 < history.size() else int(vessel["facing"])
			# Migrated turns retain the course used before path-based facing.
			var legacy_facing: int = Movement.next_facing(Math.cell(entry["pos"]), Math.cell(destination), facing, settings)
			if next_facing != legacy_facing:
				var path: Array[Vector2i] = Routes.path({"pos": entry["pos"], "facing": facing}, Math.cell(destination), turn, int(entry["move_points"]), settings, occupied)
				if next_facing != Routes.arrival_facing(path):
					return false
			facing = next_facing
		if history.is_empty() and Math.cell(vessel["pos"]) != origin:
			return false
		if int(vessel["facing"]) != facing:
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
	if shot["shooter"] not in Roster.ids(combat) or not shot["weapon"] is String or not DataLoader.record_sources.has("modules/" + str(shot["weapon"])) or DataLoader.get_record(shot["weapon"]).get("slot") != "weapon":
		return false
	var owned: Array = ship["modules"] if shot["shooter"] == "player" else Roster.actor(str(shot["shooter"]), combat)["weapons"]
	return shot["weapon"] in owned and valid_cell(shot["target"]) and shot["result"] in ["miss", "hit", "critical"] and Rules.finite_number(shot["damage"]) and shot["damage"] >= 0 and (shot["result"] != "miss" or shot["damage"] == 0)


static func _valid_volley(combat: Dictionary, ship: Dictionary) -> bool:
	var fired: Variant = combat["fired"]
	var actors: Array[String] = Roster.ids(combat)
	if not fired is Dictionary or fired.size() != actors.size() or not fired.has_all(actors):
		return false
	for actor_id: String in actors:
		var used: Variant = fired[actor_id]
		if not used is Array:
			return false
		var seen: Dictionary = {}
		for weapon_id: Variant in used:
			if not weapon_id is String or seen.has(weapon_id) or not DataLoader.record_sources.has("modules/" + str(weapon_id)) or DataLoader.get_record(weapon_id).get("slot") != "weapon":
				return false
			var owned: Array = ship["modules"] if actor_id == "player" else Roster.actor(actor_id, combat)["weapons"]
			if weapon_id not in owned:
				return false
			seen[weapon_id] = true
	var shots: Variant = combat["shots"]
	if not shots is Array or shots.size() > Math.ACTION_POINTS * Roster.ships(combat).size():
		return false
	var weapons: Dictionary = {}
	var costs: Dictionary = {}
	var player_volley: bool = false
	var enemy_volley: bool = false
	for shot: Variant in shots:
		if not shot is Dictionary or shot.size() != 6 or not shot.has_all(["shooter", "weapon", "origin", "target", "result", "damage"]) or not valid_cell(shot["origin"]):
			return false
		var check: Dictionary = combat.duplicate(false)
		check["last_shot"] = shot.duplicate(true)
		check["last_shot"].erase("origin")
		if not _valid_shot(check, ship):
			return false
		var actor_id: String = str(shot["shooter"])
		var key: String = actor_id + "/" + str(shot["weapon"])
		if weapons.has(key) or shot["weapon"] not in fired[actor_id]:
			return false
		weapons[key] = true
		costs[actor_id] = int(costs.get(actor_id, 0)) + int(DataLoader.get_record(str(shot["weapon"]))["ap_cost"])
		if costs[actor_id] > Math.ACTION_POINTS:
			return false
		player_volley = player_volley or actor_id == "player"
		enemy_volley = enemy_volley or actor_id != "player"
	if player_volley and enemy_volley:
		return false
	if not shots.is_empty():
		var last: Dictionary = shots.back().duplicate(true)
		last.erase("origin")
		if last != combat["last_shot"]:
			return false
	return true
