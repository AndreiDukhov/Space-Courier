extends Control

const Text = preload("res://scripts/ui_text.gd")
const ThemeFactory = preload("res://scripts/console_theme.gd")
const Icon = preload("res://scripts/flight_hud_icon.gd")
const Switch = preload("res://scripts/boost_switch.gd")

var _title: Label
var _resources: VBoxContainer
var _dock: HBoxContainer
var _boost: Switch
var _paused: Label
var _status: Label
var _notice: Label
var _values: Dictionary = {}
var _icons: Array[Icon] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ThemeFactory.make()
	_title = _label("Title", 24, self)
	_title.clip_text = true
	_paused = _label("Paused", 14, self)
	_paused.add_theme_color_override("font_color", Color("e4be75"))
	_status = _label("SpaceStatus", 14, self)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("efba77"))
	_notice = _label("Notice", 14, self)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resources = VBoxContainer.new()
	_register(_resources, "FlightResources", self)
	_resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resources.add_theme_constant_override("separation", 8)
	for kind: String in ["fuel", "hull", "credits"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		_resources.add_child(row)
		var icon: Icon = Icon.new()
		icon.kind = kind
		icon.custom_minimum_size = Vector2(26, 26)
		row.add_child(icon)
		_icons.append(icon)
		var value: Label = _label(kind.capitalize() + "Value", 18, row)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_values[kind] = value
	_dock = HBoxContainer.new()
	_register(_dock, "FlightDock", self)
	_dock.add_theme_constant_override("separation", 8)
	for kind: String in ["map", "pause", "ship"]:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(46, 44)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_register(button, kind.capitalize(), _dock)
		var icon: Icon = Icon.new()
		icon.name = "Icon"
		icon.kind = kind
		button.add_child(icon)
		_icons.append(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 9
		icon.offset_right = -9
		icon.offset_top = 8
		icon.offset_bottom = -8
	_boost = Switch.new()
	_register(_boost, "Boost", self)
	resized.connect(_layout)
	_layout.call_deferred()
	refresh()


func _register(node: Control, node_name: String, parent: Node) -> void:
	node.name = node_name
	parent.add_child(node)
	node.owner = get_parent()
	node.unique_name_in_owner = true


func _label(node_name: String, font_size: int, parent: Node) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.005, 0.01, 0.02, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	_register(label, node_name, parent)
	return label


func refresh() -> void:
	if GameState.state.is_empty():
		return
	for kind: String in ["fuel", "hull"]:
		var resource: Dictionary = GameState.state["ship"][kind]
		_values[kind].text = Text.get_text("ui_hud_resource_value", {"current": String.num(float(resource["current"]), 2 if kind == "fuel" else 1), "max": resource["max"]})
	_values["credits"].text = Text.get_text("ui_hud_credits_value", {"money": GameState.state["money"]})
	var icon: Icon = _dock.get_node("Pause/Icon")
	icon.kind = "play" if GameState.state["flight"]["paused"] else "pause"
	icon.queue_redraw()
	for instrument: Icon in _icons:
		instrument.queue_redraw()
	_boost.queue_redraw()


func reserved_rects() -> Array[Rect2]:
	var title_width: float = _title.get_theme_font("font").get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var title: Rect2 = Rect2(_title.position, Vector2(minf(_title.size.x, title_width), _title.size.y))
	return [title.grow(8), _resources.get_rect().grow(10), _dock.get_rect().grow(8), _boost.get_rect().grow(8)]


func _layout() -> void:
	_title.position = Vector2(24, 20)
	_title.size = Vector2(maxf(100, size.x - 320), 36)
	_paused.position = Vector2(26, 60)
	_resources.position = Vector2(size.x - 206, 66)
	_resources.size = Vector2(182, 102)
	_dock.position = Vector2(22, size.y - 66)
	_dock.size = _dock.get_combined_minimum_size()
	_boost.position = Vector2(size.x - 106, size.y * 0.5 - 64)
	_boost.size = Vector2(84, 136)
	_status.position = Vector2(size.x * 0.23, 64)
	_status.size = Vector2(size.x * 0.46, 56)
	_notice.position = Vector2(size.x * 0.2, size.y - 126)
	_notice.size = Vector2(size.x * 0.6, 54)
