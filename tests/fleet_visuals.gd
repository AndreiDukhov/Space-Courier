extends Node

const Models = preload("res://scripts/ship_models.gd")
const G = preload("res://scripts/model_geometry.gd")
const Art = preload("res://scripts/flight_art.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const FX = preload("res://scripts/impact_fx.gd")
const State = preload("res://scripts/combat_state.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_launch()
	await _check_gallery()
	await _check_flight()
	await _check_combat()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Fleet visual checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _launch() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	for entry: Dictionary in GameState.state["flight"]["npcs"].values():
		entry["cooldown"] = 10000.0


func _check_gallery() -> void:
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	container.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.012, 0.024, 0.044)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.8, 1.0)
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -30, 0)
	light.light_energy = 1.5
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 10, 8)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var specifications: Array = [["player", 0], ["civilian", 0], ["transport", 0], ["pirate", 0], ["pirate", 1], ["patrol", 0], ["patrol", 1]]
	var snapshot: Dictionary = GameState.serialize()
	seed(85021)
	var expected_random: int = randi()
	seed(85021)
	var meshes: Array[Mesh] = []
	var ships: Array[Node3D] = []
	for index: int in range(specifications.size()):
		var role: String = specifications[index][0]
		var model: Node3D = Models.create(role, specifications[index][1], ["cannon_s", "course_cannon", "broadside_plasma"])
		model.position = Vector3((index % 4 - 1.5) * 2.6, 0, -1.8 if index < 4 else 1.8)
		viewport.add_child(model)
		ships.append(model)
		model.set_motion(true)
		meshes.append(model.get_node("Hull").mesh)
		var label: Label3D = Art.label(role.to_upper() + " " + str(specifications[index][1] + 1), model.position + Vector3(0, 0, 0.9))
		label.pixel_size = 0.008
		label.font_size = 26
		viewport.add_child(label)
		_check(model.get_node("Weapons").has_node("Turret") and model.get_node("Weapons").find_children("Broadside*", "MeshInstance3D", false, false).size() == 4, "The actual weapon mounts appear on each armed hull")
	_check(randi() == expected_random and GameState.serialize() == snapshot, "Building visual models consumes no gameplay randomness or saved state")
	_check(meshes[0] != meshes[2] and meshes[2] != meshes[3] and meshes[3] != meshes[5] and meshes[3] != meshes[4], "Factions and pirate variants use distinct hull geometry")
	await _frames()
	await _capture("ship-gallery")
	for ship: Node3D in ships:
		ship.queue_free()
	for child: Node in viewport.get_children():
		if child is Label3D:
			child.queue_free()
	await _frames()
	var stations: Array[Node3D] = []
	for system: String in ["sys_earth", "sys_alpha"]:
		for object: Dictionary in DataLoader.get_record(system)["objects"]:
			if object["type"] != "station":
				continue
			var station: Node3D = Art.system_object(object)
			station.position = Vector3(-3.5 if system == "sys_earth" else 3.5, 0, 0)
			station.scale = Vector3.ONE * 0.85
			viewport.add_child(station)
			stations.append(station)
			_check(station.has_node("HabitatRing") and station.find_children("Hangar*", "MeshInstance3D", false, false).size() == 2, "Stations have habitat rings and two docking hangars")
			var label: Label3D = Art.label(str(object["name"]), station.position + Vector3(0, 1.7, 0))
			label.font_size = 24
			label.pixel_size = 0.01
			viewport.add_child(label)
	var initial_angle: float = stations[0].get_node("HabitatRing").rotation.y
	await get_tree().create_timer(0.2).timeout
	_check(stations[0].get_node("HabitatRing").rotation.y > initial_angle, "The station rotates slowly during active flight")
	GameState.state["flight"]["paused"] = true
	initial_angle = stations[0].get_node("HabitatRing").rotation.y
	await get_tree().create_timer(0.1).timeout
	_check(stations[0].get_node("HabitatRing").rotation.y == initial_angle, "Station animation respects the flight pause")
	GameState.state["flight"]["paused"] = false
	await _capture("station-gallery")
	container.queue_free()
	await _frames()


