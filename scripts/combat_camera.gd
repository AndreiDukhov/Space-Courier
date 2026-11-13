extends Camera3D

const PAN_SPEED: float = 10.0
const EDGE_MARGIN: float = 18.0
const MIN_ZOOM: float = 7.0
const MAX_ZOOM: float = 40.0
const OFFSET: Vector3 = Vector3(0, 17, 13)
const Math = preload("res://scripts/combat_math.gd")

var _focus: Vector3 = Vector3.ZERO
var _dragging: bool = false
var _cursor: Vector2 = Vector2(-100, -100)
var _viewport_size: Vector2 = Vector2.ZERO
var _limits: Vector2 = Vector2(Math.WIDTH, Math.HEIGHT) / 2.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 18.0
	if not GameState.state.get("combat", {}).is_empty():
		var combat: Dictionary = GameState.state["combat"]
		_focus = (Math.world_position(combat["player"]["pos"]) + Math.world_position(combat["opponent"]["pos"])) * 0.5
		_focus.y = 0.0
	_sync()


func center_on_player() -> void:
	stop_tracking()
	if not GameState.state.get("combat", {}).is_empty():
		_focus = Math.world_position(GameState.state["combat"]["player"]["pos"])
		_focus.y = 0.0
	_sync()


func configure(viewport_size: Vector2, limits: Vector2) -> void:
	_viewport_size = viewport_size
	_limits = limits
	_sync()


func _process(delta: float) -> void:
	if _dragging or not Rect2(Vector2.ZERO, _viewport_size).has_point(_cursor):
		return
	var direction: Vector2 = Vector2.ZERO
	if _cursor.x < EDGE_MARGIN:
		direction.x = -1
	elif _cursor.x > _viewport_size.x - EDGE_MARGIN:
		direction.x = 1
	if _cursor.y < EDGE_MARGIN:
		direction.y = -1
	elif _cursor.y > _viewport_size.y - EDGE_MARGIN:
		direction.y = 1
	pan(direction * PAN_SPEED * delta * size / 13.0)


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		_cursor = event.position
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			size = clampf(size * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12), MIN_ZOOM, MAX_ZOOM)
			return true
	elif event is InputEventMouseMotion:
		_cursor = event.position
		if _dragging:
			var units: float = size / maxf(1.0, _viewport_size.y)
			pan(Vector2(-event.relative.x, -event.relative.y / sin(atan2(OFFSET.y, OFFSET.z))) * units)
			return true
	return false


func pan(amount: Vector2) -> void:
	_focus.x = clampf(_focus.x + amount.x, -_limits.x, _limits.x)
	_focus.z = clampf(_focus.z + amount.y, -_limits.y, _limits.y)
	_sync()


func stop_tracking() -> void:
	_dragging = false
	_cursor = Vector2(-100, -100)


func pointer_position() -> Vector2:
	return _cursor


func _sync() -> void:
	position = _focus + OFFSET
	look_at(_focus, Vector3.UP)
