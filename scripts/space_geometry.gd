extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")


static func star(system_id: String) -> Dictionary:
	for object: Dictionary in DataLoader.get_record(system_id).get("objects", []):
		if object.get("type") == "star":
			return object
	return {}


static func safe_target(origin: Vector2, target: Vector2, system_id: String) -> Vector2:
	var body: Dictionary = star(system_id)
	if body.is_empty():
		return target
	var centre: Vector2 = Motion.point(body["pos"])
	var radius: float = float(body["hazard"]["radius"]) + 24.0
	var offset: Vector2 = origin - centre
	if offset.length() < radius:
		return Motion.bounded(centre + offset.normalized() * (radius + 12.0)) if offset.length() > 0.1 else centre + Vector2(radius + 12.0, 0)
	if Geometry2D.get_closest_point_to_segment(centre, origin, target).distance_to(centre) >= radius - 8.0:
		return target
	var angle: float = offset.angle_to(target - centre)
	var direction: float = 1.0 if angle >= 0.0 else -1.0
	var step: float = maxf(0.28, acos(clampf(radius / offset.length(), 0.0, 1.0)) - 0.12)
	return centre + offset.normalized().rotated(direction * step) * radius


static func segment_exposure(origin: Vector2, target: Vector2, centre: Vector2, radius: float) -> float:
	var delta: Vector2 = target - origin
	if delta.length_squared() < 0.000001:
		return 1.0 if origin.distance_to(centre) < radius else 0.0
	var offset: Vector2 = origin - centre
	var b: float = 2.0 * offset.dot(delta)
	var a: float = delta.length_squared()
	var discriminant: float = b * b - 4.0 * a * (offset.length_squared() - radius * radius)
	if discriminant <= 0.0:
		return 0.0
	var low: float = clampf((-b - sqrt(discriminant)) / (2.0 * a), 0.0, 1.0)
	var high: float = clampf((-b + sqrt(discriminant)) / (2.0 * a), 0.0, 1.0)
	return maxf(0.0, high - low)
