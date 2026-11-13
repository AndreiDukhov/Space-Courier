extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Runner = preload("res://scripts/dialogue_runner.gd")
const TRAVEL_SLOTS: int = 0
const WAIT_SLOTS: int = 1


static func occupants(location_id: String) -> Array[String]:
	var result: Array[String] = []
	for heroine_id: String in GameState.state.get("heroines", {}):
		if GameState.state["heroines"][heroine_id].get("loc") == location_id and Conditions.heroine_visible(heroine_id):
			result.append(heroine_id)
	return result


static func dialogues_for(heroine_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Conditions.is_present(heroine_id):
		return result
	for scene: Dictionary in DataLoader.get_records("scenes"):
		if not Runner.is_available(scene):
			continue
		for line: Dictionary in scene.get("lines", []):
			if line.get("who") == heroine_id:
				result.append(scene)
				break
	return result


static func travel(location_id: String) -> Error:
	var result: Error = EffectApplier.move_player(location_id)
	if result == OK and TRAVEL_SLOTS > 0:
		return EffectApplier.apply_effects([{"advance_time": TRAVEL_SLOTS}])
	return result


static func wait() -> Error:
	if not Conditions.can_wait():
		return ERR_UNAVAILABLE
	return EffectApplier.apply_effects([{"advance_time": WAIT_SLOTS}])
