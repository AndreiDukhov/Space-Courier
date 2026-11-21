extends Node3D

const State = preload("res://scripts/ambient_battle_state.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Art = preload("res://scripts/flight_art.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _stamp: String = ""
var _phase: float = 0.0


func _ready() -> void:
	name = "AmbientBattles"
	_mesh = MeshInstance3D.new()
	_mesh.name = "BattleBeams"
	_material = Art.material(Color.WHITE, true)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(_mesh)
	EffectApplier.flight_changed.connect(refresh)
	EffectApplier.galaxy_changed.connect(refresh)
	GameState.restored.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree() or GameState.state.is_empty():
		return
	var local: Array[Dictionary] = []
	for battle: Dictionary in GameState.state["flight"]["battles"]:
		if battle["system"] == GameState.state["current_system"]:
			local.append(battle)
	var stamp: String = str(GameState.state["current_system"])
	for battle: Dictionary in local:
		stamp += str(battle["id"])
		for npc_id: String in State.members(battle):
			stamp += JSON.stringify(GameState.state["flight"]["npcs"][npc_id]["pos"])
	if stamp == _stamp:
		return
	_stamp = stamp
	_mesh.visible = not local.is_empty()
	if local.is_empty():
		return
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for battle: Dictionary in local:
		for source: String in battle["sides"][0]:
			for target: String in battle["sides"][1]:
				var from: Vector3 = Motion.world_position(GameState.state["flight"]["npcs"][source]["pos"], 3.1)
				var to: Vector3 = Motion.world_position(GameState.state["flight"]["npcs"][target]["pos"], 3.1)
				for offset: float in [-0.15, 0.15]:
					mesh.surface_set_color(Color(0.25, 0.8, 1.0) if offset < 0 else Color(1.0, 0.45, 0.15))
					mesh.surface_add_vertex(from + Vector3(0, offset, 0))
					mesh.surface_add_vertex(to + Vector3(0, offset, 0))
	mesh.surface_end()
	_material.vertex_color_use_as_albedo = true
	_mesh.mesh = mesh


func _process(delta: float) -> void:
	if Conditions.can_tick_flight():
		var previous: int = floori(_phase * 1.4)
		_phase += delta
		if _mesh != null and _mesh.visible and floori(_phase * 1.4) != previous:
			for battle: Dictionary in GameState.state["flight"]["battles"]:
				if battle["system"] == GameState.state["current_system"]:
					var source: String = str(battle["sides"][previous % 2][0])
					SoundSystem.play_at("sfx_laser", Motion.world_position(GameState.state["flight"]["npcs"][source]["pos"], 3.1), self)
	if _material != null:
		_material.albedo_color.a = 0.35 + 0.65 * absf(sin(_phase * 9.0))
