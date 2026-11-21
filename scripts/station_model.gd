extends MeshInstance3D

const G = preload("res://scripts/model_geometry.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")

var _rotor: Node3D
var _radar: Node3D
var _phase: float = 0.0


func configure(object: Dictionary) -> void:
	var radius: float = float(object["radius"])
	var accent: Color = Color(str(object["color"]))
	var pirate: bool = false
	for requirement: Dictionary in DataLoader.get_record(str(object.get("shop", ""))).get("requires", []):
		pirate = pirate or requirement.get("rep") == "mafia"
	var metal: Color = Color(0.31, 0.28, 0.24) if pirate else Color(0.62, 0.70, 0.79)
	var core: CylinderMesh = CylinderMesh.new()
	core.top_radius = radius * 0.25
	core.bottom_radius = radius * 0.34
	core.height = radius * 0.8
	core.radial_segments = 8
	mesh = core
	material_override = G.material(metal)
	_rotor = Node3D.new()
	_rotor.name = "HabitatRing"
	add_child(_rotor)
	G.ring(_rotor, "OuterFrame", Vector3.ZERO, radius * 0.86, radius * 0.075, metal)
	G.ring(_rotor, "WindowBand", Vector3(0, radius * 0.04, 0), radius * 0.86, radius * 0.022, accent, true)
	for index: int in range(6 if not pirate else 5):
		var arm: Node3D = Node3D.new()
		arm.rotation.y = TAU * index / (6.0 if not pirate else 5.0)
		_rotor.add_child(arm)
		G.box(arm, "Spoke", Vector3(radius * 0.5, -0.04, 0), Vector3(radius * 0.70, radius * 0.07, radius * 0.10), metal.darkened(0.15))
		G.box(arm, "Habitat", Vector3(radius * 0.84, radius * 0.03, 0), Vector3(radius * 0.28, radius * 0.20, radius * (0.34 if not pirate else 0.49)), metal)
		G.box(arm, "Windows", Vector3(radius * 0.84, radius * 0.14, 0), Vector3(radius * 0.18, radius * 0.025, radius * 0.24), accent, true)
	G.cylinder(self, "CommandDeck", Vector3(0, radius * 0.49, 0), radius * 0.31, radius * 0.16, metal)
	G.ring(self, "CommandWindows", Vector3(0, radius * 0.51, 0), radius * 0.31, radius * 0.025, accent, true)
	for side: int in [-1, 1]:
		G.box(self, "DockBridge", Vector3(side * radius * 0.40, -radius * 0.34, 0), Vector3(radius * 0.7, radius * 0.10, radius * 0.16), metal)
		G.box(self, "Hangar", Vector3(side * radius * 0.85, -radius * 0.28, 0), Vector3(radius * 0.45, radius * 0.28, radius * 0.50), metal.darkened(0.25))
		G.box(self, "DockEntrance", Vector3(side * radius * 0.85, -radius * 0.24, -radius * 0.26), Vector3(radius * 0.28, radius * 0.14, radius * 0.025), Color(0.16, 0.8, 0.9) if not pirate else Color(1, 0.48, 0.12), true)
		var panels: MeshInstance3D = G.box(self, "SolarArray", Vector3(side * radius * 1.18, radius * 0.23, 0), Vector3(radius * 0.48, radius * 0.035, radius * 0.8), Color(0.08, 0.17, 0.34))
		panels.rotation.z = side * 0.16
		for row: int in range(4):
			G.box(panels, "PanelCell", Vector3(0, radius * 0.023, (-0.30 + row * 0.20) * radius), Vector3(radius * 0.43, radius * 0.015, radius * 0.015), accent.darkened(0.35))
	_radar = Node3D.new()
	_radar.name = "Radar"
	_radar.position.y = radius * 0.8
	add_child(_radar)
	G.cylinder(_radar, "Mast", Vector3(0, -radius * 0.1, 0), radius * 0.025, radius * 0.36, metal)
	var dish: MeshInstance3D = G.cylinder(_radar, "Dish", Vector3.ZERO, radius * 0.18, radius * 0.08, metal, radius * 0.04)
	dish.rotation.x = 0.9
	G.box(_radar, "Beacon", Vector3(0, radius * 0.15, 0), Vector3.ONE * radius * 0.05, accent, true)


func _process(delta: float) -> void:
	if _rotor == null or not Conditions.can_tick_flight():
		return
	_phase += delta
	_rotor.rotation.y = _phase * 0.055
	_radar.rotation.y = -_phase * 0.18
