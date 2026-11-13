extends RefCounted


static func select(blueprint: Dictionary, state: Dictionary) -> Dictionary:
	var mood: float = float(state.get("mood", 50))
	var face: String = "happy" if mood >= 70 else ("neutral" if mood >= 40 else ("annoyed" if mood >= 20 else "sad"))
	var arousal: float = float(state.get("arousal", 0))
	var blush: int = 0
	if float(state.get("attitude", 0)) >= float(blueprint.get("thresholds", {}).get("touch", 100)):
		blush = 2 if arousal >= 60 else (1 if arousal >= 25 else 0)
	blush = mini(blush, maxi(0, int(blueprint.get("sprite", {}).get("blush_levels", 3)) - 1))
	var bases: Array = blueprint.get("sprite", {}).get("bases", [])
	return {"base": str(bases[0]) if not bases.is_empty() else "", "face": face, "blush": blush}
