extends VBoxContainer

signal map_requested
signal flight_requested

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 22
	offset_right = -22
	offset_top = 22
	offset_bottom = -22
	add_theme_constant_override("separation", 16)
	add_child(Widgets.label(Text.get_text("ui_hub_flight_terminal"), 24))
	add_child(Widgets.button("Map", "ui_map_open", map_requested.emit, Conditions.can_use_galaxy_map()))
	add_child(Widgets.button("Launch", "ui_flight_launch", flight_requested.emit, Conditions.can_launch()))
