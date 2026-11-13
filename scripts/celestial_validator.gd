extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Rules = preload("res://scripts/order_rules.gd")


static func validate(system: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var objects: Variant = system.get("objects")
	if not objects is Array:
		return errors
	var stars: int = 0
	var planets: int = 0
	var distances: Array[float] = []
	for object: Variant in objects:
		if not object is Dictionary or object.get("type") not in ["planet", "star", "station"]:
			continue
		if not Rules.finite_number(object.get("radius")) or float(object["radius"]) <= 0.0:
			errors.append("Celestial radius must be a positive finite number")
		if not object.get("color") is String or not Color.html_is_valid(str(object["color"])):
			errors.append("Celestial color must be a valid HTML color")
		var position: Variant = object.get("pos")
		if not position is Array or position.size() != 2 or not Rules.finite_number(position[0]) or not Rules.finite_number(position[1]):
			continue
		var point: Vector2 = Motion.point(position)
		if Motion.bounded(point) != point:
			errors.append("Celestial position must stay inside the system")
		if object["type"] == "star":
			stars += 1
			if point != Motion.BOUNDS / 2.0:
				errors.append("The system star must be at its centre")
		elif object["type"] == "planet":
			planets += 1
			var distance: float = point.distance_to(Motion.BOUNDS / 2.0)
			if distance <= 0.0:
				errors.append("Planets must be outside the star centre")
			for previous: float in distances:
				if is_equal_approx(previous, distance):
					errors.append("Planets require different orbital distances")
			distances.append(distance)
	if stars != 1:
		errors.append("Each system requires exactly one central star")
	if planets < 2:
		errors.append("Each system requires at least two planets")
	return errors
