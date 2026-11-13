extends Control

const Service = preload("res://scripts/hub_service.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/hub_widgets.gd")
const Art = preload("res://scripts/location_art.gd")
const DialogueView = preload("res://scripts/dialogue.gd")
const DialogueScene = preload("res://scenes/dialogue.tscn")
const TerminalScene = preload("res://scenes/order_terminal.tscn")
const GalaxyScene = preload("res://scenes/galaxy_map.tscn")
const Text = preload("res://scripts/ui_text.gd")
const Router = preload("res://scripts/scene_router.gd")
const DomesticScene = preload("res://scenes/domestic.tscn")
const SceneQueue = preload("res://scripts/scene_queue.gd")
const Hotspot = preload("res://scripts/hub_hotspot.gd")
const Lighting = preload("res://scripts/hub_lighting.gd")
const ComputerMenu = preload("res://scripts/computer_menu.gd")
const Refit = preload("res://scripts/ship_refit.gd")
const RelationshipsPanel = preload("res://scripts/relationships_panel.gd")

@onready var background: TextureRect = %Background
@onready var backdrop: ColorRect = %Backdrop
@onready var cards: HBoxContainer = %Locations
@onready var people: HFlowContainer = %People
@onready var location_label: Label = %LocationName
@onready var time_label: Label = %Time
@onready var wait_button: Button = %Wait
@onready var conversation: Panel = %Conversation
@onready var dialogue_content: Control = %DialogueContent
@onready var terminal: Panel = %Terminal
@onready var terminal_content: Control = %TerminalContent

var _art: Art = Art.new()
var _active_heroine_id: String = ""
var _galaxy_map: Control = null
var _domestic: Control = null
var _domestic_actions: HBoxContainer
var _hotspots: Array[Hotspot] = []
var _lighting: Lighting = Lighting.new()
var _terminal_kind: String = ""
var _refit: Refit
var _relationships: RelationshipsPanel


func _ready() -> void:
	if not DataLoader.load_errors.is_empty():
		return
	if GameState.state.is_empty():
		GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	ScheduleManager.placements_changed.connect(refresh)
	EffectApplier.location_changed.connect(_on_location_changed)
	GameState.restored.connect(_on_restored)
	EffectApplier.domestic_changed.connect(refresh)
	EffectApplier.scenes_changed.connect(_show_pending_scene)
	wait_button.pressed.connect(_on_wait_pressed)
	%CloseDialogue.pressed.connect(_close_dialogue)
	%CloseTerminal.pressed.connect(_close_terminal)
	%Inventory.pressed.connect(open_domestic.bind("inventory"))
	%Relationships.pressed.connect(open_relationships)
	%Inventory.tooltip_text = Text.get_text("ui_home_inventory")
	%Relationships.tooltip_text = Text.get_text("ui_room_relationships")
	for button: Button in [%Inventory, %Relationships]:
		button.add_theme_stylebox_override("normal", Widgets.box(Color(0.025, 0.045, 0.065, 0.9), 12, Color(0.25, 0.38, 0.43), 1))
		button.add_theme_stylebox_override("hover", Widgets.box(Color(0.08, 0.17, 0.21, 0.95), 12, Color(0.45, 0.85, 0.8), 2))
		button.add_theme_stylebox_override("pressed", Widgets.box(Color(0.04, 0.1, 0.14), 12))
	%Navigation.add_theme_stylebox_override("panel", Widgets.box(Color.TRANSPARENT, 18))
	%LocationPanel.add_theme_stylebox_override("panel", Widgets.box(Color(0.025, 0.045, 0.07, 0.9), 18))
	get_node("ClockPanel").add_theme_stylebox_override("panel", Widgets.box(Color(0.025, 0.045, 0.07, 0.9), 18))
	conversation.add_theme_stylebox_override("panel", Widgets.box(Color(0.025, 0.045, 0.07, 0.98), 18))
	terminal.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_domestic_actions = HBoxContainer.new()
	_domestic_actions.name = "DomesticActions"
	get_node("LocationPanel/Margin/Column").add_child(_domestic_actions)
	_add_hotspot("KitchenHotspot", "hub_kitchen_hotspot", "ui_hub_start_cooking", open_domestic.bind("kitchen"))
	_add_hotspot("OfficeHotspot", "hub_office_hotspot", "ui_hub_office_computer", open_order_terminal)
	_add_hotspot("TechHotspot", "hub_tech_hotspot", "ui_hub_tech_computer", open_flight_terminal)
	_add_hotspot("ShipHotspot", "hub_ship_hotspot", "ui_refit_open", open_ship_refit)
	refresh()
	if not GameState.state.get("kitchen", {}).is_empty():
		open_domestic("kitchen")
	if Conditions.can_fly():
		get_tree().call_deferred("change_scene_to_file", Router.current_path())


