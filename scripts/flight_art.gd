extends RefCounted

const Motion = preload("res://scripts/flight_motion.gd")
const ShipModel = preload("res://scripts/ship_placeholder.gd")


static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.8
	if glow:
		result.emission_enabled = true
		result.emission = color
	return result


static func ship(color: Color) -> Node3D:
	var result: Node3D = ShipModel.create(color)
	result.rotation.y = PI
	return result


static func system_object(object: Dictionary) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	match object["type"]:
		"planet", "star":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = float(object["radius"])
			sphere.height = sphere.radius * 2.0
			result.mesh = sphere
			var color: Color = Color(str(object["color"]))
			result.material_override = material(color, object["type"] == "star")
			if object["type"] == "star":
				var light: OmniLight3D = OmniLight3D.new()
				light.light_color = color
				light.light_energy = 1.8
				light.omni_range = 40.0
				result.add_child(light)
		"gate":
			var ring: TorusMesh = TorusMesh.new()
			ring.inner_radius = 0.8
			ring.outer_radius = 1.5
			result.mesh = ring
			result.material_override = material(Color(0.65, 0.3, 0.95), true)
		"event_marker":
			var cube: BoxMesh = BoxMesh.new()
			cube.size = Vector3(0.8, 0.8, 0.8)
			result.mesh = cube
			result.material_override = material(Color(1.0, 0.7, 0.2), true)
		"station":
			var station: BoxMesh = BoxMesh.new()
			station.size = Vector3.ONE * float(object["radius"]) * 2.0
			result.mesh = station
			result.material_override = material(Color(str(object["color"])))
	result.position = Motion.world_position(object["pos"], 0.3)
	return result


static func label(text: String, position: Vector3) -> Label3D:
	var result: Label3D = Label3D.new()
	result.text = text
	result.position = position + Vector3(0, 1.8, 0)
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	result.font_size = 36
	result.pixel_size = 0.025
	result.no_depth_test = true
	return result


static func grid() -> MeshInstance3D:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material(Color(0.08, 0.16, 0.24), true))
	var half: Vector2 = Motion.BOUNDS * Motion.WORLD_SCALE / 2.0
	for x: int in range(-ceili(half.x), ceili(half.x) + 1, 5):
		mesh.surface_add_vertex(Vector3(x, -0.1, -half.y))
		mesh.surface_add_vertex(Vector3(x, -0.1, half.y))
	for z: int in range(-ceili(half.y), ceili(half.y) + 1, 5):
		mesh.surface_add_vertex(Vector3(-half.x, -0.1, z))
		mesh.surface_add_vertex(Vector3(half.x, -0.1, z))
	mesh.surface_end()
	var result: MeshInstance3D = MeshInstance3D.new()
	result.mesh = mesh
	return result


static func orbit(radius: float) -> MeshInstance3D:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material(Color(0.12, 0.21, 0.29), true))
	for step: int in range(97):
		var angle: float = TAU * float(step) / 96.0
		mesh.surface_add_vertex(Vector3(cos(angle) * radius, -0.15, sin(angle) * radius))
	mesh.surface_end()
	var result: MeshInstance3D = MeshInstance3D.new()
	result.mesh = mesh
	return result


static func zone(radius: float, color: Color) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = maxf(0.01, radius - 0.06)
	ring.outer_radius = radius + 0.06
	result.mesh = ring
	result.material_override = material(color, true)
	return result
