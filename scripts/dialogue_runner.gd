extends RefCounted

const Conditions = preload("res://scripts/condition_evaluator.gd")


static func is_available(scene: Dictionary) -> bool:
	return Conditions.evaluate_scene(scene)


static func choose(scene_id: String, choice_id: String) -> Error:
	if not DataLoader.record_sources.has("scenes/" + scene_id):
		return ERR_INVALID_PARAMETER
	var scene: Dictionary = DataLoader.get_record(scene_id)
	if not is_available(scene):
		return ERR_UNAVAILABLE
	for choice: Dictionary in scene.get("choices", []):
		if choice.get("id") != choice_id:
			continue
		var effects: Array = choice.get("effects", []).duplicate(true)
		effects.append_array(scene.get("on_end", []).duplicate(true))
		effects.append_array(EffectApplier.scene_end_effects(scene))
		var result: Error = EffectApplier.apply_effects(effects)
		if result == OK:
			EffectApplier.complete_scene(scene_id)
		return result
	return ERR_INVALID_PARAMETER
