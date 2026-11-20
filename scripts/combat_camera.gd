extends Camera3D

const MIN_ZOOM: float = 7.0
const MAX_ZOOM: float = 40.0
const OFFSET: Vector3 = Vector3(0, 17, 13)
const Math = preload("res://scripts/combat_math.gd")

var target: Node3D
var _cursor: Vector2 = Vector2(-100, -100)


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 24.0
	RenderingServer.frame_pre_draw.connect(_follow)
	_follow()


func center_on_player() -> void:
	stop_tracking()
	_follow()


func configure(_viewport_size: Vector2, _limits: Vector2) -> void:
	_follow()


func _process(_delta: float) -> void:
	_follow()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		_cursor = event.position
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			size = clampf(size * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12), MIN_ZOOM, MAX_ZOOM)
			return true
	elif event is InputEventMouseMotion:
		_cursor = event.position
	return false


func stop_tracking() -> void:
	_cursor = Vector2(-100, -100)


func pointer_position() -> Vector2:
	return _cursor


func _follow() -> void:
	if not is_inside_tree():
		return
	var focus: Vector3 = Vector3.ZERO
	if is_instance_valid(target) and target.is_inside_tree():
		focus = target.global_position
	elif not GameState.state.get("combat", {}).is_empty():
		focus = Math.world_position(GameState.state["combat"]["player"]["pos"])
	focus.y = 0.0
	global_position = focus + OFFSET
	look_at(focus, Vector3.UP)
