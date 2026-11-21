extends RefCounted

const G = preload("res://scripts/model_geometry.gd")
const SHIELD_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float grid = max(step(0.94, cos(UV.x * 75.398)), step(0.96, cos(UV.y * 50.265)));
	ALBEDO = mix(vec3(0.08, 0.4, 0.95), vec3(0.45, 0.95, 1.0), rim);
	ALPHA = (0.045 + rim * 0.72 + grid * 0.16) * opacity;
}
"""
static var _shield_shader: Shader


static func burst(parent: Node3D, point: Vector3, color: Color, size: float = 1.0, label: String = "Explosion") -> Node3D:
	var root: Node3D = _root(parent, point, label)
	var core: MeshInstance3D = _sphere(root, "Core", Color(1.0, 0.94, 0.72, 0.95))
	_expand(core, 0.08, size * 0.60, 0.22)
	var fire: MeshInstance3D = _sphere(root, "Fire", Color(color, 0.7))
	_expand(fire, 0.15, size * 1.2, 0.42)
	_ring(root, Color(color, 0.6), size * 2.2, 0.55)
	_sparks(root, color, size, 8)
	_finish(root, 0.75)
	return root


static func shield(parent: Node3D, point: Vector3, size: float = 1.0) -> Node3D:
	var root: Node3D = _root(parent, point, "ShieldImpact")
	var shell: MeshInstance3D = _sphere(root, "ShieldShell", Color(0.12, 0.65, 1.0, 0.20))
	if _shield_shader == null:
		_shield_shader = Shader.new()
		_shield_shader.code = SHIELD_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _shield_shader
	material.set_shader_parameter("opacity", 1.0)
	shell.material_override = material
	shell.scale = Vector3.ONE * size * 0.7
	var tween: Tween = shell.create_tween().bind_node(shell)
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * size * 1.3, 0.45)
	tween.tween_method(func(opacity: float) -> void: material.set_shader_parameter("opacity", opacity), 1.0, 0.0, 0.45)
	_ring(root, Color(0.3, 0.85, 1.0, 0.8), size * 1.6, 0.45)
	_sparks(root, Color(0.35, 0.85, 1.0), size * 0.5, 5)
	_finish(root, 0.65)
	return root


static func muzzle(parent: Node3D, point: Vector3, color: Color) -> Node3D:
	var root: Node3D = _root(parent, point, "MuzzleFlash")
	var core: MeshInstance3D = _sphere(root, "Core", Color(0.8, 0.95, 1.0, 0.95))
	_expand(core, 0.16, 0.45, 0.14)
	_ring(root, Color(color, 0.6), 0.7, 0.20)
	_finish(root, 0.24)
	return root


static func ripple(parent: Node3D, point: Vector3, color: Color, size: float = 2.0) -> Node3D:
	var root: Node3D = _root(parent, point, "TransitRipple")
	_ring(root, Color(color, 0.8), size, 0.65)
	var inner: MeshInstance3D = _sphere(root, "TransitGlow", Color(color, 0.2))
	_expand(inner, 0.12, size * 0.5, 0.5)
	_finish(root, 0.75)
	return root


static func _root(parent: Node3D, point: Vector3, label: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = label
	root.position = point
	parent.add_child(root)
	return root


static func _sphere(parent: Node3D, label: String, color: Color) -> MeshInstance3D:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var view: MeshInstance3D = G.part(parent, label, sphere, Vector3.ZERO, color, true)
	view.material_override = view.material_override.duplicate()
	return view


static func _expand(view: MeshInstance3D, start: float, end: float, duration: float) -> void:
	view.scale = Vector3.ONE * start
	var tween: Tween = view.create_tween().bind_node(view)
	tween.set_parallel(true)
	tween.tween_property(view, "scale", Vector3.ONE * end, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(view.material_override, "albedo_color:a", 0.0, duration)


static func _ring(parent: Node3D, color: Color, size: float, duration: float) -> void:
	var ring: MeshInstance3D = G.ring(parent, "Shockwave", Vector3(0, 0.03, 0), 0.5, 0.04, color, true)
	ring.material_override = ring.material_override.duplicate()
	_expand(ring, 0.1, size, duration)


static func _sparks(parent: Node3D, color: Color, size: float, count: int) -> void:
	for index: int in range(count):
		var angle: float = TAU * float(index) / count + 0.3
		var direction: Vector3 = Vector3(cos(angle), 0.14 + (index % 3) * 0.13, sin(angle))
		var spark: MeshInstance3D = G.box(parent, "Spark", Vector3.ZERO, Vector3(0.055, 0.055, 0.18) * size, Color(color, 0.9), true)
		spark.material_override = spark.material_override.duplicate()
		spark.rotation.y = -angle + PI / 2
		var tween: Tween = spark.create_tween().bind_node(spark)
		tween.set_parallel(true)
		tween.tween_property(spark, "position", direction * size * (0.6 + (index % 3) * 0.15), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark.material_override, "albedo_color:a", 0.0, 0.55)
		tween.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.55)


static func _finish(root: Node3D, duration: float) -> void:
	var tween: Tween = root.create_tween().bind_node(root)
	tween.tween_interval(duration)
	tween.tween_callback(root.queue_free)
