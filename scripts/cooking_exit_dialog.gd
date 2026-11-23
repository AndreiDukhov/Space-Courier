extends ConfirmationDialog

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")

var _action: Callable


func _ready() -> void:
	title = Text.get_text("ui_kitchen_abort_title")
	dialog_text = Text.get_text("ui_kitchen_abort_warning")
	get_ok_button().text = Text.get_text("ui_kitchen_abort_confirm")
	get_cancel_button().text = Text.get_text("ui_kitchen_abort_continue")
	confirmed.connect(_confirm)
	canceled.connect(func() -> void: _action = Callable())
	close_requested.connect(func() -> void: _action = Callable())
	exclusive = true


func request(action: Callable) -> void:
	if visible:
		return
	if not Conditions.can_cancel_cooking():
		action.call()
		return
	_action = action
	popup_centered(Vector2i(480, 160))


func _confirm() -> void:
	var action: Callable = _action
	_action = Callable()
	EffectApplier.cancel_cooking()
	if action.is_valid():
		action.call()
