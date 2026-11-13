extends RefCounted

const MAP_SCALE: int = 3
const BOUNDS: Vector2 = Vector2(1000, 760) * MAP_SCALE
const SPAWN: Vector2 = Vector2(500, 650) * MAP_SCALE
const PLAYER_SPEED: float = 150.0
const BOOST_SPEED_MULTIPLIER: float = 2.0
const BOOST_FUEL_MULTIPLIER: float = 1.5
const LOCAL_FUEL_PER_DISTANCE: float = 1.0 / (PLAYER_SPEED * 60.0)
const INTERACTION_RADIUS: float = 48.0
const WORLD_SCALE: float = 0.05


static func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func coordinates(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func bounded(value: Vector2) -> Vector2:
	return value.clamp(Vector2.ZERO, BOUNDS)


static func advance(origin: Vector2, target: Vector2, speed: float, delta: float) -> Vector2:
	return origin.move_toward(bounded(target), maxf(0.0, speed) * maxf(0.0, delta))


static func world_position(value: Array, height: float = 0.0) -> Vector3:
	var planar: Vector2 = (point(value) - BOUNDS / 2.0) * WORLD_SCALE
	return Vector3(planar.x, height, planar.y)


static func data_position(value: Vector3) -> Vector2:
	return bounded(Vector2(value.x, value.z) / WORLD_SCALE + BOUNDS / 2.0)