func refresh() -> void:
	%RoomActions.visible = Conditions.can_use_room_panels()
	if _relationships != null and not Conditions.can_use_room_panels():
		_close_relationships()
	if _refit != null and not Conditions.can_modify_ship():
		_close_refit.call_deferred()
	var location_id: String = str(GameState.state.get("location", ""))
	var location: Dictionary = DataLoader.get_record(location_id)
	background.texture = _art.background_for(location, Clock.current_slot())
	background.visible = background.texture != null
	backdrop.color = Widgets.identity_color(location_id).darkened(0.7)
	var lighting_slot: String = "day" if location.get("area") == "ship" else Clock.current_slot()
	background.material = _lighting.material_for(location_id, lighting_slot)
	backdrop.material = background.material
	for hotspot: Hotspot in _hotspots:
		hotspot.refresh()
	location_label.text = str(location.get("name", location_id))
	time_label.text = "%02d / %s" % [Clock.current_day(), Clock.current_slot()]
	wait_button.text = ""
	for action: String in location.get("actions", []):
		if action == "wait":
			wait_button.text = action
	wait_button.disabled = not Conditions.can_wait()
	if is_instance_valid(_domestic_actions):
		_clear(_domestic_actions)
		if Conditions.is_inside_ship():
			var return_button: Button = Button.new()
			return_button.name = "ReturnToFlight"
			return_button.text = Text.get_text("ui_ship_return_to_flight")
			return_button.custom_minimum_size.y = 38
			return_button.disabled = not Conditions.can_leave_ship()
			return_button.pressed.connect(_return_to_flight)
			_domestic_actions.add_child(return_button)
		if Conditions.can_open_domestic("shop") and "shop" in location.get("actions", []):
			var button: Button = Button.new()
			button.name = "shop"
			button.text = Text.get_text("ui_home_shop")
			button.custom_minimum_size.y = 38
			button.pressed.connect(open_domestic.bind("shop"))
			_domestic_actions.add_child(button)
	_clear(cards)
	for target: Dictionary in DataLoader.get_records("locations"):
		if target.get("area") == location.get("area"):
			cards.add_child(_location_card(target))
	%RoomNavigation.sync(location_id)
	_clear(people)
	for heroine_id: String in Service.occupants(location_id):
		people.add_child(_person_button(heroine_id))
	if not _active_heroine_id.is_empty() and not Conditions.is_present(_active_heroine_id):
		_close_dialogue.call_deferred()
	var terminal_available: bool = Conditions.can_use_order_terminal() if _terminal_kind == "orders" else Conditions.can_launch()
	if terminal.visible and not terminal_available:
		_close_terminal.call_deferred()
	_show_pending_scene.call_deferred()


func _add_hotspot(node_name: String, layout_id: String, text_id: String, callback: Callable) -> void:
	var hotspot: Hotspot = Hotspot.new()
	hotspot.name = node_name
	hotspot.layout_id = layout_id
	hotspot.text_id = text_id
	hotspot.background = background
	hotspot.activated.connect(callback)
	add_child(hotspot)
	move_child(hotspot, %Navigation.get_index())
	hotspot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hotspots.append(hotspot)


func open_dialogue(heroine_id: String) -> bool:
	if not Conditions.can_open_conversation(heroine_id):
		return false
	_close_relationships()
	var scenes: Array[Dictionary] = Service.dialogues_for(heroine_id)
	_close_terminal()
	_close_dialogue()
	var view: DialogueView = DialogueScene.instantiate()
	view.configure_for_hub(heroine_id)
	view.choice_resolved.connect(_on_choice_resolved)
	dialogue_content.add_child(view)
	_active_heroine_id = heroine_id
	conversation.show()
	var pending: String = Conditions.next_pending_scene()
	if not pending.is_empty() and SceneQueue.heroine(DataLoader.get_record(pending)) == heroine_id:
		view.select_scene(pending)
	elif not scenes.is_empty():
		view.select_scene(str(scenes[0]["id"]))
	return true


func _show_pending_scene() -> void:
	if not is_inside_tree() or not is_node_ready() or conversation.visible or terminal.visible or _domestic != null or _galaxy_map != null or _refit != null or _relationships != null:
		return
	var scene_id: String = Conditions.next_pending_scene()
	if not scene_id.is_empty():
		open_dialogue(SceneQueue.heroine(DataLoader.get_record(scene_id)))


func open_order_terminal() -> bool:
	if not Conditions.can_use_order_terminal():
		return false
	_close_relationships()
	_close_dialogue()
	_close_terminal()
	_terminal_kind = "orders"
	terminal_content.add_child(TerminalScene.instantiate())
	terminal.show()
	%LocationPanel.hide()
	return true


