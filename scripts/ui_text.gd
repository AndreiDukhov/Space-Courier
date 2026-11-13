extends RefCounted


static func get_text(text_id: String, values: Dictionary = {}) -> String:
	return str(DataLoader.get_record(text_id).get("text", "")).format(values)
