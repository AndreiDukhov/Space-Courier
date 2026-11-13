extends RefCounted

const Numbers = preload("res://scripts/order_rules.gd")


static func validate_sprite(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not record.has("sprite"):
		return errors
	var sprite: Variant = record["sprite"]
	if not sprite is Dictionary:
		return ["Sprite layers must be an object"]
	for field: String in ["bases", "faces"]:
		if not sprite.get(field) is Array or sprite[field].is_empty():
			errors.append("Sprite layers require a nonempty " + field + " array")
			continue
		for value: Variant in sprite[field]:
			if not value is String or value.is_empty():
				errors.append("Sprite layer ids must be nonempty strings")
	if not Numbers.whole_number(sprite.get("blush_levels")) or float(sprite.get("blush_levels", 0)) < 1:
		errors.append("Sprite blush_levels must be a positive integer")
	return errors


static func validate_links(groups: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var heroes: Dictionary = {}
	for heroine: Dictionary in groups.get("heroines", []):
		heroes[str(heroine["id"])] = heroine
	var counts: Dictionary = {}
	for scene: Dictionary in groups.get("scenes", []):
		for tag: String in ["disclosure", "reconciliation"]:
			if tag not in scene.get("tags", []):
				continue
			var owner: String = ""
			for line: Dictionary in scene.get("lines", []):
				if heroes.has(line.get("who", "")):
					owner = str(line["who"])
					break
			if owner.is_empty():
				errors.append(str(scene["id"]) + ": relationship scene requires a heroine speaker")
				continue
			var key: String = owner + "/" + tag
			counts[key] = int(counts.get(key, 0)) + 1
			if counts[key] > 1:
				errors.append(key + ": relationship scene must be unique")
	for heroine_id: String in heroes:
		if heroes[heroine_id].get("polygamy") != "forbids":
			continue
		for tag: String in ["disclosure", "reconciliation"]:
			if not counts.has(heroine_id + "/" + tag):
				errors.append(heroine_id + ": missing " + tag + " scene")
	return errors