func open_flight_terminal() -> bool:
	if not Conditions.can_launch():
		return false
	_close_relationships()
	_close_dialogue()
	_close_terminal()
	_terminal_kind = "flight"
	var menu: ComputerMenu = ComputerMenu.new()
	menu.name = "ComputerMenu"
	menu.map_requested.connect(open_galaxy_map)
	menu.flight_requested.connect(_launch_flight)
	terminal_content.add_child(menu)
	terminal.show()
	%LocationPanel.hide()
	return true


func open_galaxy_map() -> bool:
	if not Conditions.can_use_galaxy_map():
		return false
	_close_relationships()
	_close_dialogue()
	_close_terminal()
	if _galaxy_map == null:
		_galaxy_map = GalaxyScene.instantiate()
		_galaxy_map.close_requested.connect(_close_galaxy_map)
		_galaxy_map.flight_requested.connect(_launch_flight)
		add_child(_galaxy_map)
		_galaxy_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return true


func open_ship_refit() -> bool:
	if not Conditions.can_modify_ship():
		return false
	_close_relationships()
	_close_dialogue()
	_close_terminal()
	if _refit == null:
		_refit = Refit.new()
		_refit.name = "ShipRefit"
		_refit.closed.connect(_close_refit)
		add_child(_refit)
	return true


func _close_refit() -> void:
	if _refit != null:
		remove_child(_refit)
		_refit.queue_free()
		_refit = null


func open_relationships() -> bool:
	if not Conditions.can_use_room_panels():
		return false
	_close_dialogue()
	_close_terminal()
	_close_domestic()
	if _relationships == null:
		_relationships = RelationshipsPanel.new()
		_relationships.name = "RelationshipsPanel"
		_relationships.closed.connect(_close_relationships)
		add_child(_relationships)
	return true


func _close_relationships() -> void:
	if _relationships != null:
		remove_child(_relationships)
		_relationships.queue_free()
		_relationships = null


func open_domestic(tab_id: String) -> bool:
	if not Conditions.can_open_domestic(tab_id):
		return false
	_close_relationships()
	_close_dialogue()
	_close_terminal()
	if _domestic == null:
		_domestic = DomesticScene.instantiate()
		_domestic.tab = tab_id
		_domestic.close_requested.connect(_close_domestic)
		add_child(_domestic)
		_domestic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return true


func _close_domestic() -> void:
	if _domestic != null:
		remove_child(_domestic)
		_domestic.queue_free()
		_domestic = null
	refresh()


func _launch_flight() -> void:
	if EffectApplier.launch_flight() == OK:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/system_flight.tscn")


func _return_to_flight() -> void:
	if EffectApplier.leave_ship() == OK:
		get_tree().call_deferred("change_scene_to_file", Router.current_path())


func _close_galaxy_map() -> void:
	if not Conditions.can_return_to_hub() or _galaxy_map == null:
		return
	remove_child(_galaxy_map)
	_galaxy_map.queue_free()
	_galaxy_map = null
	refresh()


