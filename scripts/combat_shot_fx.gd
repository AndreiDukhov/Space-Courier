extends Node3D

signal finished
signal shot_started(shot: Dictionary)
signal explosion_created

const Roster = preload("res://scripts/combat_roster.gd")
const Math = preload("res://scripts/combat_math.gd")
const FX = preload("res://scripts/impact_fx.gd")

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
		var mount: String = str(DataLoader.get_record(str(shot["weapon"])).get("mount", "turret"))
		var color: Color = Color(1.0, 0.72, 0.2) if mount == "course" else Color(0.85, 0.3, 1.0) if mount == "broadside" else Color(0.2, 0.9, 1.0)
		if not Roster.friendly(str(shot["shooter"])):
			color = color.lerp(Color(1.0, 0.22, 0.10), 0.35)
		var beam: Node3D = _beam(origin, target, color)
		SoundSystem.play_at("sfx_autocannon" if mount == "course" else "sfx_plasma" if mount == "broadside" else "sfx_laser", origin, self)
		FX.muzzle(self, origin, color)
		await get_tree().create_timer(0.18).timeout
		if generation != _generation:
			return
		if hit:
			var target_id: String = Roster.target_at(str(shot["shooter"]), Math.cell(shot["target"]))
			if float(Roster.actor(target_id).get("shield", 0)) > 0.0:
				FX.shield(self, target, 1.1)
				SoundSystem.play_at("sfx_shield_hit", target, self)
			else:
				SoundSystem.play_at("sfx_impact", target, self)
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
	var halo: MeshInstance3D = MeshInstance3D.new()
	var halo_mesh: CylinderMesh = mesh.duplicate()
	halo_mesh.top_radius = 0.085
	halo_mesh.bottom_radius = 0.085
	halo.mesh = halo_mesh
	halo.material_override = _material(Color(color, 0.22))
	halo.rotation.x = body.rotation.x
	halo.position = body.position
	effect.add_child(halo)
	effect.scale.z = 0.01
	var tween: Tween = create_tween().bind_node(effect)
	tween.tween_property(effect, "scale:z", 1.0, 0.15)
	tween.tween_property(body.material_override, "albedo_color:a", 0.0, 0.3)
	tween.parallel().tween_property(halo.material_override, "albedo_color:a", 0.0, 0.3)
	return effect


func _explosion(position: Vector3, size: float) -> void:
	FX.burst(self, position, Color(1.0, 0.45, 0.10), size, "ShotExplosion")
	SoundSystem.play_at("sfx_explosion", position, self)
	explosion_created.emit()


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	return material
