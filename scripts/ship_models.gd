extends RefCounted

const G = preload("res://scripts/model_geometry.gd")
const Visual = preload("res://scripts/ship_visual.gd")
const Roster = preload("res://scripts/combat_roster.gd")
const STEEL: Color = Color(0.23, 0.29, 0.36)
const DARK: Color = Color(0.075, 0.1, 0.14)
const GLASS: Color = Color(0.2, 0.85, 1.0)


static func npc_role(npc: Dictionary) -> String:
	return "transport" if npc.get("role") == "civilian" and npc.has("shop") else str(npc.get("role", "civilian"))


static func actor_key(actor: String) -> String:
	if actor == "player":
		return JSON.stringify(GameState.state["ship"]["modules"])
	var entry: Dictionary = Roster.actor(actor)
	return str(entry.get("source_npc", "")) + "|" + str(entry.get("enemy", "")) + "|" + JSON.stringify(entry.get("weapons", []))


static func for_actor(actor: String) -> Visual:
	if actor == "player":
		return create("player", 0, GameState.state["ship"]["modules"])
	var entry: Dictionary = Roster.actor(actor)
	var source: String = str(entry.get("source_npc", ""))
	var npc: Dictionary = DataLoader.get_record(source)
	var enemy: Dictionary = DataLoader.get_record(str(entry.get("enemy", "")))
	var role: String = npc_role(npc) if not npc.is_empty() else "pirate" if "pirate" in enemy.get("tags", []) else "patrol" if "law_abiding" in enemy.get("tags", []) else "civilian"
	return create(role, absi((source if not source.is_empty() else str(enemy.get("id", ""))).hash()) % 2, entry.get("weapons", []))


static func create(role: String = "player", variant: int = 0, weapons: Array = []) -> Visual:
	var ship: Visual = Visual.new()
	ship.name = "ShipModel"
	ship.role = role
	ship.variant = variant % 2
	for label: String in ["Thrusters", "Beacons", "Weapons"]:
		var group: Node3D = Node3D.new()
		group.name = label
		ship.add_child(group)
	match role:
		"pirate": _pirate(ship, variant % 2)
		"patrol": _patrol(ship, variant % 2)
		"transport": _transport(ship)
		"civilian": _courier(ship, false)
		_: _courier(ship, true)
	_weapons(ship, weapons)
	return ship


static func _courier(ship: Visual, player: bool) -> void:
	var accent: Color = Color(0.08, 0.72, 0.65) if player else Color(0.95, 0.61, 0.12)
	G.hull(ship, "Hull", PackedVector2Array([Vector2(-0.26, 0.52), Vector2(-0.28, -0.1), Vector2(-0.12, -0.83), Vector2(0.12, -0.83), Vector2(0.28, -0.1), Vector2(0.26, 0.52)]), 0.24, Color(0.64, 0.71, 0.76))
	G.box(ship, "Spine", Vector3(0, 0.28, 0.03), Vector3(0.14, 0.1, 0.7), accent)
	G.box(ship, "Cockpit", Vector3(0, 0.24, -0.42), Vector3(0.23, 0.08, 0.18), GLASS, true)
	for side: int in [-1, 1]:
		G.box(ship, "Wing", Vector3(side * 0.33, 0.10, 0.23), Vector3(0.32, 0.12, 0.40), STEEL)
		G.box(ship, "WingStripe", Vector3(side * 0.36, 0.17, 0.19), Vector3(0.09, 0.025, 0.29), accent)
		_engine(ship, Vector3(side * 0.32, 0.07, 0.54), 0.105)
		_beacon(ship, Vector3(side * 0.5, 0.17, 0.34), Color(1.0, 0.18, 0.1) if side < 0 else GLASS)
	if not player:
		for side: int in [-1, 1]:
			G.box(ship, "CargoPod", Vector3(side * 0.2, 0.29, 0.17), Vector3(0.15, 0.16, 0.29), accent.darkened(0.15))
	G.cylinder(ship, "Aerial", Vector3(0.13, 0.41, 0.31), 0.018, 0.3, STEEL, -1.0, false, 6)


static func _pirate(ship: Visual, variant: int) -> void:
	var accent: Color = Color(0.72, 0.16, 0.07)
	var wide: float = 0.28 if variant == 0 else 0.38
	G.hull(ship, "Hull", PackedVector2Array([Vector2(-wide, 0.53), Vector2(-wide, -0.05), Vector2(-0.08, -0.87), Vector2(0.13, -0.72), Vector2(wide, 0.12), Vector2(wide, 0.53)]), 0.26, Color(0.29, 0.23, 0.22))
	G.box(ship, "ArmourSpine", Vector3(-0.08, 0.30, -0.02), Vector3(0.18, 0.12, 0.61), accent)
	G.box(ship, "Cockpit", Vector3(-0.04, 0.28, -0.36), Vector3(0.18, 0.06, 0.13), Color(1.0, 0.52, 0.12), true)
	for side: int in [-1, 1]:
		var z: float = -0.12 if side < 0 else 0.22
		var fin: MeshInstance3D = G.box(ship, "SweptFin", Vector3(side * 0.39, 0.1, z), Vector3(0.43, 0.1, 0.22), accent.darkened(0.25))
		fin.rotation.y = side * 0.5
		G.box(ship, "ArmourPlate", Vector3(side * wide * 0.7, 0.27, 0.24), Vector3(0.13, 0.06, 0.3), STEEL)
		_engine(ship, Vector3(side * (0.25 if variant == 0 else 0.32), 0.1, 0.57), 0.12)
		_beacon(ship, Vector3(side * 0.52, 0.18, z), Color(1.0, 0.22, 0.04))
	G.cylinder(ship, "ExposedReactor", Vector3(0.14, 0.31, 0.33), 0.12, 0.12, Color(1, 0.45, 0.08), -1, true)
	if variant == 1:
		G.box(ship, "SalvagePod", Vector3(-0.42, 0.22, 0.34), Vector3(0.22, 0.27, 0.38), Color(0.47, 0.37, 0.18))


