extends "res://scripts/combat_card.gd"

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")
const Storage = preload("res://scripts/module_storage.gd")
const HubTheme = preload("res://scripts/hub_theme.gd")

var module_id: String = ""


func _ready() -> void:
	super._ready()
	_icon.warm = true
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.queue_redraw()
	_label.max_lines_visible = 4
	_label.add_theme_font_size_override("font_size", 12)
	add_theme_stylebox_override("hover", Style.box(Color("ffe5b6"), 12, HubTheme.ACCENT, 2))
	add_theme_stylebox_override("disabled", Style.box(Color("ebe1ce"), 12, Color("cfbda1"), 1))


func set_selected(selected: bool) -> void:
	add_theme_stylebox_override("normal", Style.box(HubTheme.CARD, 12, HubTheme.ACCENT if selected else HubTheme.BORDER, 2))
	if is_instance_valid(_label):
		_label.modulate = Color.WHITE
		_label.add_theme_color_override("font_color", HubTheme.MUTED if disabled else HubTheme.INK)
		_icon.modulate = Color(1, 1, 1, 0.55) if disabled else Color.WHITE


func refresh_status() -> void:
	title = str(DataLoader.get_record(module_id)["name"])
	if module_id in GameState.state["ship"]["modules"]:
		title += "\n" + Text.get_text("ui_refit_current")
	else:
		title += "\n" + Text.get_text("ui_parts_stock", {"count": Storage.count(module_id)})
	_label.text = title
	disabled = not Conditions.can_install_module(module_id)
	set_selected(false)


func _get_drag_data(_position: Vector2) -> Variant:
	if not Conditions.can_install_module(module_id):
		return null
	var preview: Control = Control.new()
	var icon: Control = Icon.new()
	icon.kind = kind
	icon.warm = true
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
	caption.add_theme_color_override("font_color", HubTheme.INK)
	caption.add_theme_color_override("font_outline_color", HubTheme.PAPER)
	caption.add_theme_constant_override("outline_size", 5)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(caption)
	set_drag_preview(preview)
	return module_id
