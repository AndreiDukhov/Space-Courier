extends Control

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Art = preload("res://scripts/flight_art.gd")
const Text = preload("res://scripts/ui_text.gd")
const MapScene = preload("res://scenes/galaxy_map.tscn")
const Router = preload("res://scripts/scene_router.gd")
const Indicators = preload("res://scripts/offscreen_indicators.gd")
const Interactions = preload("res://scripts/object_interactions.gd")
const PlanetPanel = preload("res://scripts/planet_panel.gd")
const SpaceEffects = preload("res://scripts/space_effects.gd")
const QuestButton = preload("res://scripts/quest_button.gd")
const Backdrop = preload("res://scripts/space_backdrop.gd")

@onready var space: Node3D = %Space
@onready var camera: Camera3D = %Camera
@onready var viewport: SubViewport = %Viewport

var _player: Node3D = Node3D.new()
var _map: Control = null
var _boost: bool = false
var _following_mouse: bool = false
var _leaving: bool = false
var _planet_panel: PlanetPanel = null
var _interactions: Interactions
var _indicators: Indicators
var _status: Label
var _flash: ColorRect
var _flash_tween: Tween
var _journal: QuestButton


func _ready() -> void:
	if not DataLoader.load_errors.is_empty():
		return
	if GameState.state.is_empty():
		GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	if Conditions.can_launch():
		EffectApplier.launch_flight()
	%SpaceContainer.add_child(Backdrop.new())
	_player.add_child(Art.ship(Color(0.15, 0.95, 0.85)))
	var marker: TorusMesh = TorusMesh.new()
	marker.inner_radius = 0.7
	marker.outer_radius = 0.9
	var marker_view: MeshInstance3D = MeshInstance3D.new()
	marker_view.mesh = marker
	marker_view.material_override = Art.material(Color(0.15, 0.95, 0.85), true)
	_player.add_child(marker_view)
	space.add_child(_player)
	space.add_child(SpaceEffects.new())
	_interactions = Interactions.new()
	_interactions.name = "ObjectInteractions"
	_interactions.camera = camera
	_interactions.planet_requested.connect(_open_planet)
	_interactions.gate_requested.connect(_jump)
	_interactions.npc_requested.connect(_interact_npc)
	_interactions.delivery_requested.connect(_deliver_order)
	%SpaceContainer.add_child(_interactions)
	_interactions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_indicators = Indicators.new()
	_indicators.name = "Indicators"
	_indicators.camera = camera
	%SpaceContainer.add_child(_indicators)
	_indicators.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1.0, 0.1, 0.0, 0.0)
	%SpaceContainer.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_journal = QuestButton.new()
	_journal.name = "QuestButton"
	_journal.host = self
	_journal.opened.connect(func() -> void: _following_mouse = false)
	%SpaceContainer.add_child(_journal)
	_journal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status = Label.new()
	_status.name = "SpaceStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3))
	%Help.get_parent().add_child(_status)
	EffectApplier.flight_changed.connect(_sync_flight)
	EffectApplier.galaxy_changed.connect(_refresh_world)
	EffectApplier.combat_changed.connect(_on_combat_changed)
	EffectApplier.orders_changed.connect(_refresh_world)
	EffectApplier.space_effect.connect(_on_space_effect)
	EffectApplier.location_changed.connect(_on_location_changed)
	GameState.restored.connect(_on_restored)
	%SpaceContainer.gui_input.connect(_on_space_input)
	viewport.size_changed.connect(_resize_camera)
	%Pause.pressed.connect(_pause)
	%Map.pressed.connect(open_map)
	%Ship.pressed.connect(_visit_ship)
	%Boost.toggled.connect(_on_boost)
	%Save.pressed.connect(_save)
	%Load.pressed.connect(_load)
	%Map.text = Text.get_text("ui_map_open")
	%Ship.text = Text.get_text("ui_flight_visit_ship")
	%Ship.tooltip_text = Text.get_text("ui_flight_visit_ship_hint")
	%Help.text = Text.get_text("ui_flight_help")
	%Boost.text = Text.get_text("ui_map_boost")
	%Save.text = Text.get_text("ui_map_save")
	%Load.text = Text.get_text("ui_map_load")
	_refresh_world()
	_resize_camera.call_deferred()
	_on_combat_changed.call_deferred()


func _physics_process(delta: float) -> void:
	if not _leaving and _map == null and _planet_panel == null and (_journal == null or not _journal.is_open()):
		EffectApplier.advance_flight(delta, _boost)


