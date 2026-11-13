extends Control

signal opened

const Journal = preload("res://scripts/quest_journal.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")

var host: Control
var _button: Button
var _view: Journal


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = Button.new()
	_button.name = "OpenQuests"
	_button.text = Text.get_text("ui_journal_open")
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.add_theme_font_size_override("font_size", 18)
	_button.add_theme_color_override("font_outline_color", Color.BLACK)
	_button.add_theme_constant_override("outline_size", 4)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(_button)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -140
	_button.offset_right = -8
	_button.offset_top = 8
	_button.offset_bottom = 44
	_button.pressed.connect(_open)
	EffectApplier.flight_changed.connect(_sync)
	GameState.restored.connect(_sync)
	_sync()


func is_open() -> bool:
	return is_instance_valid(_view)


func button_rect() -> Rect2:
	return _button.get_rect() if _button != null else Rect2()


func _open() -> void:
	if is_open() or host == null or not Conditions.can_use_galaxy_map():
		return
	_view = Journal.new()
	_view.name = "QuestJournal"
	_view.closed.connect(_close)
	host.add_child(_view)
	opened.emit()


func _close() -> void:
	if is_open():
		host.remove_child(_view)
		_view.queue_free()
		_view = null


func _sync() -> void:
	_button.disabled = not Conditions.can_use_galaxy_map()
	if _button.disabled:
		_close()
