extends Control

signal activated

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")

var background: TextureRect
var layout_id: String = "hub_kitchen_hotspot"
var text_id: String = "ui_hub_start_cooking"
var _button: Button
var _hint: Label
var _zone: String


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone = str(DataLoader.get_record(layout_id)["zones"].keys()[0])
	_button = Button.new()
	_button.name = _zone.capitalize()
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	add_child(_button)
	_button.pressed.connect(_activate)
	_button.mouse_entered.connect(_show_hint)
	_button.mouse_exited.connect(func() -> void: _hint.hide())
	_button.gui_input.connect(_on_button_input)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = Text.get_text(text_id)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color.WHITE)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.hide()
	add_child(_hint)
	resized.connect(_layout_button)
	refresh()


func refresh() -> void:
	visible = Conditions.can_use_hub_hotspot(layout_id)
	_hint.hide()
	_layout_button()


func _layout_button() -> void:
	if not is_instance_valid(_button) or background == null or background.texture == null:
		return
	var image_size: Vector2 = background.texture.get_size()
	var scale: float = maxf(size.x / image_size.x, size.y / image_size.y)
	var rendered: Vector2 = image_size * scale
	var offset: Vector2 = (size - rendered) * 0.5
	var rect: Array = DataLoader.get_record(layout_id)["zones"][_zone]["drop_rect"]
	_button.position = offset + Vector2(float(rect[0]), float(rect[1])) * rendered
	_button.size = Vector2(float(rect[2]), float(rect[3])) * rendered


func _show_hint() -> void:
	_hint.show()
	_position_hint(get_local_mouse_position())


func _position_hint(point: Vector2) -> void:
	_hint.position = (point + Vector2(16, 18)).clamp(Vector2.ZERO, (size - _hint.get_combined_minimum_size()).max(Vector2.ZERO))


func _on_button_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_position_hint(_button.position + event.position)


func _activate() -> void:
	if Conditions.can_use_hub_hotspot(layout_id):
		_hint.hide()
		activated.emit()
