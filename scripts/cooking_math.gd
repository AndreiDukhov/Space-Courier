extends RefCounted


static func quality(skill: int) -> int:
	return mini(3, 1 + floori(skill / 5.0))


static func taste(tags: Array, preferences: Dictionary) -> float:
	for tag: String in tags:
		if tag in preferences.get("dislikes", []):
			return -1.0
	for tag: String in tags:
		if tag in preferences.get("likes", []):
			return 1.5
	return 1.0


static func gain(base: float, dish_quality: int, taste_multiplier: float) -> float:
	return base * (1.0 + 0.25 * (dish_quality - 1)) * taste_multiplier
