extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const Galaxy = preload("res://scripts/galaxy_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const ENTRY_MARGIN: float = Motion.INTERACTION_RADIUS * 2.0
const LAUNCH_CLEARANCE: float = Motion.INTERACTION_RADIUS * 0.5
const GATE_CLEARANCE: float = Motion.INTERACTION_RADIUS * 0.8


static func hub_departure() -> Vector2:
	var earth: Dictionary = Conditions.space_object(Galaxy.HUB_PLANET, Galaxy.INITIAL_SYSTEM)
	var center: Vector2 = Motion.point(earth["pos"])
	var direction: Vector2 = (Motion.BOUNDS * 0.5 - center).normalized()
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var distance: float = float(earth["radius"]) / Motion.WORLD_SCALE + LAUNCH_CLEARANCE
	return Motion.bounded(center + direction * distance)


static func arrival(source_id: String, destination_id: String) -> Vector2:
	for object: Dictionary in DataLoader.get_record(destination_id).get("objects", []):
		if object.get("type") != "gate":
			continue
		var route: Dictionary = DataLoader.get_record(str(object.get("to_route", "")))
		if route.get("from") == destination_id and route.get("to") == source_id:
			var centre: Vector2 = Motion.point(object["pos"])
			var inward: Vector2 = (Motion.BOUNDS * 0.5 - centre).normalized()
			return Motion.bounded(centre + (Vector2.DOWN if inward.is_zero_approx() else inward) * GATE_CLEARANCE)
	var source: Vector2 = Motion.point(DataLoader.get_record(source_id)["map_pos"])
	var destination: Vector2 = Motion.point(DataLoader.get_record(destination_id)["map_pos"])
	var direction: Vector2 = (source - destination).normalized()
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var half: Vector2 = Motion.BOUNDS * 0.5 - Vector2.ONE * ENTRY_MARGIN
	var distance: float = minf(half.x / maxf(absf(direction.x), 0.00001), half.y / maxf(absf(direction.y), 0.00001))
	return Motion.bounded(Motion.BOUNDS * 0.5 + direction * distance)
