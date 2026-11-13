extends "res://scripts/combat_card.gd"

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")

var module_id: String = ""


func refresh_status() -> void:
	title = str(DataLoader.get_record(module_id)["name"])
	if module_id in GameState.state["ship"]["modules"]:
		title += "\n" + Text.get_text("ui_refit_current")
	_label.text = title
	disabled = not Conditions.can_install_module(module_id)
	set_selected(false)


func _get_drag_data(_position: Vector2) -> Variant:
	if not Conditions.can_install_module(module_id):
		return null
	var preview: Control = Control.new()
	var icon: Control = Icon.new()
	icon.kind = kind
	icon.size = Vector2(64, 64)
	icon.position = Vector2(-32, -32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)
	var caption: Label = Label.new()
	caption.text = str(DataLoader.get_record(module_id)["name"])
	caption.position = Vector2(-90, 36)
	caption.size = Vector2(180, 44)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 5)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(caption)
	set_drag_preview(preview)
	return module_id
