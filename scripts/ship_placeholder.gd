extends RefCounted

static func create(color: Color, hostile: bool = false) -> Node3D:
	var ship: Node3D = Node3D.new()
	var hull: Color = color.darkened(0.42)
	_box(ship, Vector3(0.0, 0.12, 0.04), Vector3(0.38, 0.24, 0.92), hull)
	_box(ship, Vector3(0.0, 0.28, -0.08), Vector3(0.24, 0.16, 0.32), color.darkened(0.2))
	_box(ship, Vector3(0.0, 0.3, -0.27), Vector3(0.16, 0.07, 0.12), Color(0.25, 0.8, 1.0), true)
	_nose(ship, color, hostile)
	for side: int in [-1, 1]:
		_box(ship, Vector3(side * 0.32, 0.1, 0.17), Vector3(0.25, 0.12, 0.38), hull.darkened(0.15))
		_box(ship, Vector3(side * 0.24, 0.09, 0.5), Vector3(0.1, 0.1, 0.15), Color(0.15, 0.65, 1.0), true)
		_box(ship, Vector3(side * 0.28, 0.2, 0.04), Vector3(0.17, 0.07, 0.09), color)
	_box(ship, Vector3(0, 0.35, 0.14), Vector3(0.16, 0.08, 0.16), Color(0.45, 0.5, 0.57))
	_box(ship, Vector3(0, 0.36, -0.03), Vector3(0.04, 0.04, 0.25), Color(0.65, 0.7, 0.77))
	return ship


static func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color, glow: bool = false) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var view: MeshInstance3D = MeshInstance3D.new()
	view.position = position
	view.mesh = mesh
	view.material_override = _material(color, glow)
	parent.add_child(view)


static func _nose(parent: Node3D, color: Color, hostile: bool) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0
	mesh.bottom_radius = 0.23 if hostile else 0.2
	mesh.height = 0.42
	mesh.radial_segments = 4
	var nose: MeshInstance3D = MeshInstance3D.new()
	nose.mesh = mesh
	nose.position = Vector3(0, 0.12, -0.55)
	nose.rotation.x = -PI / 2.0
	nose.material_override = _material(color)
	parent.add_child(nose)


static func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	material.emission_enabled = glow
	if glow:
		material.emission = color
	return material
