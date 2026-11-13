extends Node3D

const Art = preload("res://scripts/flight_art.gd")
const Motion = preload("res://scripts/flight_motion.gd")


func _ready() -> void:
	EffectApplier.space_effect.connect(show_effect)
	EffectApplier.galaxy_changed.connect(clear)
	GameState.restored.connect(clear)


func clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func show_effect(kind: String, position: Vector2, _npc_id: String) -> void:
	if kind not in ["destroyed", "landing", "takeoff"]:
		return
	var colour: Color = Color(1.0, 0.35, 0.05) if kind == "destroyed" else Color(0.2, 0.9, 0.75)
	var centre: Vector3 = Motion.world_position(Motion.coordinates(position), 2.8)
	var count: int = 3 if kind == "destroyed" else 1
	for i: int in range(count):
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.8
		mesh.mesh = sphere
		mesh.material_override = Art.material(colour.lightened(float(i) * 0.2), true)
		mesh.position = centre + Vector3(float(i - 1) * 0.3, 0, float(i % 2) * 0.3)
		add_child(mesh)
		var tween: Tween = create_tween()
		tween.bind_node(mesh)
		tween.tween_property(mesh, "scale", Vector3.ONE * (4.0 if kind == "destroyed" else 2.0), 0.28)
		tween.tween_property(mesh, "scale", Vector3.ZERO, 0.35)
		tween.tween_callback(mesh.queue_free)