func _check_flight() -> void:
	_launch()
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	for npc_id: String in ["npc_earth_transport", "npc_earth_courier", "npc_earth_pirate", "npc_earth_patrol"]:
		var model: Node3D = view.get_node("%NPCView").get_node(npc_id + "/ShipModel")
		_check(model.role == Models.npc_role(DataLoader.get_record(npc_id)), "The actual system map chooses the expected ship class")
	var start: Vector2 = Motion.point(GameState.state["flight"]["pos"])
	EffectApplier.set_flight_target(start + Vector2(500, 0))
	view._on_boost(true)
	for _step: int in range(12):
		EffectApplier.advance_flight(0.035, true)
		await _frames()
	var player: Node3D = view._player.get_node("ShipModel")
	_check(player.get_node("EngineTrail").visible and player._boost, "Moving on boost creates a visible trail and longer exhaust")
	await _capture("flight-boost")
	var saved: Dictionary = GameState.serialize()
	await get_tree().create_timer(0.1).timeout
	_check(GameState.serialize() == saved, "Rendering exhaust and trails never consumes extra fuel or advances simulation")
	view.get_node("%Space").get_node("SpaceEffects").show_effect("destroyed", Motion.point(saved["flight"]["pos"]) + Vector2(30, 30), "")
	await get_tree().create_timer(0.08).timeout
	await _capture("flight-explosion")
	await get_tree().create_timer(0.8).timeout
	_check(view.get_node("%Space/SpaceEffects").get_child_count() == 0, "Transient flight effects release their geometry")
	_check(GameState.restore(saved) == OK and not player.get_node("EngineTrail").visible, "Loading clears old player trails")
	for kind: String in ["station", "gate"]:
		for object: Dictionary in DataLoader.get_record("sys_earth")["objects"]:
			if object["type"] != kind:
				continue
			GameState.state["flight"]["pos"] = Motion.coordinates(Motion.point(object["pos"]) + Vector2(90, 80))
			GameState.state["flight"]["target"] = GameState.state["flight"]["pos"].duplicate()
			view._refresh_world()
			view.get_node("%Camera").size = 20
			await _frames()
			await _capture("system-" + kind)
			break
	view.queue_free()
	await _frames()


func _check_combat() -> void:
	_launch()
	GameState.state["combat"] = State.initial("pirate_light", "npc_earth_pirate")
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await _frames()
	var board: Node3D = view.find_child("Board", true, false)
	var model: Node3D = board.get_node("EnemyShip/ShipModel")
	_check(model.role == "pirate" and model.variant == absi("npc_earth_pirate".hash()) % 2, "Combat preserves the same NPC faction and visual variant")
	var snapshot: Dictionary = GameState.serialize()
	var player: Node3D = board.get_node("PlayerShip")
	view.find_child("Camera", true, false).size = 10
	FX.shield(board.get_node("ShotFX"), player.position + Vector3(0, 0.33, 0), 1.2)
	await get_tree().create_timer(0.08).timeout
	await _capture("combat-shield")
	var old_id: int = model.get_instance_id()
	GameState.state["combat"]["opponents"][0]["source_npc"] = "npc_earth_patrol"
	GameState.state["combat"]["opponents"][0]["enemy"] = "patrol_ship"
	board.reset_from_state()
	_check(board.get_node("EnemyShip/ShipModel").role == "patrol" and board.get_node("EnemyShip/ShipModel").get_instance_id() != old_id, "Restoring another actor profile rebuilds the visual while retaining the actor wrapper")
	GameState.state = snapshot.duplicate(true)
	board.reset_from_state()
	_check(GameState.serialize() == snapshot, "Refreshing models and shield effects leaves the combat state intact")
	view.queue_free()
	await _frames()


func _frames() -> void:
	for _frame: int in range(3):
		await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture-fleet" not in OS.get_cmdline_user_args():
		return
	var suffix: String = "-small" if "--small" in OS.get_cmdline_user_args() else ""
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/fleet-" + label + suffix + ".png") == OK, "The fleet view renders: " + label)


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
