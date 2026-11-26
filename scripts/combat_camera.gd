extends Camera3D

const MIN_ZOOM: float = 7.0
const MAX_ZOOM: float = 40.0
const OFFSET: Vector3 = Vector3(0, 17, 13)
const Math = preload("res://scripts/combat_math.gd")

var target: Node3D
var _cursor: Vector2 = Vector2(-100, -100)
var _focus: Vector3 = Vector3.ZERO
var _limits: Vector2 = Vector2(30, 30)
var _viewport_size: Vector2 = Vector2(1280, 800)
var _dragging: bool = false


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 24.0
	RenderingServer.frame_pre_draw.connect(_follow)
	_follow()


func center_on_player() -> void:
	stop_tracking()
	_focus = target.global_position if is_instance_valid(target) else Math.world_position(GameState.state["combat"]["player"]["pos"])
	_focus.y = 0.0
	_follow()


func configure(viewport_size: Vector2, limits: Vector2) -> void:
	_viewport_size = viewport_size
	_limits = limits
	_follow()


func _process(delta: float) -> void:
	if not _dragging and Rect2(Vector2.ZERO, _viewport_size).has_point(_cursor):
		var direction: Vector2 = Vector2.ZERO
		if _cursor.x < 18: direction.x = -1
		elif _cursor.x > _viewport_size.x - 18: direction.x = 1
		if _cursor.y < 18: direction.y = -1
		elif _cursor.y > _viewport_size.y - 18: direction.y = 1
		_focus += Vector3(direction.x, 0, direction.y) * size * delta * 0.8
	_follow()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		_cursor = event.position
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			size = clampf(size * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12), MIN_ZOOM, MAX_ZOOM)
			return true
	elif event is InputEventMouseMotion:
		_cursor = event.position
		if _dragging:
			_focus -= Vector3(event.relative.x, 0, event.relative.y * 1.5) * size / maxf(1, _viewport_size.y)
			_follow()
			return true
	return false


func stop_tracking() -> void:
	_cursor = Vector2(-100, -100)
	_dragging = false


func pointer_position() -> Vector2:
	return _cursor


func _follow() -> void:
	if not is_inside_tree():
		return
	_focus.x = clampf(_focus.x, -_limits.x, _limits.x)
	_focus.z = clampf(_focus.z, -_limits.y, _limits.y)
	global_position = _focus + OFFSET
	look_at(_focus, Vector3.UP)
