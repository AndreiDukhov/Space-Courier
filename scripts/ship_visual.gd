extends Node3D

const Geometry = preload("res://scripts/model_geometry.gd")
const EngineAudio = preload("res://scripts/ship_audio.gd")
const TRAIL_LIFETIME: float = 0.5
const MAX_TRAIL_POINTS: int = 22

var role: String = "player"
var variant: int = 0
var animation_enabled: bool = true
var _throttle: float = 0.0
var _requested_throttle: float = 0.0
var _boost: bool = false
var _phase: float = 0.0
var _trail: MeshInstance3D
var _trail_material: StandardMaterial3D
var _points: Array[Dictionary] = []
var _last_position: Vector3
var _trail_clock: float = 0.0
var _hull_ratio: float = 1.0


func _ready() -> void:
	_trail = MeshInstance3D.new()
	_trail.name = "EngineTrail"
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY
	_trail_material = Geometry.material(Color(0.18, 0.75, 1.0, 0.45), true).duplicate()
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.albedo_color = Color.WHITE
	_last_position = global_position
	var engine_audio: EngineAudio = EngineAudio.new()
	engine_audio.name = "EngineAudio"
	add_child(engine_audio)


func set_motion(moving: bool, boosting: bool = false) -> void:
	_requested_throttle = 1.0 if moving else 0.0
	_boost = boosting and moving


func set_damage(ratio: float) -> void:
	_hull_ratio = clampf(ratio, 0.0, 1.0)


func clear_trail() -> void:
	_points.clear()
	if _trail != null:
		_trail.hide()
	if is_inside_tree():
		_last_position = global_position


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		clear_trail()
		return
	if not animation_enabled:
		_last_position = global_position
		return
	_phase += delta
	_throttle = move_toward(_throttle, _requested_throttle, delta * 7.0)
	for engine: Node3D in get_node("Thrusters").get_children():
		var plume: MeshInstance3D = engine.get_node("Plume")
		var length: float = (0.10 + _throttle * (0.95 if not _boost else 2.5)) * (0.92 + 0.08 * sin(_phase * 31.0 + engine.get_index()))
		plume.scale = Vector3(1.3 if _boost else 1.0, length, 1.3 if _boost else 1.0)
		plume.position.z = 0.04 + length * 0.22
	for light: MeshInstance3D in get_node("Beacons").get_children():
		light.visible = fmod(_phase * (3.5 if role == "patrol" else 0.8) + light.get_index() * 0.5, 1.0) < 0.7
	_update_trail(delta)


func _update_trail(delta: float) -> void:
	_trail_clock += delta
	for point: Dictionary in _points:
		point["age"] += delta
	_points = _points.filter(func(point: Dictionary) -> bool: return point["age"] < TRAIL_LIFETIME)
	var distance: float = global_position.distance_to(_last_position)
	if distance > 5.0:
		clear_trail()
	elif distance > 0.015 and _trail_clock > 0.025 and _requested_throttle > 0.0:
		_points.push_front({"pos": global_position + global_basis.z * 0.65, "side": global_basis.x.normalized(), "age": 0.0})
		if _points.size() > MAX_TRAIL_POINTS:
			_points.pop_back()
		_trail_clock = 0.0
	_last_position = global_position
	_trail.visible = _points.size() > 1
	if not _trail.visible:
		return
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _trail_material)
	var colour: Color = Color(0.2, 0.85, 1.0) if _hull_ratio > 0.3 else Color(1.0, 0.42, 0.12)
	for index: int in range(1, _points.size()):
		var a: Dictionary = _points[index - 1]
		var b: Dictionary = _points[index]
		for side: float in [-0.22, 0.22]:
			var width: float = 0.07 if _boost else 0.035
			var start: Vector3 = a["pos"] + a["side"] * side
			var end: Vector3 = b["pos"] + b["side"] * side
			for corner: Array in [[start - a["side"] * width, a["age"]], [start + a["side"] * width, a["age"]], [end + b["side"] * width, b["age"]], [start - a["side"] * width, a["age"]], [end + b["side"] * width, b["age"]], [end - b["side"] * width, b["age"]]]:
				mesh.surface_set_color(Color(colour, (1.0 - float(corner[1]) / TRAIL_LIFETIME) * (0.55 if _boost else 0.27)))
				mesh.surface_add_vertex(corner[0])
	mesh.surface_end()
	_trail.mesh = mesh
