extends Control

signal resume_requested
signal save_requested
signal settings_requested
signal back_requested
signal volume_changed(field: String, value: float)

const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var main: VBoxContainer
var settings: VBoxContainer
var title: Label
var notice: Label
var sliders: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.008, 0.012, 0.025, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.035, 0.055, 0.08), 16, Color(0.2, 0.5, 0.6), 2))
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 26)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	title = Widgets.label(Text.get_text("ui_pause_title"), 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	main = VBoxContainer.new()
	main.name = "Main"
	main.add_theme_constant_override("separation", 10)
	column.add_child(main)
	main.add_child(Widgets.button("Resume", "ui_pause_resume", func() -> void: resume_requested.emit()))
	main.add_child(Widgets.button("Save", "ui_pause_save", func() -> void: save_requested.emit()))
	main.add_child(Widgets.button("Settings", "ui_pause_settings", func() -> void: settings_requested.emit()))
	main.add_child(Widgets.label(Text.get_text("ui_pause_hint"), 13))
	settings = VBoxContainer.new()
	settings.name = "Settings"
	settings.add_theme_constant_override("separation", 18)
	column.add_child(settings)
	_volume_row("effects_volume", "ui_pause_effects")
	_volume_row("music_volume", "ui_pause_music")
	var hint: Label = Widgets.label(Text.get_text("ui_pause_settings_hint"), 13)
	hint.custom_minimum_size.x = 360
	settings.add_child(hint)
	settings.add_child(Widgets.button("Back", "ui_pause_back", func() -> void: back_requested.emit()))
	notice = Widgets.label("", 14)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(notice)
	show_settings(false)


func _volume_row(field: String, text_id: String) -> void:
	var column: VBoxContainer = VBoxContainer.new()
	settings.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	var label: Label = Widgets.label(Text.get_text(text_id), 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value: Label = Widgets.label("", 16)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_values[field] = value
	var slider: HSlider = HSlider.new()
	slider.name = field
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(360, 32)
	slider.value_changed.connect(func(amount: float) -> void: volume_changed.emit(field, amount / 100.0))
	column.add_child(slider)
	sliders[field] = slider


func refresh_volumes(values: Dictionary) -> void:
	for field: String in sliders:
		var amount: int = roundi(float(values[field]) * 100.0)
		sliders[field].set_value_no_signal(amount)
		_values[field].text = Text.get_text("ui_pause_volume", {"value": amount})


func show_settings(enabled: bool) -> void:
	main.visible = not enabled
	settings.visible = enabled
	title.text = Text.get_text("ui_pause_settings" if enabled else "ui_pause_title")
	notice.text = ""
	if is_visible_in_tree():
		if enabled:
			sliders["effects_volume"].grab_focus()
		else:
			main.get_node("Resume").grab_focus()
