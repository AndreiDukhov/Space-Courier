extends RefCounted


static func heroine(scene: Dictionary) -> String:
	for line: Dictionary in scene.get("lines", []):
		var speaker: String = str(line.get("who", ""))
		if DataLoader.record_sources.has("heroines/" + speaker):
			return speaker
	return ""


static func find_for(heroine_id: String, tag: String) -> String:
	for scene: Dictionary in DataLoader.get_records("scenes"):
		if tag in scene.get("tags", []) and heroine(scene) == heroine_id:
			return str(scene["id"])
	return ""


static func valid_save(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Array[String] = []
	for scene_id: Variant in value:
		if not scene_id is String or not DataLoader.record_sources.has("scenes/" + scene_id) or scene_id in seen:
			return false
		seen.append(scene_id)
	return true
