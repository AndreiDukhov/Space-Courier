extends RefCounted


static func enemy_for_event(event_id: String) -> String:
	for option: Dictionary in DataLoader.get_record(event_id).get("options", []):
		for effect: Dictionary in option.get("effects", []):
			if effect.has("start_combat"):
				return str(effect["start_combat"])
	return ""


static func enemy_for_npc(npc_id: String) -> String:
	return enemy_for_event(str(DataLoader.get_record(npc_id).get("event", "")))


static func roll(enemy_id: String) -> Array[String]:
	var result: Array[String] = []
	if enemy_id.is_empty():
		return result
	var profiles: Array = DataLoader.get_record(enemy_id).get("loadouts", [])
	if profiles.is_empty():
		return result
	for weapon_id: String in profiles[randi_range(0, profiles.size() - 1)]:
		result.append(weapon_id)
	return result


static func valid(enemy_id: String, weapon_ids: Variant) -> bool:
	if not weapon_ids is Array:
		return false
	if enemy_id.is_empty():
		return weapon_ids.is_empty()
	var seen: Dictionary = {}
	for weapon_id: Variant in weapon_ids:
		if not weapon_id is String or seen.has(weapon_id):
			return false
		seen[weapon_id] = true
	for profile: Array in DataLoader.get_record(enemy_id).get("loadouts", []):
		if profile.size() == weapon_ids.size() and profile.all(func(weapon_id: String) -> bool: return seen.has(weapon_id)):
			return true
	return false


static func weapons(enemy_id: String, weapon_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon: Dictionary in DataLoader.get_record(enemy_id).get("weapons", []):
		if weapon.get("id") in weapon_ids:
			result.append(weapon)
	return result
