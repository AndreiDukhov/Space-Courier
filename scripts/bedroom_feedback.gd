extends Control

signal closed

const Widgets = preload("res://scripts/domestic_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const HubTheme = preload("res://scripts/hub_theme.gd")

var scene_id: String = ""
var heading: String = ""
var message_id: String = ""


func _ready() -> void:
	theme = HubTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.27, 0.15, 0.07, 0.35)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre: CenterContainer = CenterContainer.new()
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 200)
	panel.add_theme_stylebox_override("panel", HubTheme.surface(14, 1.0))
	centre.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(Widgets.label(heading, 23))
	if not message_id.is_empty():
		column.add_child(Widgets.label(Text.get_text(message_id), 16))
	for line: Dictionary in DataLoader.get_record(scene_id).get("lines", []):
		column.add_child(Widgets.label(str(line["text"]), 20))
	column.add_child(Widgets.button("Close", "ui_room_close", closed.emit))
