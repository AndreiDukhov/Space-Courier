extends Control

const Math = preload("res://scripts/combat_math.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Board = preload("res://scripts/combat_board.gd")
const Text = preload("res://scripts/ui_text.gd")
const Router = preload("res://scripts/scene_router.gd")
const Camera = preload("res://scripts/combat_camera.gd")
const Card = preload("res://scripts/combat_card.gd")
const Vitals = preload("res://scripts/combat_vitals.gd")
const Backdrop = preload("res://scripts/space_backdrop.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Icon = preload("res://scripts/combat_icon.gd")

var _board: Node3D
var _camera: Camera3D
var _viewport: SubViewport
var _space: SubViewportContainer
var _title: Label
var _ap_value: Label
var _mp_value: Label
var _points: VBoxContainer
var _notice: Label
var _result: Label
var _target_info: Label
var _actions: ScrollContainer
var _weapons: Dictionary = {}
var _weapon_id: String = ""
var _hovered: Vector2i = Vector2i(-1, -1)
var _buttons: Dictionary = {}
var _abilities: Dictionary = {}
var _moving: bool = true
var _leaving: bool = false
var _shot_stamp: String = ""
var _camera_transform: Transform3D = Transform3D.IDENTITY
var _camera_zoom: float = -1.0


func _ready() -> void:
	if not DataLoader.load_errors.is_empty():
		return
	if not Conditions.has_combat():
		_route()
		return
	_build_view()
	_board.motion_changed.connect(refresh)
	EffectApplier.combat_changed.connect(refresh)
	GameState.restored.connect(_on_restored)
	PauseMenu.opened.connect(_camera.stop_tracking)
	refresh()
	_resize_camera.call_deferred()


func _build_view() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.025, 0.04, 0.07)
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_space(self)
	_space.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = _label(self, "Title", 22)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 4)
	_points = VBoxContainer.new()
	_points.name = "Points"
	_points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_points)
	for kind: String in ["ap", "movement"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_points.add_child(row)
		var icon: Icon = Icon.new()
		icon.kind = kind
		icon.custom_minimum_size = Vector2(26, 26)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var value: Label = _label(row, "AP" if kind == "ap" else "MP", 18)
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		value.tooltip_text = Text.get_text("ui_combat_ap_hint" if kind == "ap" else "ui_combat_mp_hint")
		value.add_theme_color_override("font_outline_color", Color.BLACK)
		value.add_theme_constant_override("outline_size", 4)
		if kind == "ap":
			_ap_value = value
		else:
			_mp_value = value
	_result = _label(self, "Result", 18)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_info = _label(self, "TargetInfo", 12)
	_target_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_target_info.add_theme_constant_override("outline_size", 3)
	_notice = _label(self, "Notice", 13)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_outline_color", Color.BLACK)
	_notice.add_theme_constant_override("outline_size", 3)
	_build_actions(self)
	_button(self, "Continue", "ui_combat_continue", _finish)
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	_title.position = Vector2(22, 18)
	_points.position = Vector2(size.x - 112, 18)
	_target_info.position = Vector2(22, 54)
	_target_info.size = Vector2(390, 40)
	_notice.position = Vector2(size.x * 0.2, size.y - 180)
	_notice.size = Vector2(size.x * 0.6, 28)
	_result.position = Vector2(size.x * 0.2, size.y * 0.42)
	_result.size = Vector2(size.x * 0.6, 76)
	_buttons["Continue"].position = Vector2(size.x * 0.5 - 110, size.y * 0.55)
	_buttons["Continue"].size = Vector2(220, 42)


func _build_actions(parent: Control) -> void:
	_actions = ScrollContainer.new()
	_actions.name = "CombatActions"
	_actions.custom_minimum_size.y = 138
	_actions.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_actions)
	_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_actions.offset_left = 16
	_actions.offset_right = -16
	_actions.offset_top = -144
	_actions.offset_bottom = -6
	var cards: HBoxContainer = HBoxContainer.new()
	cards.name = "ActionCards"
	cards.alignment = BoxContainer.ALIGNMENT_BEGIN
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 10)
	_actions.add_child(cards)
	var finish: HBoxContainer = _action_section(cards, "TurnSection", "")
	var end: Card = Card.new()
	end.name = "EndTurn"
	end.title = Text.get_text("ui_combat_end_turn")
	end.kind = "end_turn"
	end.pressed.connect(_end_turn)
	finish.add_child(end)
	_buttons["EndTurn"] = end
	var movement: HBoxContainer = _action_section(cards, "MovementSection", "")
	var move: Card = Card.new()
	move.name = "Move"
	move.title = Text.get_text("ui_combat_move")
	move.kind = "movement"
	move.tooltip_text = Text.get_text("ui_combat_move_hint")
	move.pressed.connect(_select_move)
	movement.add_child(move)
	_buttons["Move"] = move
	var weapons: HBoxContainer = _action_section(cards, "WeaponsSection", "ui_combat_weapons")
	for weapon: Dictionary in Math.player_weapons():
		var card: Card = Card.new()
		card.name = "Weapon_" + str(weapon["id"])
		card.title = str(weapon["name"])
		card.kind = str(weapon["mount"])
		card.pressed.connect(_select_weapon.bind(str(weapon["id"])))
		weapons.add_child(card)
		_weapons[weapon["id"]] = card
	var abilities: HBoxContainer = _action_section(cards, "AbilitiesSection", "ui_combat_abilities")
	for ability: Dictionary in DataLoader.get_records("abilities"):
		if ability["effect"].has("self_evasion"):
			continue
		var card: Card = Card.new()
		card.name = str(ability["id"])
		card.title = str(ability["name"])
		card.kind = "evasion"
		if ability["effect"].has("move_points"):
			card.kind = "burn"
		elif ability["effect"].has("shield_restore"):
			card.kind = "shield"
		card.pressed.connect(_use_ability.bind(str(ability["id"])))
		abilities.add_child(card)
		_abilities[ability["id"]] = card


