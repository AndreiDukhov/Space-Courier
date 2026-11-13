extends RefCounted

var _textures: Dictionary = {}


func background_for(location: Dictionary, slot: String) -> Texture2D:
	var backgrounds: Dictionary = location.get("backgrounds", {})
	var variant: String = "night" if slot == "night" else "day"
	var path: String = str(backgrounds.get(variant, backgrounds.get("day", "")))
	if path.is_empty():
		return null
	if not path.begins_with("res://"):
		path = "res://" + path
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]
