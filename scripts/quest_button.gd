extends Control

signal opened

const Journal = preload("res://scripts/quest_journal.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")

var host: Control
var _button: Button
var _counter: Label
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
	_counter = Label.new()
	_counter.name = "QuestDays"
	_counter.mouse_filter = Control.MOUSE_FILTER_STOP
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.add_theme_font_size_override("font_size", 14)
	_counter.add_theme_color_override("font_color", Color("ffda91"))
	_counter.add_theme_color_override("font_outline_color", Color.BLACK)
	_counter.add_theme_constant_override("outline_size", 4)
	add_child(_counter)
	_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter.offset_left = -200
	_counter.offset_right = -16
	_counter.offset_top = 44
	_counter.offset_bottom = 64
	EffectApplier.flight_changed.connect(_sync)
	EffectApplier.orders_changed.connect(_refresh_counter)
	GameState.restored.connect(_sync)
	GameState.restored.connect(_refresh_counter)
	Clock.time_changed.connect(_on_time_changed)
	_sync()
	_refresh_counter()


func is_open() -> bool:
	return is_instance_valid(_view)


func button_rect() -> Rect2:
	if _button == null:
		return Rect2()
	return _button.get_rect().merge(_counter.get_rect()) if _counter != null and _counter.visible else _button.get_rect()


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


func _refresh_counter() -> void:
	var active: Array[String] = Conditions.active_order_ids()
	_counter.visible = not active.is_empty()
	if active.is_empty():
		_counter.text = ""
		_counter.tooltip_text = ""
		return
	var timed: Array[String] = Conditions.timed_order_ids()
	_counter.text = _day_text(timed[0]) if not timed.is_empty() else Text.get_text("ui_journal_untimed")
	var lines: PackedStringArray = []
	if not timed.is_empty():
		lines.append(Text.get_text("ui_journal_nearest", {"title": DataLoader.get_record(timed[0])["title"]}))
	for order_id: String in active:
		lines.append(Text.get_text("ui_journal_day_entry", {"title": DataLoader.get_record(order_id)["title"], "days": _day_text(order_id) if order_id in timed else Text.get_text("ui_journal_untimed")}))
	_counter.tooltip_text = "\n".join(lines)


func _day_text(order_id: String) -> String:
	return Text.get_text("ui_journal_days", {"elapsed": OrderManager.elapsed_days(order_id), "total": int(DataLoader.get_record(order_id)["deadline_days"])})


func _on_time_changed(_day: int, _slot: String) -> void:
	_refresh_counter()
