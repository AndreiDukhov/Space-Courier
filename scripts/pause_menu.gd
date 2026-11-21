extends CanvasLayer

signal opened
signal closed

const Conditions = preload("res://scripts/condition_evaluator.gd")
const View = preload("res://scripts/pause_menu_view.gd")
const Text = preload("res://scripts/ui_text.gd")

var view: View
var _was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	if not DataLoader.load_errors.is_empty():
		return
	view = View.new()
	view.name = "PauseMenuView"
	add_child(view)
	view.hide()
	view.resume_requested.connect(close)
	view.save_requested.connect(_save)
	view.settings_requested.connect(func() -> void: view.show_settings(true))
	view.back_requested.connect(func() -> void: view.show_settings(false))
	view.volume_changed.connect(EffectApplier.set_audio_volume)
	GameState.settings_changed.connect(_refresh_settings)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if not Conditions.can_open_pause_menu():
		return
	get_viewport().set_input_as_handled()
	if not is_open():
		open()
	elif view.settings.visible:
		view.show_settings(false)
	else:
		close()


func is_open() -> bool:
	return view != null and view.visible


func open() -> void:
	if is_open() or not Conditions.can_open_pause_menu():
		return
	_was_paused = get_tree().paused
	view.show()
	view.show_settings(false)
	_refresh_settings()
	get_tree().paused = true
	opened.emit()


func close() -> void:
	if not is_open():
		return
	view.hide()
	get_tree().paused = _was_paused
	closed.emit()


func _refresh_settings() -> void:
	if view != null and GameState.state.get("settings") is Dictionary:
		view.refresh_volumes(GameState.state["settings"])


func _save() -> void:
	var result: Error = GameState.save_game()
	view.notice.text = Text.get_text("ui_pause_saved" if result == OK else "ui_pause_save_error")