func _action_section(parent: HBoxContainer, node_name: String, text_id: String) -> HBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.025, 0.045, 0.065), 12, Color(0.18, 0.3, 0.38), 1))
	if text_id.is_empty():
		panel.size_flags_vertical = Control.SIZE_SHRINK_END
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 8)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	if not text_id.is_empty():
		var heading: Label = _label(column, "Heading", 14)
		heading.text = Text.get_text(text_id)
		heading.add_theme_color_override("font_color", Color(0.65, 0.85, 0.9))
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Cards"
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	return row


func _build_space(parent: Control) -> void:
	_space = SubViewportContainer.new()
	_space.name = "SpaceContainer"
	_space.stretch = true
	_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_space.custom_minimum_size = Vector2.ZERO
	parent.add_child(_space)
	_space.add_child(Backdrop.new())
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_space.add_child(_viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.background_color = Color(0.015, 0.025, 0.05)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.75, 0.9)
	environment.environment.ambient_light_energy = 0.6
	_viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.set_script(Camera)
	_viewport.add_child(_camera)
	_camera.current = true
	_board = Node3D.new()
	_board.name = "Board"
	_board.set_script(Board)
	_viewport.add_child(_board)
	_camera.target = _board.get_node("PlayerShip")
	SoundSystem.attach_listener(_viewport, _board.get_node("PlayerShip"))
	_camera.center_on_player()
	var vitals: Vitals = Vitals.new()
	vitals.name = "Vitals"
	vitals.camera = _camera
	vitals.board = _board
	_space.add_child(vitals)
	vitals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_space.gui_input.connect(_on_space_input)
	_space.mouse_exited.connect(_camera.stop_tracking)
	_viewport.size_changed.connect(_resize_camera)