static func _patrol(ship: Visual, variant: int) -> void:
	var white: Color = Color(0.78, 0.83, 0.88)
	var blue: Color = Color(0.1, 0.25, 0.55)
	G.hull(ship, "Hull", PackedVector2Array([Vector2(-0.28, 0.52), Vector2(-0.37, 0.1), Vector2(-0.14, -0.84), Vector2(0.14, -0.84), Vector2(0.37, 0.1), Vector2(0.28, 0.52)]), 0.22, white)
	G.box(ship, "CommandBridge", Vector3(0, 0.29, -0.04), Vector3(0.24, 0.14, 0.4), blue)
	G.box(ship, "Cockpit", Vector3(0, 0.37, -0.18), Vector3(0.2, 0.045, 0.10), GLASS, true)
	for side: int in [-1, 1]:
		var wing: MeshInstance3D = G.box(ship, "Outrigger", Vector3(side * 0.37, 0.08, 0.2), Vector3(0.29, 0.15, 0.67 if variant == 0 else 0.92), white)
		wing.rotation.y = side * 0.18
		G.box(ship, "PoliceStripe", Vector3(side * 0.38, 0.17, 0.16), Vector3(0.11, 0.035, 0.49), blue)
		_engine(ship, Vector3(side * 0.38, 0.1, 0.61), 0.12)
		_beacon(ship, Vector3(side * 0.13, 0.40, 0.07), Color(1.0, 0.14, 0.12) if side < 0 else Color(0.18, 0.48, 1.0))
	G.cylinder(ship, "RadarMast", Vector3(0, 0.43, 0.28), 0.025, 0.23, STEEL)
	G.box(ship, "RadarArray", Vector3(0, 0.56, 0.28), Vector3(0.31, 0.045, 0.08), blue)


static func _transport(ship: Visual) -> void:
	G.hull(ship, "Hull", PackedVector2Array([Vector2(-0.21, 0.64), Vector2(-0.21, -0.66), Vector2(0, -0.88), Vector2(0.21, -0.66), Vector2(0.21, 0.64)]), 0.22, STEEL)
	G.box(ship, "Bridge", Vector3(0, 0.33, -0.55), Vector3(0.38, 0.22, 0.32), Color(0.76, 0.70, 0.48))
	G.box(ship, "Cockpit", Vector3(0, 0.46, -0.62), Vector3(0.28, 0.04, 0.09), GLASS, true)
	for side: int in [-1, 1]:
		for index: int in range(3):
			var z: float = -0.24 + index * 0.28
			G.box(ship, "Container", Vector3(side * 0.33, 0.18, z), Vector3(0.36, 0.29, 0.23), Color(0.63, 0.28 + index * 0.05, 0.075))
			G.box(ship, "ContainerBand", Vector3(side * 0.33, 0.335, z), Vector3(0.38, 0.025, 0.035), Color(0.88, 0.71, 0.33))
		_engine(ship, Vector3(side * 0.28, 0.09, 0.67), 0.15)
		_beacon(ship, Vector3(side * 0.52, 0.18, 0.42), GLASS)


static func _engine(ship: Visual, position: Vector3, radius: float) -> void:
	var nozzle: MeshInstance3D = G.cylinder(ship, "EngineNozzle", position - Vector3(0, 0, 0.08), radius * 1.3, 0.2, DARK)
	nozzle.rotation.x = PI / 2.0
	var engine: Node3D = Node3D.new()
	engine.position = position
	ship.get_node("Thrusters").add_child(engine)
	var core: MeshInstance3D = G.cylinder(engine, "Core", Vector3.ZERO, radius * 0.85, 0.035, GLASS, -1, true)
	core.rotation.x = PI / 2.0
	var plume: MeshInstance3D = G.cylinder(engine, "Plume", Vector3(0, 0, 0.15), radius * 0.8, 0.44, Color(0.12, 0.66, 1.0, 0.55), 0.0, true)
	plume.rotation.x = PI / 2.0


static func _beacon(ship: Visual, position: Vector3, color: Color) -> void:
	G.box(ship.get_node("Beacons"), "Light", position, Vector3(0.06, 0.04, 0.06), color, true)


static func _weapons(ship: Visual, weapons: Array) -> void:
	var mounts: Array[String] = []
	for id: String in weapons:
		var mount: String = str(DataLoader.get_record(id).get("mount", ""))
		if not mount.is_empty() and mount not in mounts:
			mounts.append(mount)
	var parent: Node3D = ship.get_node("Weapons")
	if "turret" in mounts:
		G.cylinder(parent, "Turret", Vector3(0, 0.35, 0.14), 0.12, 0.12, STEEL)
		G.box(parent, "TurretBarrel", Vector3(0, 0.41, -0.01), Vector3(0.055, 0.055, 0.33), DARK)
	if "course" in mounts:
		for side: int in [-1, 1]:
			G.box(parent, "CourseBarrel", Vector3(side * 0.17, 0.16, -0.57), Vector3(0.065, 0.065, 0.5), DARK)
	if "broadside" in mounts:
		for side: int in [-1, 1]:
			for index: int in range(2):
				G.box(parent, "BroadsidePort", Vector3(side * 0.37, 0.22, 0.02 + index * 0.14), Vector3(0.21, 0.07, 0.065), DARK)
