extends RefCounted

const Movement = preload("res://scripts/combat_movement.gd")
const WIDTH: int = Movement.BOARD_SIZE.x
const HEIGHT: int = Movement.BOARD_SIZE.y
const ACTION_POINTS: int = 6
const DIRECTIONS: Array[Vector2i] = Movement.DIRECTIONS
const Loadouts = preload("res://scripts/enemy_loadout.gd")
const ShipLoadout = preload("res://scripts/ship_loadout.gd")


static func cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func coordinates(value: Vector2i) -> Array[int]:
	return [value.x, value.y]


static func inside(value: Vector2i) -> bool:
	return value.x >= 0 and value.y >= 0 and value.x < WIDTH and value.y < HEIGHT


static func distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


static func facing_toward(direction: Vector2) -> int:
	return Movement.facing_toward(direction)


static func ability_ap_cost(ability: Dictionary) -> int:
	var cost: Variant = ability.get("cost_ap", 0)
	if cost is String:
		if cost == "all":
			return int(GameState.state.get("combat", {}).get("ap", 0))
		if cost == "half":
			return ceili(float(ACTION_POINTS) * 0.5)
	return int(cost)


static func in_arc(origin: Vector2i, target: Vector2i, facing: int, weapon: Dictionary) -> bool:
	var delta: Vector2 = Vector2(target - origin)
	if delta.is_zero_approx():
		return false
	var forward: Vector2 = Movement.heading(facing)
	var angle: float = absf(rad_to_deg(forward.angle_to(delta.normalized())))
	var half_arc: float = float(weapon["arc_degrees"]) / 2.0
	if weapon["mount"] == "broadside":
		return absf(angle - 90.0) <= half_arc + 0.00001
	return angle <= half_arc + 0.00001


static func accuracy(weapon: Dictionary, distance_to_target: float, evasion: float = 0.0, hull_ratio: float = 1.0, crew_mood: float = 50.0) -> float:
	var reach: int = int(weapon["range"])
	var progress: float = clampf((distance_to_target - 1.0) / float(maxi(1, reach - 1)), 0.0, 1.0)
	var settings: Dictionary = weapon["accuracy"]
	var hull_penalty: float = float(settings["hull_penalty"]) * (1.0 - hull_ratio)
	var mood_bonus: float = float(settings["crew_mood_bonus"]) * (crew_mood - 50.0) / 50.0
	return clampf(lerpf(float(settings["close"]), float(settings["far"]), progress) - hull_penalty + mood_bonus - evasion, 0.0, 1.0)


static func damage(hull: float, shield: float, amount: float, weapon_type: String) -> Dictionary:
	var shield_ratio: float = 0.5 if weapon_type == "kinetic" else 1.0
	var hull_ratio: float = 0.75 if weapon_type == "laser" else 1.0
	var absorbed: float = minf(shield, amount * shield_ratio)
	var remaining: float = maxf(0.0, amount - absorbed / shield_ratio)
	return {"hull": maxf(0.0, hull - remaining * hull_ratio), "shield": maxf(0.0, shield - absorbed)}


static func player_weapon() -> Dictionary:
	var weapons: Array[Dictionary] = player_weapons()
	return weapons[0] if not weapons.is_empty() else {}


static func player_weapons() -> Array[Dictionary]:
	var weapons: Array[Dictionary] = []
	for module_id: String in GameState.state.get("ship", {}).get("modules", []):
		var module: Dictionary = DataLoader.get_record(module_id)
		if module.get("slot") == "weapon":
			weapons.append(module)
	return weapons


static func enemy_weapons() -> Array[Dictionary]:
	var combat: Dictionary = GameState.state["combat"]
	return Loadouts.weapons(str(combat["enemy"]), combat["opponent"]["weapons"])


static func weapon_power(weapon: Dictionary) -> float:
	var average: float = (float(weapon["dmg"][0]) + float(weapon["dmg"][1])) / 2.0
	return average * (1.0 + float(weapon["critical"]["chance"]) * (float(weapon["critical"]["multiplier"]) - 1.0))


static func strongest_first(weapons: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = weapons.duplicate(true)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return weapon_power(a) > weapon_power(b))
	return result


static func movement_settings(player: bool) -> Dictionary:
	return ShipLoadout.movement_settings(GameState.state["ship"]) if player else DataLoader.get_record(str(GameState.state["combat"]["enemy"]))["movement"]


static func player_shield_max() -> float:
	return ShipLoadout.shield_max(GameState.state["ship"])


static func security_mood() -> float:
	if "security" not in GameState.state.get("ship", {}).get("crew_aboard", []):
		return 50.0
	var security: Dictionary = GameState.state.get("heroines", {}).get("security", {})
	return float(security.get("mood", 50.0)) if security.get("aboard", false) else 50.0


static func shot_chance(attacker: Dictionary, target: Vector2i, weapon: Dictionary, player_fires: bool) -> float:
	var combat: Dictionary = GameState.state["combat"]
	var target_actor: String = "opponent" if player_fires else "player"
	if target != cell(combat[target_actor]["pos"]):
		return 0.0
	var hull: Dictionary = GameState.state["ship"]["hull"]
	var ratio: float = float(hull["current"]) / float(hull["max"]) if player_fires else float(combat["opponent"]["hull"]) / float(DataLoader.get_record(str(combat["enemy"]))["hull"])
	var evasion: float = 0.0 if player_fires or target != cell(combat["player"]["pos"]) else float(combat["evasion"]["value"])
	return accuracy(weapon, distance(cell(attacker["pos"]), target), evasion, ratio, security_mood() if player_fires else 50.0)


static func movement_budget() -> int:
	return movement_budget_for(GameState.state.get("ship", {}), GameState.state.get("orders", {}))


static func movement_budget_for(ship: Dictionary, orders: Dictionary) -> int:
	var thrust: int = 1
	for module_id: String in ship.get("modules", []):
		var module: Dictionary = DataLoader.get_record(module_id)
		if module.get("slot") == "engine":
			thrust = int(module["thrust"])
	var mass: float = preload("res://scripts/inventory.gd").total_mass(ship, orders)
	return maxi(1, thrust - floori(mass / 4.0))


static func mood_multiplier(ability: Dictionary) -> float:
	var scale: Dictionary = ability["mood_scale"]
	var path: PackedStringArray = str(scale["stat"]).split(".")
	var mood: float = float(GameState.state["heroines"][path[0]][path[1]])
	return lerpf(float(scale["min"]), float(scale["max"]), mood / 100.0)


static func world_position(value: Array) -> Vector3:
	return Vector3(float(value[0]) - float(WIDTH - 1) / 2.0, 0.15, float(value[1]) - float(HEIGHT - 1) / 2.0)

