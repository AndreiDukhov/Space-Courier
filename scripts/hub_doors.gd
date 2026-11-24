extends Control

signal action_requested(door_id: String, action: String)
signal exit_requested

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const HubTheme = preload("res://scripts/hub_theme.gd")
const EXIT_TOP: float = -82.0

var background: TextureRect
var _buttons: Dictionary = {}
var _menu: PanelContainer
var _selected: String = ""
var _exit: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for door: Dictionary in DataLoader.get_record("hub_corridor_doors")["doors"]:
		var button: Button = Button.new()
		button.name = str(door["id"])
		button.tooltip_text = str(DataLoader.get_record(str(door["location"]))["name"])
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", Style.box(Color(1.0, 0.81, 0.48, 0.1), 8, Color(1.0, 0.9, 0.7, 0.4), 1))
		button.add_theme_stylebox_override("pressed", Style.box(Color(1.0, 0.81, 0.48, 0.18), 8))
		button.add_theme_stylebox_override("focus", Style.box(Color.TRANSPARENT, 8, Color(1.0, 0.9, 0.7, 0.4), 1))
		button.pressed.connect(open_menu.bind(str(door["id"])))
		add_child(button)
		_buttons[door["id"]] = button
	_exit = Button.new()
	_exit.name = "Exit"
	_exit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_exit.tooltip_text = Text.get_text("ui_bedroom_exit")
	_exit.add_theme_font_size_override("font_size", 20)
	_exit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_exit.add_theme_stylebox_override("hover", Style.box(Color(1.0, 0.81, 0.48, 0.1), 8, Color(1.0, 0.9, 0.7, 0.4), 1))
	_exit.add_theme_stylebox_override("pressed", Style.box(Color(1.0, 0.81, 0.48, 0.18), 8))
	_exit.add_theme_stylebox_override("focus", Style.box(Color.TRANSPARENT, 8, Color(1.0, 0.9, 0.7, 0.4), 1))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_exit.add_theme_color_override(state, Color("fff2da"))
	_exit.add_theme_color_override("font_outline_color", HubTheme.INK)
	_exit.add_theme_constant_override("outline_size", 4)
	add_child(_exit)
	_exit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_exit.offset_left = 370
	_exit.offset_right = -18
	_exit.offset_top = EXIT_TOP
	_exit.offset_bottom = -18
	_exit.pressed.connect(exit_requested.emit)
	_exit.mouse_entered.connect(_show_exit_caption.bind(true))
	_exit.mouse_exited.connect(_show_exit_caption.bind(false))
	_exit.focus_entered.connect(_show_exit_caption.bind(true))
	_exit.focus_exited.connect(_show_exit_caption.bind(false))
	_menu = PanelContainer.new()
	_menu.name = "DoorMenu"
	_menu.custom_minimum_size.x = 240
	_menu.size.x = 240
	_menu.add_theme_stylebox_override("panel", HubTheme.surface(12, 0.99))
	add_child(_menu)
	_menu.minimum_size_changed.connect(_position_menu.call_deferred)
	_menu.hide()
	resized.connect(_layout)
	refresh()


func refresh() -> void:
	var corridor: bool = Conditions.can_use_bedroom_doors()
	_exit.visible = Conditions.can_exit_bedroom()
	visible = corridor or _exit.visible
	for button: Button in _buttons.values():
		button.visible = corridor
	_show_exit_caption(false)
	close_menu()
	_layout()


func _show_exit_caption(show_caption: bool) -> void:
	_exit.text = Text.get_text("ui_bedroom_exit") if show_caption else ""


func _layout() -> void:
	if background == null or background.texture == null:
		return
	var image_size: Vector2 = background.texture.get_size()
	var scale: float = maxf(size.x / image_size.x, size.y / image_size.y)
	var rendered: Vector2 = image_size * scale
	var offset: Vector2 = (size - rendered) * 0.5
	for door: Dictionary in DataLoader.get_record("hub_corridor_doors")["doors"]:
		var rect: Array = door["drop_rect"]
		var button: Button = _buttons[door["id"]]
		button.position = offset + Vector2(float(rect[0]), float(rect[1])) * rendered
		button.size = Vector2(float(rect[2]), float(rect[3])) * rendered
	if _menu != null and _menu.visible:
		_position_menu.call_deferred()


func open_menu(door_id: String) -> void:
	if not Conditions.can_use_bedroom_doors() or not _buttons.has(door_id):
		return
	_selected = door_id
	Widgets.clear(_menu)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	_menu.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.custom_minimum_size.x = 190
	margin.add_child(column)
	var door: Dictionary = Conditions.bedroom_door(door_id)
	column.add_child(Widgets.label(str(DataLoader.get_record(str(door["location"]))["name"]), 17))
	for action: String in ["peek", "knock", "enter"]:
		if action != "enter" and not door.has("heroine"):
			continue
		column.add_child(Widgets.button(action.capitalize(), "ui_door_" + action, _request.bind(action), Conditions.can_use_bedroom_door(door_id, action)))
	column.add_child(Widgets.button("Close", "ui_room_close", close_menu))
	_menu.reset_size()
	_menu.show()
	_position_menu.call_deferred()


func _position_menu() -> void:
	if _selected.is_empty() or not _menu.visible:
		return
	_menu.reset_size()
	var rect: Rect2 = _buttons[_selected].get_rect()
	var point: Vector2 = Vector2(rect.end.x + 8, rect.get_center().y - _menu.size.y * 0.5)
	if point.x + _menu.size.x > size.x - 12:
		point.x = rect.position.x - _menu.size.x - 8
	_menu.position = point.clamp(Vector2(12, 12), (size - _menu.size - Vector2(12, 12)).max(Vector2(12, 12)))


func close_menu() -> void:
	_selected = ""
	if _menu != null:
		_menu.hide()


func _request(action: String) -> void:
	var selected: String = _selected
	close_menu()
	action_requested.emit(selected, action)


func _input(event: InputEvent) -> void:
	if _menu == null or not _menu.visible:
		return
	if event is InputEventMouseButton and event.pressed and not _menu.get_global_rect().has_point(event.position):
		close_menu()
