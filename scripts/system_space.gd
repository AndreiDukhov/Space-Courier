extends Node3D

const Art = preload("res://scripts/flight_art.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Text = preload("res://scripts/ui_text.gd")

var _objects: Node3D = Node3D.new()


func _ready() -> void:
	add_child(_objects)


func rebuild(system_id: String, gate_names: Dictionary) -> void:
	for child: Node in _objects.get_children():
		_objects.remove_child(child)
		child.queue_free()
	var system: Dictionary = DataLoader.get_record(system_id)
	for object: Dictionary in system.get("objects", []):
		var body: MeshInstance3D = Art.system_object(object)
		if object.has("id"):
			body.name = str(object["id"])
		_objects.add_child(body)
		if object["type"] == "star":
			var zone: MeshInstance3D = Art.zone(float(object["hazard"]["radius"]) * Motion.WORLD_SCALE, Color(1.0, 0.25, 0.08))
			zone.name = "Hazard_" + str(object["id"])
			zone.position = Motion.world_position(object["pos"], 0.2)
			_objects.add_child(zone)
			_objects.add_child(Art.label(Text.get_text("ui_space_star_zone"), zone.position + Vector3(0, 0, -float(object["hazard"]["radius"]) * Motion.WORLD_SCALE)))
		if object["type"] == "planet":
			_objects.add_child(Art.orbit(Motion.point(object["pos"]).distance_to(Motion.BOUNDS / 2.0) * Motion.WORLD_SCALE))
		var text: String = ""
		match object["type"]:
			"planet", "star", "station": text = str(object["name"])
			"gate": text = str(gate_names.get(object["to_route"], ""))
			"event_marker": text = Text.get_text("ui_flight_marker")
		_objects.add_child(Art.label(text, Motion.world_position(object["pos"])))
