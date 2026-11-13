extends Button

const Icon = preload("res://scripts/combat_icon.gd")
const Style = preload("res://scripts/hub_widgets.gd")

var kind: String = "turret"
var title: String = ""
var _icon: Icon
var _label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(122, 118)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 7
	column.offset_right = -7
	column.offset_top = 5
	column.offset_bottom = -5
	_icon = Icon.new()
	_icon.name = "Icon"
	_icon.kind = kind
	_icon.custom_minimum_size = Vector2(48, 48)
	_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_icon)
	_label = Label.new()
	_label.name = "Caption"
	_label.text = title
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.max_lines_visible = 3
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", 12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_label)
	set_selected(false)
	add_theme_stylebox_override("hover", Style.box(Color(0.08, 0.18, 0.22), 12, Color(0.4, 0.95, 0.9), 2))
	add_theme_stylebox_override("disabled", Style.box(Color(0.03, 0.045, 0.065), 12, Color(0.1, 0.15, 0.2), 1))


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override("normal", Style.box(Color(0.045, 0.09, 0.12), 12, Color(1.0, 0.72, 0.28) if selected else Color(0.18, 0.32, 0.4), 2))
	if is_instance_valid(_label):
		_label.modulate = Color(0.45, 0.5, 0.55) if disabled else Color.WHITE
		_icon.modulate = _label.modulate
