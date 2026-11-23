extends VBoxContainer

signal map_requested
signal flight_requested
signal parts_requested

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const Icon = preload("res://scripts/console_icon.gd")

var _cards: Array[Button] = []
var _details: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 24
	offset_right = -24
	offset_top = 18
	offset_bottom = -18
	add_theme_constant_override("separation", 12)
	var brand: Label = Widgets.label(Text.get_text("ui_console_brand"), 12)
	brand.add_theme_color_override("font_color", Color("77949e"))
	add_child(brand)
	add_child(Widgets.label(Text.get_text("ui_hub_flight_terminal"), 25))
	_app("Parts", "ui_parts_open", "ui_console_parts_hint", "parts", parts_requested.emit, Conditions.can_use_shop("hub_module_parts"))
	_app("Map", "ui_map_open", "ui_console_map_hint", "map", map_requested.emit, Conditions.can_use_galaxy_map())
	_app("Launch", "ui_flight_launch", "ui_console_launch_hint", "launch", flight_requested.emit, Conditions.can_launch())
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	add_child(footer)
	for id: String in ["ui_console_wallet", "ui_console_system", "ui_console_day"]:
		var value: Label = Widgets.label(Text.get_text(id, {"money": GameState.state["money"], "name": DataLoader.get_record(str(GameState.state["current_system"]))["name"], "day": Clock.current_day()}), 12)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.add_theme_color_override("font_color", Color("7f9a9e"))
		footer.add_child(value)
	resized.connect(_fit)
	_fit.call_deferred()


func _app(node_name: String, title: String, hint: String, kind: String, callback: Callable, enabled: bool) -> void:
	var button: Button = Widgets.button(node_name, "", callback, enabled)
	button.tooltip_text = Text.get_text(hint)
	add_child(button)
	_cards.append(button)
	var margin: MarginContainer = MarginContainer.new()
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var icon: Icon = Icon.new()
	icon.kind = kind
	icon.custom_minimum_size = Vector2(52, 52)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var labels: VBoxContainer = VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(labels)
	labels.add_child(Widgets.label(Text.get_text(title), 19))
	var detail: Label = Widgets.label(Text.get_text(hint), 13)
	detail.add_theme_color_override("font_color", Color("819aa3"))
	labels.add_child(detail)
	_details.append(detail)
	var arrow: Label = Widgets.label(Text.get_text("ui_console_arrow"), 28)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_theme_color_override("font_color", Color("72999e"))
	row.add_child(arrow)
	_ignore_children(button)


func _ignore_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_children(child)


func _fit() -> void:
	for button: Button in _cards:
		button.custom_minimum_size.y = 72 if size.y < 440 else 90
	for detail: Label in _details:
		detail.visible = size.y >= 350
