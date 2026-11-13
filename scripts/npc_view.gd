extends Node3D

const Art = preload("res://scripts/flight_art.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")
const Pairs = preload("res://scripts/pirate_pairs.gd")


func rebuild(system_id: String) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["system"] != system_id or npc["id"] in GameState.state["flight"]["defeated_npcs"]:
			continue
		var vessel: Node3D = Node3D.new()
		vessel.name = str(npc["id"])
		var colour: Color = Color(0.25, 0.6, 1.0) if npc["role"] == "patrol" else Color(1.0, 0.25, 0.15) if npc["role"] == "pirate" else Color(1.0, 0.65, 0.2)
		vessel.add_child(Art.ship(colour))
		add_child(vessel)
		var label: Label3D = Art.label(str(npc["name"]), Vector3.ZERO)
		label.name = str(npc["id"]) + "_label"
		add_child(label)
	sync_positions()


func sync_positions() -> void:
	for npc: Dictionary in DataLoader.get_records("npcs"):
		var vessel: Node3D = get_node_or_null(NodePath(str(npc["id"])))
		if vessel == null:
			continue
		var entry: Dictionary = GameState.state["flight"]["npcs"][npc["id"]]
		vessel.visible = Conditions.npc_is_active(str(npc["id"]))
		vessel.position = Motion.world_position(entry["pos"], 2.8)
		var target: Vector2 = Motion.point(npc["waypoints"][int(entry["waypoint"])])
		if entry["status"] == "landing":
			target = Motion.point(Conditions.space_object(str(entry["destination"]), str(npc["system"]))["pos"])
		elif entry["status"] == "chase":
			target = Motion.point(GameState.state["flight"]["pos"] if entry["target"] == "player" else GameState.state["flight"]["npcs"][entry["target"]]["pos"])
		if Pairs.is_follower(npc, entry) and (entry["status"] == "cruise" or GameState.state["flight"]["npcs"][entry["partner"]]["target"] == entry["target"]):
			target = Pairs.follow_target(npc, GameState.state["flight"]["npcs"])
		var direction: Vector2 = target - Motion.point(entry["pos"])
		if direction.length_squared() > 0.01:
			vessel.rotation.y = atan2(direction.x, direction.y)
		var label: Label3D = get_node(NodePath(str(npc["id"]) + "_label"))
		label.visible = vessel.visible
		label.text = str(npc["name"]) + (" · " + Text.get_text("ui_space_chasing") if entry["status"] == "chase" else "")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.offset = Vector2.ZERO
		if not entry["partner"].is_empty():
			label.text += " · " + Text.get_text("ui_space_pair")
			var partner_pos: Vector2 = Motion.point(GameState.state["flight"]["npcs"][entry["partner"]]["pos"])
			var on_right: bool = Motion.point(entry["pos"]).x > partner_pos.x if not is_equal_approx(Motion.point(entry["pos"]).x, partner_pos.x) else Pairs.is_follower(npc, entry)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if on_right else HORIZONTAL_ALIGNMENT_RIGHT
			label.offset.x = 20.0 if on_right else -20.0
		label.position = vessel.position + Vector3(0, 2.0, 0)