func refresh() -> void:
	if not is_node_ready() or _board == null:
		return
	if not Conditions.has_combat():
		_route()
		return
	var combat: Dictionary = GameState.state["combat"]
	for button_id: String in _buttons:
		if button_id != "Continue":
			_buttons[button_id].visible = combat["result"] == "active"
	_title.text = Text.get_text("ui_combat_title", {"round": combat["round"]})
	_ap_value.text = Text.get_text("ui_combat_ap_value", {"value": combat["ap"]})
	_mp_value.text = Text.get_text("ui_combat_mp_value", {"value": combat["move_points"]})
	_actions.visible = combat["result"] == "active"
	_target_info.visible = combat["result"] == "active"
	var busy: bool = _board.is_animating()
	_buttons["Move"].disabled = busy or not Conditions.can_act_combat() or combat["move_points"] <= 0
	for weapon_id: String in _weapons:
		var weapon: Dictionary = DataLoader.get_record(weapon_id)
		var fired: bool = Conditions.weapon_has_fired("player", weapon_id)
		_weapons[weapon_id].tooltip_text = _weapon_tooltip(weapon, fired)
		_weapons[weapon_id].disabled = busy or fired or not Conditions.can_act_combat() or int(combat["ap"]) < int(weapon["ap_cost"])
		_weapons[weapon_id].set_selected(_weapon_id == weapon_id and not _moving)
	_buttons["EndTurn"].disabled = busy or not Conditions.can_act_combat()
	_buttons["EndTurn"].set_attention(not busy and combat["result"] == "active" and int(combat["ap"]) == 0 and int(combat["move_points"]) == 0)
	_buttons["Continue"].visible = Conditions.can_finish_combat()
	_buttons["Continue"].disabled = busy
	_buttons["Move"].set_selected(_moving)
	for ability_id: String in _abilities:
		var ability: Dictionary = DataLoader.get_record(ability_id)
		_abilities[ability_id].disabled = busy or not Conditions.can_use_combat_ability(ability_id)
		_abilities[ability_id].set_selected(false)
		_abilities[ability_id].tooltip_text = _ability_tooltip(ability)
	_result.text = ""
	if combat["result"] == "victory":
		_result.text = Text.get_text("ui_combat_victory", combat["loot"])
	elif combat["result"] == "defeat":
		_result.text = Text.get_text("ui_combat_defeat")
	_result.visible = combat["result"] != "active"
	_refresh_target()
	_refresh_notice()
	_board.refresh(_moving, DataLoader.get_record(_weapon_id) if not _moving else {}, _hovered)


func _on_space_input(event: InputEvent) -> void:
	if _camera.handle_input(event):
		_space.accept_event()
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_hovered = _cell_at(event.position)
		_refresh_target()
		_board.refresh(_moving, DataLoader.get_record(_weapon_id) if not _moving else {}, _hovered)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _board.is_animating():
			if _moving:
				EffectApplier.move_combat(_hovered)
			else:
				EffectApplier.shoot_combat(_weapon_id, _hovered)
		_space.accept_event()


func _weapon_tooltip(weapon: Dictionary, fired: bool) -> String:
	var values: Dictionary = {
		"name": weapon["name"],
		"mount": Text.get_text("ui_tactical_mount_" + str(weapon["mount"])),
		"type": Text.get_text("ui_tactical_type_" + str(weapon["type"])),
		"min": int(weapon["dmg"][0]), "max": int(weapon["dmg"][1]),
		"range": int(weapon["range"]), "arc": int(weapon["arc_degrees"]),
		"critical": roundi(float(weapon["critical"]["chance"]) * 100),
		"ap": int(weapon["ap_cost"]),
		"status": Text.get_text("ui_combat_gun_fired" if fired else "ui_combat_gun_ready")
	}
	return Text.get_text("ui_tactical_weapon_tip", values)



func _ability_tooltip(ability: Dictionary) -> String:
	var effect: Dictionary = ability["effect"]
	var description: String
	if effect.has("shield_restore"):
		description = Text.get_text("ui_tactical_recharge", {"amount": int(effect["shield_restore"]), "delay": int(effect["delay"])})
	elif effect.has("move_points"):
		description = Text.get_text("ui_combat_burn", {"move": ceili(float(effect["move_points"]) * Math.mood_multiplier(ability)), "fuel": effect["fuel"]})
	else:
		description = Text.get_text("ui_combat_evasion", {"value": roundi(float(effect["self_evasion"]) * Math.mood_multiplier(ability) * 100.0)})
	var cost: String = str(Math.ability_ap_cost(ability))
	if ability["cost_ap"] is String and ability["cost_ap"] == "all":
		cost = Text.get_text("ui_tactical_all_ap")
	var tooltip: String = Text.get_text("ui_tactical_ability_tip", {"name": ability["name"], "description": description, "ap": cost, "cooldown": GameState.state["combat"]["cooldowns"][ability["id"]]})
	if effect.has("shield_restore") and not GameState.state["combat"]["shield_recharge"].is_empty():
		tooltip += "\n" + Text.get_text("ui_tactical_pending", {"round": GameState.state["combat"]["shield_recharge"]["round"]})
	return tooltip