func _location_card(location: Dictionary) -> VBoxContainer:
	var location_id: String = str(location["id"])
	var card: VBoxContainer = VBoxContainer.new()
	card.name = location_id
	card.custom_minimum_size.x = Widgets.CARD_SIZE
	card.add_theme_constant_override("separation", 6)
	var button: Button = Button.new()
	button.name = "Travel"
	button.custom_minimum_size = Vector2(Widgets.CARD_SIZE, Widgets.CARD_SIZE)
	button.disabled = not Conditions.can_enter(location_id)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = str(location.get("name", location_id))
	var selected: bool = location_id == GameState.state.get("location")
	var closed: bool = not Conditions.location_is_open(location_id)
	button.disabled = button.disabled or closed
	var width: int = 6 if selected else 5
	button.add_theme_stylebox_override("normal", Widgets.box(Color.TRANSPARENT, 14, Color.BLACK, width))
	button.add_theme_stylebox_override("hover", Widgets.box(Color(0.1, 0.2, 0.2, 0.1), 14, Color.BLACK, 6))
	button.add_theme_stylebox_override("pressed", Widgets.box(Color(0.15, 0.3, 0.3, 0.15), 14, Color.BLACK, 6))
	button.add_theme_stylebox_override("focus", Widgets.box(Color.TRANSPARENT, 14, Color.BLACK, 6))
	button.add_theme_stylebox_override("disabled", Widgets.box(Color.TRANSPARENT, 14, Color.BLACK, width))
	button.modulate.a = 0.4 if button.disabled else 1.0
	if closed:
		button.modulate.a = 0.75
	button.pressed.connect(_on_travel_pressed.bind(location_id))
	card.add_child(button)
	var texture: Texture2D = _art.background_for(location, Clock.current_slot())
	if texture != null:
		var thumbnail: Panel = Panel.new()
		thumbnail.name = "Thumbnail"
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumbnail.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		thumbnail.add_theme_stylebox_override("panel", Widgets.box(Color.WHITE, 14))
		button.add_child(thumbnail)
		thumbnail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var image: TextureRect = TextureRect.new()
		image.name = "Image"
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.material = _lighting.material_for(location_id, "day", closed)
		thumbnail.add_child(image)
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var symbol: Label = Label.new()
		symbol.add_theme_color_override("font_outline_color", Color.BLACK)
		symbol.add_theme_constant_override("outline_size", 4)
		symbol.text = location_id.trim_prefix("hub_").trim_prefix("ship_")
		symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(symbol)
		symbol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame: Panel = Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", Widgets.box(Color.TRANSPARENT, 14, Color.BLACK, width))
	button.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if closed:
		var shade: Panel = Panel.new()
		shade.name = "ClosedShade"
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.add_theme_stylebox_override("panel", Widgets.box(Color(0.15, 0.15, 0.15, 0.75), 14, Color.BLACK, width))
		button.add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var notice: Label = Label.new()
		notice.name = "Closed"
		notice.text = Text.get_text("ui_hub_closed")
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		notice.add_theme_font_size_override("font_size", 14)
		notice.add_theme_color_override("font_color", Color.WHITE)
		notice.add_theme_color_override("font_outline_color", Color.BLACK)
		notice.add_theme_constant_override("outline_size", 3)
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.add_child(notice)
		notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var occupants_row: HBoxContainer = HBoxContainer.new()
	occupants_row.name = "Occupants"
	occupants_row.alignment = BoxContainer.ALIGNMENT_CENTER
	occupants_row.custom_minimum_size.y = 24.0
	occupants_row.add_theme_constant_override("separation", 4)
	card.add_child(occupants_row)
	for heroine_id: String in Service.occupants(location_id):
		occupants_row.add_child(Widgets.avatar(heroine_id))
	var label: Label = Label.new()
	label.text = str(location.get("name", location_id))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.9) if selected else Color(0.9, 0.93, 0.96))
	label.custom_minimum_size.x = Widgets.CARD_SIZE
	label.custom_minimum_size.y = 34.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)
	return card


func _person_button(heroine_id: String) -> Button:
	var blueprint: Dictionary = DataLoader.get_record(heroine_id)
	var button: Button = Button.new()
	button.name = heroine_id
	button.custom_minimum_size = Vector2(140, 52)
	button.tooltip_text = str(blueprint.get("name", heroine_id))
	button.disabled = not Conditions.can_open_conversation(heroine_id)
	button.modulate.a = 0.65 if button.disabled else 1.0
	button.add_theme_stylebox_override("normal", Widgets.box(Color(0.09, 0.14, 0.18), 12))
	button.add_theme_stylebox_override("hover", Widgets.box(Color(0.12, 0.24, 0.28), 12))
	button.add_theme_stylebox_override("disabled", Widgets.box(Color(0.06, 0.09, 0.12), 12))
	button.pressed.connect(open_dialogue.bind(heroine_id))
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	var icon: PanelContainer = Widgets.avatar(heroine_id, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label: Label = Label.new()
	label.text = str(blueprint.get("name", heroine_id))
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return button


func _on_travel_pressed(location_id: String) -> void:
	_close_dialogue()
	_close_terminal()
	if Service.travel(location_id) != OK:
		refresh()


func _on_wait_pressed() -> void:
	_close_dialogue()
	if Service.wait() != OK:
		refresh()


func _on_location_changed(_location_id: String) -> void:
	refresh()


func _on_restored() -> void:
	_close_relationships()
	_close_refit()
	_close_domestic()
	_close_dialogue()
	_close_terminal()
	refresh()
	if Conditions.can_fly():
		get_tree().call_deferred("change_scene_to_file", Router.current_path())
	elif not GameState.state.get("kitchen", {}).is_empty():
		open_domestic("kitchen")


func _on_choice_resolved(_scene_id: String, _result: Error) -> void:
	_close_dialogue.call_deferred()
	_show_pending_scene.call_deferred()


func _close_dialogue() -> void:
	_active_heroine_id = ""
	conversation.hide()
	_clear(dialogue_content)


func _close_terminal() -> void:
	terminal.hide()
	_terminal_kind = ""
	%LocationPanel.show()
	_clear(terminal_content)


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