func _refresh_world() -> void:
	if not is_node_ready():
		return
	_following_mouse = false
	var system_id: String = str(GameState.state["current_system"])
	var names: Dictionary = {}
	var number: int = 0
	for object: Dictionary in DataLoader.get_record(system_id)["objects"]:
		if object["type"] == "gate":
			number += 1
			var route_id: String = str(object["to_route"])
			names[route_id] = gate_name(route_id, number)
	%SystemSpace.rebuild(system_id, names)
	%NPCView.rebuild(system_id)
	_indicators.rebuild()
	%Title.text = Text.get_text("ui_flight_title", {"name": DataLoader.get_record(system_id)["name"]})
	_sync_flight()


func gate_name(route_id: String, number: int) -> String:
	if Conditions.is_destination_known(route_id):
		var route: Dictionary = DataLoader.get_record(route_id)
		return Text.get_text("ui_flight_known_gate", {"name": DataLoader.get_record(str(route["to"]))["name"]})
	return Text.get_text("ui_flight_unknown_gate", {"number": number})


func _sync_flight() -> void:
	if not is_node_ready():
		return
	var flight: Dictionary = GameState.state["flight"]
	if not flight["paused"]:
		_interactions.selected_npc = ""
	%NPCView.sync_positions()
	%EncounterLayer.visible = not flight["encounter"].is_empty()
	if %EncounterLayer.visible or flight["paused"]:
		_following_mouse = false
		if %EncounterLayer.visible and _map != null:
			_close_map()
	_player.position = Motion.world_position(flight["pos"], 2.8)
	_follow_camera()
	var direction: Vector2 = Motion.point(flight["target"]) - Motion.point(flight["pos"])
	if direction.length_squared() > 0.01:
		_player.rotation.y = atan2(direction.x, direction.y)
	%Pause.text = Text.get_text("ui_flight_resume" if flight["paused"] else "ui_flight_pause")
	%Paused.visible = flight["paused"]
	%Paused.text = Text.get_text("ui_flight_paused")
	var fuel: Dictionary = GameState.state["ship"]["fuel"]
	%Resources.text = Text.get_text("ui_flight_resources", {"day": Clock.current_day(), "fuel": String.num(float(fuel["current"]), 2), "max": fuel["max"], "hull": String.num(float(GameState.state["ship"]["hull"]["current"]), 1), "money": GameState.state["money"]})
	var status: Array[String] = []
	if Conditions.star_is_dangerous(Motion.point(flight["pos"])):
		status.append(Text.get_text("ui_space_star_damage"))
	for npc_id: String in flight["npcs"]:
		if flight["npcs"][npc_id]["target"] == "player":
			status.append(Text.get_text("ui_space_pursuit_warning"))
			break
	if not flight["autopilot"].is_empty():
		status.append(Text.get_text("ui_space_autopilot", {"name": DataLoader.get_record(str(flight["autopilot"]["destination"]))["name"]}))
	_status.text = "\n".join(status)
	%Load.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)
	%Pause.disabled = not Conditions.can_pause_flight()
	%Map.disabled = not Conditions.can_open_flight_map()
	%Ship.disabled = not Conditions.can_visit_ship()
	if _interactions != null:
		_interactions.sync()
	if _indicators != null:
		_indicators.reserved_rect = _journal.button_rect()
		_indicators.sync()


func _resize_camera() -> void:
	if viewport.size.y > 0:
		camera.size = 38.0
		_follow_camera()
		if _interactions != null:
			_interactions.sync()
		if _indicators != null:
			_indicators.reserved_rect = _journal.button_rect()
			_indicators.sync()


func _follow_camera() -> void:
	var focus: Vector3 = Vector3(_player.position.x, 0.0, _player.position.z)
	camera.position = focus + Vector3(0, 45, 16)
	camera.look_at(focus, Vector3.UP)


func _on_space_input(event: InputEvent) -> void:
	if _journal.is_open():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _map == null and _planet_panel == null:
			var npc_id: String = _interactions.pick_npc(event.position)
			if not npc_id.is_empty() and EffectApplier.pause_at_npc(npc_id) == OK:
				_following_mouse = false
				_interactions.selected_npc = npc_id
				_interactions.sync()
				%SpaceContainer.accept_event()
				return
		_following_mouse = event.pressed and _map == null and _planet_panel == null and Conditions.can_move_flight()
		if _following_mouse:
			_target_at_cursor(event.position)
		%SpaceContainer.accept_event()
	elif event is InputEventMouseMotion and _following_mouse and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_target_at_cursor(event.position)
		%SpaceContainer.accept_event()


