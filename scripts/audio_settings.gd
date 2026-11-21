extends RefCounted

const FIELDS: Array[String] = ["effects_volume", "music_volume"]


static func initial() -> Dictionary:
	return {"effects_volume": 1.0, "music_volume": 1.0}


static func migrate(save: Dictionary) -> Dictionary:
	if save.has("settings"):
		return save
	var result: Dictionary = save.duplicate(true)
	result["settings"] = initial()
	return result


static func valid(settings: Variant) -> bool:
	if not settings is Dictionary or settings.size() != FIELDS.size() or not settings.has_all(FIELDS):
		return false
	for field: String in FIELDS:
		var value: Variant = settings[field]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
			return false
	return true
