extends Node3D

signal motion_changed

const Math = preload("res://scripts/combat_math.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Art = preload("res://scripts/flight_art.gd")
const Models = preload("res://scripts/ship_placeholder.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")
const ShotFX = preload("res://scripts/combat_shot_fx.gd")
const Routes = preload("res://scripts/combat_routes.gd")

var _tiles: Dictionary = {}
var _materials: Dictionary = {}
var _vessels: Dictionary = {}
var _targets: Dictionary = {}
var _facings: Dictionary = {}
var _turns: Dictionary = {}
var _tweens: Dictionary = {}
var _route_line: MeshInstance3D = MeshInstance3D.new()
var _active_route: Array[Vector2i] = []
var _fx: Node3D
var _pending_shots: Array = []
var _shot_stamp: String = ""


func _ready() -> void:
	_route_line.name = "MovementRoute"
	_route_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_route_line)
	_fx = Node3D.new()
	_fx.name = "ShotFX"
	_fx.set_script(ShotFX)
	add_child(_fx)
	_fx.finished.connect(_on_fx_finished)
	var tiles: Node3D = Node3D.new()
	tiles.name = "Tiles"
	add_child(tiles)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.95, 0.04, 0.95)
	for y: int in range(Math.HEIGHT):
		for x: int in range(Math.WIDTH):
			var tile: MeshInstance3D = MeshInstance3D.new()
			tile.mesh = mesh
			tile.position = Math.world_position([x, y]) - Vector3(0, 0.25, 0)
			_tiles[Vector2i(x, y)] = tile
			tiles.add_child(tile)
	for actor: String in ["player", "opponent"]:
		var vessel: Node3D = Models.create(Color(0.12, 0.9, 0.8) if actor == "player" else Color(1.0, 0.36, 0.2), actor == "opponent")
		vessel.name = "PlayerShip" if actor == "player" else "EnemyShip"
		_vessels[actor] = vessel
		add_child(vessel)
		var label: Label3D = Art.label(Text.get_text("ui_combat_player_marker" if actor == "player" else "ui_combat_enemy_marker"), Vector3(0, -0.9 if actor == "player" else -0.25, 0))
		label.font_size = 28
		label.pixel_size = 0.01
		vessel.add_child(label)
	reset_from_state()


func is_animating() -> bool:
	return not _tweens.is_empty() or not _pending_shots.is_empty() or (_fx != null and _fx.active)


func reset_from_state() -> void:
	for tween: Tween in _tweens.values():
		tween.kill()
	_tweens.clear()
	_active_route.clear()
	_route_line.visible = false
	_pending_shots = []
	_fx.clear()
	if not Conditions.has_combat():
		return
	_shot_stamp = _current_shot_stamp()
	for actor: String in _vessels:
		var entry: Dictionary = GameState.state["combat"][actor]
		_targets[actor] = entry["pos"].duplicate()
		_facings[actor] = int(entry["facing"])
		_turns[actor] = GameState.state["combat"]["movement"][actor].duplicate(true)
		_vessels[actor].position = Math.world_position(entry["pos"])
		_vessels[actor].rotation.y = _yaw(int(entry["facing"]))


func refresh(show_movement: bool, weapon: Dictionary, hovered: Vector2i) -> void:
	if not is_node_ready() or not Conditions.has_combat():
		return
	var combat: Dictionary = GameState.state["combat"]
	var origin: Vector2i = Math.cell(combat["player"]["pos"])
	var enemy: Vector2i = Math.cell(combat["opponent"]["pos"])
	for cell: Vector2i in _tiles:
		var color: Color = Color(0.065, 0.095, 0.14) if (cell.x + cell.y) % 2 == 0 else Color(0.085, 0.125, 0.18)
		if not weapon.is_empty() and Conditions.can_fire_weapon(combat["player"], {"pos": Math.coordinates(cell)}, weapon, Math.ACTION_POINTS):
			color = Color(0.32, 0.17, 0.12)
		if show_movement and (Conditions.can_move_combat(cell) or (_tweens.has("player") and cell in _active_route)):
			color = Color(0.06, 0.32, 0.28)
		if cell == origin:
			color = Color(0.08, 0.57, 0.48)
		elif cell == enemy:
			color = Color(0.65, 0.16, 0.1)
		if cell == hovered:
			color = color.lightened(0.3)
		color.a = 0.5
		if not _materials.has(color):
			_materials[color] = Art.material(color)
			_materials[color].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tiles[cell].material_override = _materials[color]
	var started: bool = false
	for actor: String in _vessels:
		var entry: Dictionary = combat[actor]
		if _targets.get(actor, []) != entry["pos"] or _facings.get(actor, -1) != int(entry["facing"]):
			_animate(actor, entry, combat["movement"][actor])
			started = true
		_turns[actor] = combat["movement"][actor].duplicate(true)
	if _tweens.has("player"):
		_draw_route(_active_route)
	elif not is_animating() and show_movement:
		_draw_route(Conditions.combat_move_path(hovered))
	else:
		_route_line.visible = false
	var stamp: String = _current_shot_stamp()
	if stamp != _shot_stamp:
		_shot_stamp = stamp
		_pending_shots = combat["shots"].duplicate(true)
		started = started or not _pending_shots.is_empty()
	_try_play_shots()
	_vessels["opponent"].visible = combat["opponent"]["hull"] > 0 or is_animating()
	if started:
		motion_changed.emit()