func _target_at_cursor(position: Vector2) -> void:
	if not Rect2(Vector2.ZERO, %SpaceContainer.size).has_point(position):
		_following_mouse = false
		return
	var origin: Vector3 = camera.project_ray_origin(position)
	var ray: Vector3 = camera.project_ray_normal(position)
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, ray)
	if intersection is Vector3:
		EffectApplier.set_flight_target(Motion.data_position(intersection))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_following_mouse = false
	if event is InputEventKey and event.pressed and not event.echo and _map == null and _planet_panel == null and not _journal.is_open() and GameState.state["flight"]["encounter"].is_empty():
		if event.keycode == KEY_SPACE:
			_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			open_map()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_following_mouse = false


func _pause() -> void:
	_following_mouse = false
	EffectApplier.toggle_flight_pause()


func _visit_ship() -> void:
	if _leaving or _map != null or _planet_panel != null or _journal.is_open():
		return
	_following_mouse = false
	EffectApplier.visit_ship()


func _jump(route_id: String) -> void:
	EffectApplier.jump_route(route_id, _boost)


func _on_boost(enabled: bool) -> void:
	_boost = enabled
	_interactions.boost = enabled
	_refresh_world()


func _interact_npc(npc_id: String, trading: bool) -> void:
	if _planet_panel != null or _map != null:
		return
	if trading:
		if not Conditions.can_trade_npc(npc_id) or EffectApplier.pause_at_npc(npc_id) != OK:
			return
		_following_mouse = false
		EffectApplier.stop_autopilot()
		_planet_panel = PlanetPanel.new()
		_planet_panel.name = "NPCTrade"
		_planet_panel.npc_id = npc_id
		_planet_panel.trading = true
		_planet_panel.closed.connect(_close_planet)
		add_child(_planet_panel)
	elif Conditions.can_contact_npc(npc_id):
		EffectApplier.pause_at_npc(npc_id)
		EffectApplier.start_flight_event(str(DataLoader.get_record(npc_id)["event"]))


func _deliver_order(order_id: String) -> void:
	_following_mouse = false
	if EffectApplier.deliver_order(order_id) == OK:
		EffectApplier.stop_autopilot()
		%Notice.text = Text.get_text("ui_flight_delivered", {"name": DataLoader.get_record(order_id)["title"]})
	else:
		%Notice.text = Text.get_text("ui_flight_delivery_unavailable")


func open_map() -> void:
	if _map != null or _planet_panel != null or _journal.is_open() or not Conditions.can_open_flight_map():
		return
	_following_mouse = false
	_map = MapScene.instantiate()
	_map.close_requested.connect(_close_map)
	add_child(_map)
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _close_map() -> void:
	if _map == null:
		return
	remove_child(_map)
	_map.queue_free()
	_map = null
	_refresh_world()


func _on_restored() -> void:
	_close_planet()
	if Conditions.has_combat():
		_on_combat_changed()
	elif not Conditions.can_fly():
		get_tree().call_deferred("change_scene_to_file", Router.current_path())
	else:
		_refresh_world()


func _on_combat_changed() -> void:
	if Conditions.has_combat() and not _leaving and get_tree().current_scene == self:
		_leaving = true
		_following_mouse = false
		get_tree().call_deferred("change_scene_to_file", Router.current_path())


func _save() -> void:
	%Notice.text = Text.get_text("ui_map_saved" if GameState.save_game() == OK else "ui_map_save_error")
	_sync_flight()


func _load() -> void:
	if GameState.load_game() != OK:
		%Notice.text = Text.get_text("ui_map_save_error")
	_sync_flight()


func _open_planet(planet_id: String, trading: bool) -> void:
	if _planet_panel != null or not Conditions.can_interact_planet(planet_id):
		return
	_following_mouse = false
	EffectApplier.stop_autopilot()
	_planet_panel = PlanetPanel.new()
	_planet_panel.name = "PlanetPanel"
	_planet_panel.planet_id = planet_id
	_planet_panel.trading = trading
	_planet_panel.closed.connect(_close_planet)
	add_child(_planet_panel)


func _close_planet() -> void:
	if _planet_panel != null:
		remove_child(_planet_panel)
		_planet_panel.queue_free()
		_planet_panel = null


func _on_space_effect(kind: String, _position: Vector2, npc_id: String) -> void:
	if kind == "star_damage":
		if _flash_tween != null:
			_flash_tween.kill()
		_flash.color.a = 0.18
		_flash_tween = create_tween()
		_flash_tween.tween_property(_flash, "color:a", 0.0, 0.4)
	elif kind in ["paid", "destroyed"]:
		%Notice.text = Text.get_text("ui_space_" + kind, {"name": DataLoader.get_record(npc_id).get("name", "")})


func _on_location_changed(_location: String) -> void:
	if not Conditions.can_fly() and not _leaving and is_inside_tree() and get_tree().current_scene == self:
		_leaving = true
		get_tree().call_deferred("change_scene_to_file", Router.current_path())
