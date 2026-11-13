extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Geometry = preload("res://scripts/space_geometry.gd")


static func toward(origin: Vector2, target: Vector2, system_id: String, speed: float, delta: float) -> Vector2:
	return Motion.advance(origin, Geometry.safe_target(origin, target, system_id), speed, delta)


static func advance(position: Vector2, waypoint: int, points: Array, speed: float, delta: float) -> Dictionary:
	var budget: float = speed * delta
	var loop_length: float = 0.0
	for i: int in range(points.size()):
		loop_length += Motion.point(points[i]).distance_to(Motion.point(points[(i + 1) % points.size()]))
	var target: Vector2 = Motion.point(points[waypoint])
	var initial_distance: float = position.distance_to(target)
	if budget >= initial_distance:
		budget -= initial_distance
		position = target
		waypoint = (waypoint + 1) % points.size()
		if loop_length > 0.0:
			budget = fmod(budget, loop_length)
	for _segment: int in range(points.size() + 1):
		target = Motion.point(points[waypoint])
		var distance: float = position.distance_to(target)
		if distance > budget:
			position = position.move_toward(target, budget)
			break
		position = target
		budget -= distance
		waypoint = (waypoint + 1) % points.size()
		if budget <= 0.0:
			break
	return {"pos": Motion.coordinates(position), "waypoint": waypoint}
