extends Node3D

signal finished
signal shot_started(shot: Dictionary)
signal explosion_created

const Math = preload("res://scripts/combat_math.gd")

var active: bool = false
var _generation: int = 0


func clear() -> void:
	_generation += 1
	active = false
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func play(shots: Array) -> void:
	_generation += 1
	var generation: int = _generation
	active = true
	for shot: Dictionary in shots:
		shot_started.emit(shot.duplicate(true))
		var origin: Vector3 = _position(shot["origin"])
		var target: Vector3 = _position(shot["target"])
		var hit: bool = shot["result"] != "miss"
		if not hit:
			var direction: Vector3 = (target - origin).normalized()
			target += Vector3(-direction.z, 0, direction.x) * 1.1 + direction * 0.9
		var color: Color = Color(0.2, 0.9, 1.0) if shot["shooter"] == "player" else Color(1.0, 0.35, 0.12)
		var beam: Node3D = _beam(origin, target, color)
		await get_tree().create_timer(0.18).timeout
		if generation != _generation:
			return
		if hit:
			_explosion(target, 0.75 if shot["result"] == "critical" else 1.0)
			if shot["result"] == "critical":
				await get_tree().create_timer(0.14).timeout
				if generation != _generation:
					return
				_explosion(target + Vector3(0.55, 0.06, 0.28), 0.9)
		await get_tree().create_timer(0.36).timeout
		if generation != _generation:
			return
		remove_child(beam)
		beam.queue_free()
	active = false
	finished.emit()


func _position(cell: Array) -> Vector3:
	return Math.world_position(cell) + Vector3(0, 0.33, 0)


func _beam(origin: Vector3, target: Vector3, color: Color) -> Node3D:
	var effect: Node3D = Node3D.new()
	effect.name = "ShotBeam"
	effect.position = origin
	add_child(effect)
	effect.look_at(target, Vector3.UP)
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = origin.distance_to(target)
	mesh.radial_segments = 6
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = _material(color)
	body.rotation.x = PI / 2.0
	body.position.z = -mesh.height / 2.0
	effect.add_child(body)
	effect.scale.z = 0.01
	var tween: Tween = create_tween().bind_node(effect)
	tween.tween_property(effect, "scale:z", 1.0, 0.15)
	tween.tween_property(body.material_override, "albedo_color:a", 0.0, 0.3)
	return effect


func _explosion(position: Vector3, size: float) -> void:
	var effect: MeshInstance3D = MeshInstance3D.new()
	effect.name = "ShotExplosion"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	sphere.radial_segments = 12
	sphere.rings = 6
	effect.mesh = sphere
	effect.position = position
	effect.material_override = _material(Color(1.0, 0.65, 0.12))
	effect.scale = Vector3.ONE * 0.15
	add_child(effect)
	explosion_created.emit()
	var tween: Tween = create_tween().bind_node(effect)
	tween.set_parallel(true)
	tween.tween_property(effect, "scale", Vector3.ONE * size * 2.8, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(effect.material_override, "albedo_color:a", 0.0, 0.32)
	tween.chain().tween_callback(effect.queue_free)


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	return material
