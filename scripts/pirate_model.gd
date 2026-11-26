extends RefCounted

const G = preload("res://scripts/model_geometry.gd")
const HULL: Color = Color("514947")
const ARMOR: Color = Color("847565")
const DARK: Color = Color("24262b")
const RUST: Color = Color("a52f21")
const PATCH: Color = Color("b38b50")
const HOT: Color = Color("ff9a3d")
const GLASS: Color = Color("ffbc70")


static func build(ship: Node3D, variant: int) -> void:
	if variant == 0:
		_raider(ship)
	else:
		_scavenger(ship)
	_reactor(ship, Vector3(0.09 if variant == 0 else -0.12, 0.32, 0.40))
	var mast: MeshInstance3D = G.cylinder(ship, "SensorMast", Vector3(-0.12, 0.42, -0.16), 0.012, 0.22, ARMOR, -1, false, 6)
	mast.rotation.z = -0.28
	G.box(ship, "SensorArray", Vector3(-0.15, 0.53, -0.16), Vector3(0.17, 0.025, 0.05), DARK)


static func _raider(ship: Node3D) -> void:
	G.hull(ship, "Hull", PackedVector2Array([Vector2(-0.22, 0.59), Vector2(-0.28, 0.06), Vector2(-0.18, -0.51), Vector2(0, -0.70), Vector2(0.20, -0.45), Vector2(0.28, 0.23), Vector2(0.23, 0.59)]), 0.23, HULL)
	for side: int in [-1, 1]:
		var fork: MeshInstance3D = G.hull(ship, "ProwFork", PackedVector2Array([Vector2(-0.08, 0.20), Vector2(-0.055, -0.38), Vector2(0.015, -0.52), Vector2(0.07, -0.25), Vector2(0.09, 0.17)]), 0.12, ARMOR if side < 0 else RUST)
		fork.position = Vector3(side * 0.16, 0.07, -0.48)
		var wing: MeshInstance3D = G.hull(ship, "ClawWing", PackedVector2Array([Vector2(side * 0.18, 0.39), Vector2(side * 0.23, -0.18), Vector2(side * 0.63, -0.48), Vector2(side * 0.68, -0.24), Vector2(side * 0.54, 0.39)]), 0.10, RUST.darkened(0.20))
		wing.position.y = 0.015
		_pod(ship, Vector3(side * 0.48, 0.08, 0.17), 0.19, 0.75, HULL)
		G.box(ship, "PodArmor", Vector3(side * 0.48, 0.26, 0.12), Vector3(0.14, 0.025, 0.45), RUST if side < 0 else ARMOR)
		_vents(ship, Vector3(side * 0.48, 0.28, 0.19), 4)
		var strut: MeshInstance3D = G.box(ship, "WingBrace", Vector3(side * 0.33, 0.13, 0.27), Vector3(0.35, 0.06, 0.055), PATCH)
		strut.rotation.y = side * 0.35
		G.box(ship, "KeelFin", Vector3(side * 0.46, 0.32, 0.43), Vector3(0.035, 0.19, 0.24), DARK)
	var bridge: MeshInstance3D = G.hull(ship, "Bridge", PackedVector2Array([Vector2(-0.14, 0.14), Vector2(-0.13, -0.11), Vector2(0, -0.24), Vector2(0.13, -0.11), Vector2(0.14, 0.14)]), 0.13, DARK)
	bridge.position = Vector3(0, 0.23, -0.21)
	var canopy: MeshInstance3D = G.box(ship, "Cockpit", Vector3(0, 0.36, -0.34), Vector3(0.15, 0.035, 0.12), GLASS, true)
	canopy.rotation.x = -0.22
	G.box(ship, "CanopyDivider", Vector3(0, 0.385, -0.34), Vector3(0.018, 0.022, 0.14), DARK)
	G.box(ship, "DeckPlate", Vector3(-0.11, 0.25, 0.13), Vector3(0.14, 0.035, 0.25), RUST)
	_insignia(ship, Vector3(-0.48, 0.30, -0.05), 0.8)


