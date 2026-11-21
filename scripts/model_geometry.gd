extends RefCounted

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key: String = color.to_html() + str(glow)
	if not _materials.has(key):
		var result: StandardMaterial3D = StandardMaterial3D.new()
		result.albedo_color = color
		result.metallic = 0.48 if not glow else 0.0
		result.roughness = 0.46
		if glow:
			result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			result.emission_enabled = true
			result.emission = color
		if color.a < 1.0:
			result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			result.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = result
	return _materials[key]


static func part(parent: Node3D, label: String, mesh: Mesh, position: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = label
	view.mesh = mesh
	view.position = position
	view.material_override = material(color, glow)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view, true)
	return view


static func box(parent: Node3D, label: String, position: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var key: String = "box" + str(size)
	if not _meshes.has(key):
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return part(parent, label, _meshes[key], position, color, glow)


static func cylinder(parent: Node3D, label: String, position: Vector3, radius: float, height: float, color: Color, top: float = -1.0, glow: bool = false, segments: int = 12) -> MeshInstance3D:
	var key: String = "cylinder%s/%s/%s/%s" % [radius, height, top, segments]
	if not _meshes.has(key):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = radius if top < 0.0 else top
		mesh.height = height
		mesh.radial_segments = segments
		_meshes[key] = mesh
	return part(parent, label, _meshes[key], position, color, glow)


static func ring(parent: Node3D, label: String, position: Vector3, radius: float, thickness: float, color: Color, glow: bool = false) -> MeshInstance3D:
	var key: String = "ring%s/%s" % [radius, thickness]
	if not _meshes.has(key):
		var mesh: TorusMesh = TorusMesh.new()
		mesh.inner_radius = radius - thickness
		mesh.outer_radius = radius + thickness
		mesh.rings = 32
		mesh.ring_segments = 8
		_meshes[key] = mesh
	return part(parent, label, _meshes[key], position, color, glow)


static func hull(parent: Node3D, label: String, outline: PackedVector2Array, height: float, color: Color) -> MeshInstance3D:
	var key: String = "hull%s/%s" % [hash(outline), height]
	if not _meshes.has(key):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
		for index: int in range(0, indices.size(), 3):
			_triangle(surface, _point(outline[indices[index]] * 0.78, height), _point(outline[indices[index + 1]] * 0.78, height), _point(outline[indices[index + 2]] * 0.78, height), Vector3.UP)
			_triangle(surface, _point(outline[indices[index]], 0), _point(outline[indices[index + 1]], 0), _point(outline[indices[index + 2]], 0), Vector3.DOWN)
		for index: int in range(outline.size()):
			var a: Vector2 = outline[index]
			var b: Vector2 = outline[(index + 1) % outline.size()]
			var normal: Vector3 = Vector3((a + b).x, 0, (a + b).y).normalized()
			var low_a: Vector3 = _point(a, 0.0)
			var low_b: Vector3 = _point(b, 0.0)
			var high_a: Vector3 = _point(a * 0.78, height)
			var high_b: Vector3 = _point(b * 0.78, height)
			_triangle(surface, low_a, low_b, high_b, normal)
			_triangle(surface, low_a, high_b, high_a, normal)
		_meshes[key] = surface.commit()
	return part(parent, label, _meshes[key], Vector3.ZERO, color)


static func _point(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x, height, point.y)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.dot(outward) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		normal = -normal
	surface.set_normal(normal)
	# Godot uses clockwise front faces.
	for point: Vector3 in [a, c, b]:
		surface.add_vertex(point)
