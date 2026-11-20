extends RefCounted

const Text = preload("res://scripts/ui_text.gd")


static func icon_kind(module: Dictionary) -> String:
	return str(module.get("mount", {"engine": "burn", "maneuver_engine": "movement"}.get(str(module.get("slot")), module.get("slot", "turret"))))


static func stats(module: Dictionary) -> String:
	match module.get("slot"):
		"weapon": return Text.get_text("ui_parts_weapon_stats", {"min": int(module["dmg"][0]), "max": int(module["dmg"][1]), "arc": int(module["arc_degrees"]), "range": int(module["range"])})
		"engine": return Text.get_text("ui_parts_engine_stats", {"speed": int(module["speed"]), "thrust": int(module["thrust"])})
		"maneuver_engine": return Text.get_text("ui_parts_maneuver_stats", {"value": int(module["maneuver_level"])})
		"armor": return Text.get_text("ui_parts_armor_stats", {"value": int(module["hull_bonus"])})
		"shield": return Text.get_text("ui_parts_shield_stats", {"value": int(module["shield"])})
		"fuel_tank": return Text.get_text("ui_parts_tank_stats", {"value": int(module["fuel_bonus"])})
	return ""