static func _scavenger(ship: Node3D) -> void:
	G.hull(ship, "Hull", PackedVector2Array([Vector2(-0.29, 0.65), Vector2(-0.37, 0.14), Vector2(-0.27, -0.47), Vector2(-0.04, -0.83), Vector2(0.27, -0.53), Vector2(0.37, 0.02), Vector2(0.29, 0.65)]), 0.27, HULL)
	var prow: MeshInstance3D = G.hull(ship, "ProwArmor", PackedVector2Array([Vector2(-0.27, -0.27), Vector2(-0.18, -0.62), Vector2(-0.04, -0.83), Vector2(0.25, -0.47), Vector2(0.21, -0.24)]), 0.10, ARMOR)
	prow.position.y = 0.22
	var stripe: MeshInstance3D = G.box(ship, "ProwStripe", Vector3(-0.04, 0.315, -0.51), Vector3(0.10, 0.02, 0.28), RUST)
	stripe.rotation.y = -0.10
	for side: int in [-1, 1]:
		var shoulder: MeshInstance3D = G.hull(ship, "ShoulderArmor", PackedVector2Array([Vector2(-0.14, 0.32), Vector2(-0.17, -0.12), Vector2(0.06, -0.33), Vector2(0.17, -0.10), Vector2(0.15, 0.32)]), 0.16, RUST if side > 0 else PATCH)
		shoulder.position = Vector3(side * 0.45, 0.10, 0.03 if side > 0 else 0.16)
		_pod(ship, Vector3(side * 0.38, 0.06, 0.43), 0.24, 0.53, DARK)
		G.box(ship, "EngineShroud", Vector3(side * 0.38, 0.25, 0.47), Vector3(0.16, 0.045, 0.27), ARMOR)
		_vents(ship, Vector3(side * 0.38, 0.28, 0.47), 3)
		G.box(ship, "ArmorRail", Vector3(side * 0.28, 0.32, 0.16), Vector3(0.045, 0.055, 0.42), ARMOR)
	var bridge: MeshInstance3D = G.hull(ship, "Bridge", PackedVector2Array([Vector2(-0.13, 0.14), Vector2(-0.14, -0.06), Vector2(-0.06, -0.17), Vector2(0.13, -0.09), Vector2(0.13, 0.14)]), 0.15, DARK)
	bridge.position = Vector3(0.07, 0.27, -0.18)
	G.box(ship, "Cockpit", Vector3(0.07, 0.405, -0.28), Vector3(0.18, 0.035, 0.075), GLASS, true)
	G.box(ship, "BridgeRoof", Vector3(0.07, 0.435, -0.14), Vector3(0.17, 0.03, 0.17), RUST)
	var tank: MeshInstance3D = G.cylinder(ship, "SalvageTank", Vector3(-0.57, 0.16, -0.05), 0.105, 0.58, PATCH, -1, false, 10)
	tank.rotation.x = PI / 2
	for z: float in [-0.24, 0.13]:
		var band: MeshInstance3D = G.ring(ship, "TankClamp", Vector3(-0.57, 0.16, z), 0.109, 0.012, DARK)
		band.rotation.x = PI / 2
		G.box(ship, "TankBrace", Vector3(-0.43, 0.12, z), Vector3(0.31, 0.045, 0.06), ARMOR)
	G.box(ship, "RadiatorFrame", Vector3(0.54, 0.15, 0.34), Vector3(0.33, 0.07, 0.37), DARK)
	for index: int in range(5):
		G.box(ship, "RadiatorFin", Vector3(0.54, 0.20, 0.19 + index * 0.07), Vector3(0.32, 0.035, 0.025), ARMOR)
	_insignia(ship, Vector3(0.45, 0.28, -0.07), 1.0)


static func _pod(ship: Node3D, position: Vector3, width: float, length: float, color: Color) -> void:
	var pod: MeshInstance3D = G.hull(ship, "EnginePod", PackedVector2Array([Vector2(-width * 0.5, length * 0.5), Vector2(-width * 0.5, -length * 0.28), Vector2(0, -length * 0.55), Vector2(width * 0.5, -length * 0.28), Vector2(width * 0.5, length * 0.5)]), 0.16, color)
	pod.position = position


static func _vents(ship: Node3D, position: Vector3, count: int) -> void:
	for index: int in range(count):
		G.box(ship, "CoolingVent", position + Vector3(0, 0, (index - (count - 1) * 0.5) * 0.052), Vector3(0.11, 0.015, 0.023), DARK)


static func _reactor(ship: Node3D, position: Vector3) -> void:
	G.cylinder(ship, "ReactorHousing", position, 0.13, 0.09, DARK, -1, false, 10)
	G.cylinder(ship, "ReactorCore", position + Vector3(0, 0.055, 0), 0.085, 0.03, HOT, -1, true, 10)
	G.ring(ship, "ReactorGuard", position + Vector3(0, 0.08, 0), 0.105, 0.017, ARMOR)
	for index: int in range(3):
		var brace: MeshInstance3D = G.box(ship, "ReactorBrace", position + Vector3(0, 0.09, 0), Vector3(0.025, 0.025, 0.22), DARK)
		brace.rotation.y = index * PI / 3


static func _insignia(ship: Node3D, position: Vector3, scale: float) -> void:
	var emblem: Node3D = Node3D.new()
	emblem.name = "PirateInsignia"
	emblem.position = position
	emblem.scale = Vector3.ONE * scale
	ship.add_child(emblem)
	for side: int in [-1, 1]:
		var bone: MeshInstance3D = G.box(emblem, "Crossbone", Vector3(0, 0, 0.035), Vector3(0.025, 0.012, 0.17), Color("dfcbaa"))
		bone.rotation.y = side * 0.85
	G.cylinder(emblem, "Skull", Vector3(0, 0.01, -0.025), 0.044, 0.014, Color("dfcbaa"), -1, false, 8)
	for side: int in [-1, 1]:
		G.box(emblem, "Eye", Vector3(side * 0.018, 0.02, -0.035), Vector3(0.014, 0.008, 0.016), DARK)
