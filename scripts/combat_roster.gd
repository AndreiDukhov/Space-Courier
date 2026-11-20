extends RefCounted


static func actor(actor_id: String, combat: Dictionary = {}) -> Dictionary:
	combat = _state(combat)
	if actor_id == "player":
		return combat.get("player", {})
	for opponent: Dictionary in ships(combat):
		if opponent["id"] == actor_id:
			return opponent
	return {}


static func ids(combat: Dictionary = {}) -> Array[String]:
	combat = _state(combat)
	var result: Array[String] = ["player"]
	for opponent: Dictionary in ships(combat):
		result.append(str(opponent["id"]))
	return result


static func living(combat: Dictionary = {}) -> Array[Dictionary]:
	combat = _state(combat)
	var result: Array[Dictionary] = []
	for opponent: Dictionary in combat.get("opponents", []):
		if opponent["hull"] > 0:
			result.append(opponent)
	return result


static func at_cell(cell: Vector2i, combat: Dictionary = {}) -> Dictionary:
	combat = _state(combat)
	for opponent: Dictionary in living(combat):
		if _cell(opponent["pos"]) == cell:
			return opponent
	return {}


static func ships(combat: Dictionary = {}) -> Array[Dictionary]:
	combat = _state(combat)
	var result: Array[Dictionary] = []
	result.append_array(combat.get("allies", []))
	result.append_array(combat.get("opponents", []))
	return result


static func friendly(actor_id: String, combat: Dictionary = {}) -> bool:
	combat = _state(combat)
	if actor_id == "player":
		return true
	for ally: Dictionary in combat.get("allies", []):
		if ally["id"] == actor_id:
			return true
	return false


static func target_ids(actor_id: String, combat: Dictionary = {}) -> Array[String]:
	combat = _state(combat)
	var result: Array[String] = []
	if friendly(actor_id, combat):
		for opponent: Dictionary in living(combat):
			result.append(str(opponent["id"]))
	else:
		result.append("player")
		for ally: Dictionary in combat.get("allies", []):
			if ally["hull"] > 0:
				result.append(str(ally["id"]))
	return result


static func target_at(actor_id: String, cell: Vector2i, combat: Dictionary = {}) -> String:
	combat = _state(combat)
	for target_id: String in target_ids(actor_id, combat):
		if _cell(actor(target_id, combat)["pos"]) == cell:
			return target_id
	return ""


static func ally_at(cell: Vector2i, combat: Dictionary = {}) -> bool:
	combat = _state(combat)
	for ally: Dictionary in combat.get("allies", []):
		if ally["hull"] > 0 and _cell(ally["pos"]) == cell:
			return true
	return false


static func blocked(actor_id: String, combat: Dictionary = {}) -> Array[Vector2i]:
	combat = _state(combat)
	var result: Array[Vector2i] = []
	if actor_id != "player":
		result.append(_cell(combat["player"]["pos"]))
	for ship: Dictionary in ships(combat):
		if ship["hull"] > 0 and ship["id"] != actor_id:
			result.append(_cell(ship["pos"]))
	return result


static func history_blocked(actor_id: String, combat: Dictionary) -> Array[Vector2i]:
	if actor_id == "player":
		return blocked(actor_id, combat)
	var result: Array[Vector2i] = [_cell(combat["movement"]["player"]["origin"])]
	var after_actor: bool = false
	for ship: Dictionary in ships(combat):
		if ship["id"] == actor_id:
			after_actor = true
		elif ship["hull"] > 0:
			result.append(_cell(combat["movement"][ship["id"]]["origin"] if after_actor else ship["pos"]))
	return result


static func _cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func _state(combat: Dictionary) -> Dictionary:
	return GameState.state.get("combat", {}) if combat.is_empty() else combat
