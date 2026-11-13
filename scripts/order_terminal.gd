extends Control

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

@onready var title_label: Label = %Title
@onready var resource_label: Label = %Resources
@onready var reputation_label: Label = %Reputation
@onready var order_grid: GridContainer = %Orders


func _ready() -> void:
	EffectApplier.orders_changed.connect(refresh)
	Clock.time_changed.connect(_on_time_changed)
	GameState.restored.connect(refresh)
	refresh()


func refresh() -> void:
	var location: Dictionary = DataLoader.get_record(str(GameState.state.get("location", "")))
	title_label.text = str(location.get("name", ""))
	resource_label.text = "money: %d    cargo: %s / %s" % [GameState.state.get("money", 0), String.num(OrderManager.active_mass(), 2), String.num(float(GameState.state.get("ship", {}).get("cargo", {}).get("max_mass", 0)), 2)]
	var reputation_parts: PackedStringArray = []
	for reputation_id: String in GameState.state.get("reputation", {}):
		reputation_parts.append("%s: %d" % [reputation_id, GameState.state["reputation"][reputation_id]])
	reputation_label.text = "    ".join(reputation_parts)
	for child: Node in order_grid.get_children():
		order_grid.remove_child(child)
		child.queue_free()
	for order: Dictionary in DataLoader.get_records("orders"):
		if order.get("source") != "shop":
			order_grid.add_child(_order_card(order))


func _order_card(order: Dictionary) -> PanelContainer:
	var order_id: String = str(order["id"])
	var panel: PanelContainer = PanelContainer.new()
	panel.name = order_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.tooltip_text = str(order["description"])
	var active: bool = OrderManager.status(order_id) == "active"
	panel.add_theme_stylebox_override("panel", Widgets.box(Color(0.06, 0.09, 0.14), 12, Color(0.35, 0.85, 0.8) if active else Color(0.16, 0.22, 0.29), 2))
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var source: Label = Label.new()
	source.text = "%s / %s" % [order["source"], order_id]
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.add_theme_font_size_override("font_size", 13)
	source.add_theme_color_override("font_color", Widgets.identity_color(str(order["source"])).lightened(0.4))
	header.add_child(source)
	var status_label: Label = Label.new()
	status_label.name = "Status"
	status_label.text = OrderManager.status(order_id)
	status_label.add_theme_font_size_override("font_size", 13)
	header.add_child(status_label)
	var title: Label = Label.new()
	title.text = str(order["title"])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	var payment: Label = Label.new()
	payment.name = "Payment"
	var amount: int = 0
	for effect: Dictionary in order["reward"]:
		amount += int(effect.get("money", 0))
	payment.text = Text.get_text("ui_order_payment", {"amount": amount})
	payment.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
	column.add_child(payment)
	var system: Dictionary = DataLoader.get_record(str(order["to"]))
	var destination: Label = Label.new()
	destination.name = "Destination"
	var planet_name: String = ""
	for object: Dictionary in system.get("objects", []):
		if object.get("type") == "planet" and object.get("id") == order["to_planet"]:
			planet_name = str(object["name"])
	destination.text = Text.get_text("ui_order_system", {"name": system.get("name", "")}) + "\n" + Text.get_text("ui_order_planet", {"name": planet_name})
	destination.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination.add_theme_font_size_override("font_size", 14)
	column.add_child(destination)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var summary: Label = Label.new()
	var days: int = OrderManager.remaining_days(order_id) if active else int(order["deadline_days"])
	summary.text = Text.get_text("ui_order_summary", {"mass": String.num(float(order["cargo"]["mass"]), 2), "days": days})
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("font_size", 13)
	footer.add_child(summary)
	footer.add_child(_action_button("Accept", "+", order_id, not Conditions.can_accept_order(order_id), "ui_order_accept", _on_accept))
	footer.add_child(_action_button("Fail", "×", order_id, not Conditions.can_settle_order(order_id, "failed"), "ui_order_fail", _on_fail))
	return panel


func _action_button(button_name: String, symbol: String, order_id: String, disabled: bool, hint_id: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.text = symbol
	button.disabled = disabled
	button.custom_minimum_size = Vector2(36, 36)
	button.tooltip_text = Text.get_text(hint_id)
	button.pressed.connect(callback.bind(order_id))
	return button


func _on_accept(order_id: String) -> void:
	if OrderManager.accept(order_id) != OK:
		refresh()


func _on_fail(order_id: String) -> void:
	if OrderManager.fail(order_id) != OK:
		refresh()


func _on_time_changed(_day: int, _slot: String) -> void:
	refresh()
