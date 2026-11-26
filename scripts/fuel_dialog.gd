extends Control

signal dismissed

const ThemeFactory = preload("res://scripts/hub_theme.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var arrived: bool = false
var _notice: Label
var _choices: VBoxContainer
var _loads: VBoxContainer


func _ready() -> void:
	name = "TowNotice" if arrived else "FuelEmergency"
	theme = ThemeFactory.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.15, 0.1, 0.06, 0.6)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre: CenterContainer = CenterContainer.new()
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 460
	panel.add_theme_stylebox_override("panel", ThemeFactory.surface(18, 1.0))
	centre.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	column.add_child(Widgets.label(Text.get_text("ui_tow_arrived_title" if arrived else "ui_fuel_empty_title"), 24))
	var body: Label = Widgets.label(Text.get_text("ui_tow_arrived_body" if arrived else "ui_fuel_empty_body", {"fee": EffectApplier.FUEL_TOW_FEE, "days": EffectApplier.TOW_DAYS}), 17)
	body.custom_minimum_size.x = 410
	column.add_child(body)
	_notice = Widgets.label("", 15)
	column.add_child(_notice)
	if arrived:
		column.add_child(Widgets.button("Close", "ui_tow_continue", _acknowledge))
	else:
		_choices = VBoxContainer.new()
		_choices.add_theme_constant_override("separation", 10)
		column.add_child(_choices)
		_choices.add_child(Widgets.button("Tow", "ui_fuel_tow", _tow))
		var load_button: Button = Widgets.button("Load", "ui_fuel_load", _show_loads, FileAccess.file_exists(GameState.SAVE_PATH) or FileAccess.file_exists(GameState.AUTOSAVE_PATH))
		load_button.tooltip_text = Text.get_text("ui_fuel_load_hint")
		_choices.add_child(load_button)
		_loads = VBoxContainer.new()
		_loads.add_theme_constant_override("separation", 10)
		column.add_child(_loads)
		_loads.add_child(Widgets.button("LoadManual", "ui_fuel_load_manual", _load_game.bind(GameState.SAVE_PATH), FileAccess.file_exists(GameState.SAVE_PATH)))
		_loads.add_child(Widgets.button("LoadAuto", "ui_fuel_load_auto", _load_game.bind(GameState.AUTOSAVE_PATH), FileAccess.file_exists(GameState.AUTOSAVE_PATH)))
		_loads.add_child(Widgets.button("Back", "ui_fuel_back", _hide_loads))
		_loads.hide()


func _tow() -> void:
	if EffectApplier.request_tow() != OK:
		_notice.text = Text.get_text("ui_home_error")
	else:
		dismissed.emit()


func _show_loads() -> void:
	_choices.hide()
	_loads.show()


func _hide_loads() -> void:
	_loads.hide()
	_choices.show()


func _load_game(path: String) -> void:
	if GameState.load_game(path) != OK:
		_notice.text = Text.get_text("ui_map_save_error")
	else:
		dismissed.emit()


func _acknowledge() -> void:
	EffectApplier.acknowledge_tow()
	dismissed.emit()