func _process(_delta: float) -> void:
	if _camera == null or _board == null or (_camera_transform == _camera.transform and _camera_zoom == _camera.size):
		return
	_camera_transform = _camera.transform
	_camera_zoom = _camera.size
	var pointer: Vector2 = _camera.pointer_position()
	if Rect2(Vector2.ZERO, _space.size).has_point(pointer):
		_hovered = _cell_at(pointer)
		_refresh_target()
		_board.refresh(_moving, DataLoader.get_record(_weapon_id) if not _moving else {}, _hovered)


func _cell_at(position: Vector2) -> Vector2i:
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(_camera.project_ray_origin(position), _camera.project_ray_normal(position))
	if intersection is Vector3:
		return Vector2i(floori(intersection.x + float(Math.WIDTH) / 2.0), floori(intersection.z + float(Math.HEIGHT) / 2.0))
	return Vector2i(-1, -1)


func _resize_camera() -> void:
	_camera.configure(Vector2(_viewport.size), Vector2(Math.WIDTH, Math.HEIGHT) / 2.0)


func _select_move() -> void:
	_moving = true
	_weapon_id = ""
	refresh()


func _select_weapon(weapon_id: String) -> void:
	_weapon_id = weapon_id
	_moving = false
	refresh()


func _refresh_target() -> void:
	if not Conditions.has_combat() or _target_info == null:
		return
	if _board.is_animating() or _moving or Conditions.weapon_has_fired("player", _weapon_id) or not Math.inside(_hovered) or not Conditions.can_shoot_combat(_weapon_id, _hovered):
		_target_info.text = ""
	else:
		var weapon: Dictionary = DataLoader.get_record(_weapon_id)
		var chance: float = Math.shot_chance(GameState.state["combat"]["player"], _hovered, weapon, true)
		_target_info.text = Text.get_text("ui_combat_target", {"x": _hovered.x + 1, "z": _hovered.y + 1, "chance": roundi(chance * 100), "critical": roundi(float(weapon["critical"]["chance"]) * 100)})


func _refresh_notice() -> void:
	var shot: Dictionary = GameState.state.get("combat", {}).get("last_shot", {})
	var stamp: String = JSON.stringify(shot) + str(GameState.state.get("combat", {}).get("ap", 0)) + str(GameState.state.get("combat", {}).get("round", 0))
	if not shot.is_empty() and stamp != _shot_stamp:
		_shot_stamp = stamp
		_notice.text = Text.get_text("ui_combat_shot_" + str(shot["result"]), {"damage": String.num(float(shot["damage"]), 2), "weapon": DataLoader.get_record(str(shot["weapon"]))["name"]})


func _input(event: InputEvent) -> void:
	if _camera != null and event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		_camera.stop_tracking()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _camera != null:
		_camera.stop_tracking()


func _use_ability(ability_id: String) -> void:
	EffectApplier.use_combat_ability(ability_id)


func _end_turn() -> void:
	if not _board.is_animating():
		EffectApplier.end_combat_turn()


func _finish() -> void:
	if not _board.is_animating():
		EffectApplier.finish_combat()


func _on_restored() -> void:
	_board.reset_from_state()
	_camera.center_on_player()
	_shot_stamp = ""
	_notice.text = ""
	refresh()


func _route() -> void:
	if not _leaving and get_tree().current_scene == self:
		_leaving = true
		get_tree().call_deferred("change_scene_to_file", Router.current_path())


func _label(parent: Control, node_name: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Control, node_name: String, text_id: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = Text.get_text(text_id) if not text_id.is_empty() else ""
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons[node_name] = button
	return button
