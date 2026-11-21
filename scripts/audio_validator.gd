extends RefCounted

const REQUIRED: Array[String] = ["sfx_laser", "sfx_autocannon", "sfx_plasma", "sfx_impact", "sfx_explosion", "sfx_shield_hit", "sfx_shield_recharge", "sfx_engine_idle", "sfx_engine_cruise", "sfx_engine_boost", "sfx_jump_depart", "sfx_jump_arrive", "sfx_ui_click", "sfx_ui_confirm", "sfx_ui_cancel", "sfx_door_open", "sfx_knock", "sfx_takeoff", "sfx_landing", "sfx_heat", "music_hub", "music_space", "music_danger"]


static func validate(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if record.size() != 6 or not record.has_all(["id", "files", "volume_db", "pitch", "loop", "spatial"]):
		return ["Audio requires id, files, volume_db, pitch, loop and spatial"]
	if not record["files"] is Array or record["files"].is_empty():
		errors.append("Audio files must be a nonempty array")
	else:
		var seen: Array[String] = []
		for path: Variant in record["files"]:
			if not path is String or not path.begins_with("res://audio/") or path.get_extension().to_lower() != "wav" or not ResourceLoader.exists(path, "AudioStreamWAV"):
				errors.append("Audio file must reference an existing project WAV")
			elif path in seen:
				errors.append("Audio variants must be unique")
			else:
				seen.append(path)
	if not _number(record["volume_db"]) or float(record["volume_db"]) < -60 or float(record["volume_db"]) > 0:
		errors.append("Audio volume_db must be between -60 and 0")
	var pitch: Variant = record["pitch"]
	if not pitch is Array or pitch.size() != 2:
		errors.append("Audio pitch requires a minimum and maximum")
	elif not _number(pitch[0]) or not _number(pitch[1]) or float(pitch[0]) < 0.5 or float(pitch[1]) > 2.0 or float(pitch[0]) > float(pitch[1]):
		errors.append("Audio pitch must be an ordered range between 0.5 and 2")
	if not record["loop"] is bool or not record["spatial"] is bool:
		errors.append("Audio loop and spatial must be booleans")
	return errors


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