func _animate(actor: String, entry: Dictionary, turn: Dictionary) -> void:
	if _tweens.has(actor):
		_tweens[actor].kill()
		_tweens.erase(actor)
	var vessel: Node3D = _vessels[actor]
	var points: Array[Vector2i] = _animation_path(actor, entry, turn)
	_targets[actor] = entry["pos"].duplicate()
	_facings[actor] = int(entry["facing"])
	if actor == "player":
		_active_route = points.duplicate()
	if points.is_empty():
		vessel.position = Math.world_position(entry["pos"])
		vessel.rotation.y = _yaw(int(entry["facing"]))
		return
	var tween: Tween = create_tween()
	_tweens[actor] = tween
	var previous_position: Vector3 = vessel.position
	var previous_yaw: float = vessel.rotation.y
	for point: Vector2i in points.slice(1):
		var destination: Vector3 = Math.world_position(Math.coordinates(point))
		var delta: Vector3 = destination - previous_position
		var yaw: float = previous_yaw + angle_difference(previous_yaw, atan2(-delta.x, -delta.z))
		var duration: float = clampf(delta.length() * 0.18, 0.12, 0.5)
		tween.tween_property(vessel, "position", destination, duration)
		tween.parallel().tween_property(vessel, "rotation:y", yaw, minf(duration, 0.12))
		previous_position = destination
		previous_yaw = yaw
	var final_yaw: float = previous_yaw + angle_difference(previous_yaw, _yaw(int(entry["facing"])))
	if absf(angle_difference(previous_yaw, final_yaw)) > 0.00001:
		tween.tween_property(vessel, "rotation:y", final_yaw, 0.12)
	tween.finished.connect(_on_motion_finished.bind(actor))


func _animation_path(actor: String, entry: Dictionary, turn: Dictionary) -> Array[Vector2i]:
	var old_turn: Dictionary = _turns[actor]
	var history: Array = turn["history"]
	var old_history: Array = old_turn["history"]
	var settings: Dictionary = Math.movement_settings(true) if actor == "player" else DataLoader.get_record(str(GameState.state["combat"]["enemy"]))["movement"]
	var other: String = "opponent" if actor == "player" else "player"
	var occupied: Vector2i = Math.cell(GameState.state["combat"][other]["pos"])
	var same_turn: bool = old_turn["origin"] == turn["origin"] and old_turn["facing"] == turn["facing"]
	if same_turn and history.size() < old_history.size() and old_history.slice(0, history.size()) == history:
		var reverse: Array[Vector2i] = Routes.trace(old_turn, _targets[actor], settings, occupied, history.size())
		reverse.reverse()
		return reverse
	var first: int = old_history.size() if same_turn and history.slice(0, old_history.size()) == old_history else 0
	return Routes.trace(turn, entry["pos"], settings, occupied, first)


func _draw_route(points: Array[Vector2i]) -> void:
	_route_line.visible = points.size() > 1
	if not _route_line.visible:
		return
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = Art.material(Color(0.3, 1.0, 0.7), true)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index: int in range(1, points.size()):
		mesh.surface_add_vertex(Math.world_position(Math.coordinates(points[index - 1])) + Vector3(0, -0.16, 0))
		mesh.surface_add_vertex(Math.world_position(Math.coordinates(points[index])) + Vector3(0, -0.16, 0))
	var end: Vector3 = Math.world_position(Math.coordinates(points[-1])) + Vector3(0, -0.16, 0)
	var heading: Vector2 = Movement.heading(Routes.arrival_facing(points))
	var direction: Vector3 = Vector3(heading.x, 0, heading.y)
	var side: Vector3 = Vector3(-direction.z, 0, direction.x) * 0.12
	for offset: Vector3 in [side, -side]:
		mesh.surface_add_vertex(end)
		mesh.surface_add_vertex(end - direction * 0.3 + offset)
	mesh.surface_end()
	_route_line.mesh = mesh


func _on_motion_finished(actor: String) -> void:
	_tweens.erase(actor)
	if actor == "player":
		_active_route.clear()
	_try_play_shots()
	motion_changed.emit()


func _current_shot_stamp() -> String:
	return str(GameState.state["combat"]["round"]) + "|" + JSON.stringify(GameState.state["combat"]["shots"])


func _try_play_shots() -> void:
	if not _tweens.is_empty() or _fx.active or _pending_shots.is_empty():
		return
	var shots: Array = _pending_shots
	_pending_shots = []
	_fx.play(shots)


func _on_fx_finished() -> void:
	_try_play_shots()
	if Conditions.has_combat():
		_vessels["opponent"].visible = GameState.state["combat"]["opponent"]["hull"] > 0
	motion_changed.emit()


func _yaw(facing: int) -> float:
	var direction: Vector2 = Movement.heading(facing)
	return atan2(-direction.x, -direction.y)
