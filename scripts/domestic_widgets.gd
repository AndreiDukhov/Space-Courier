extends RefCounted

const Widgets = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")


static func label(value: String, font_size: int = 17) -> Label:
	var node: Label = Label.new()
	node.text = value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", font_size)
	return node


static func button(node_name: String, text_id: String, callback: Callable, enabled: bool = true, values: Dictionary = {}) -> Button:
	var node: Button = Button.new()
	node.name = node_name
	node.text = Text.get_text(text_id, values)
	node.custom_minimum_size.y = 38
	node.disabled = not enabled
	node.pressed.connect(callback)
	return node


static func card(parent: Node, node_name: String, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Widgets.box(Color(0.065, 0.1, 0.14), 12, Color(0.16, 0.28, 0.34), 1))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	column.add_child(label(title, 20))
	return column


static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
