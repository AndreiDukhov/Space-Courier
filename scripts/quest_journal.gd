extends Control

signal closed

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 20
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.86)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Window"
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.035, 0.065, 0.1), 16, Color(0.25, 0.7, 0.7), 2))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Widgets.label(Text.get_text("ui_journal_title"), 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Widgets.button("Close", "ui_space_close", closed.emit))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "Quests"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	EffectApplier.orders_changed.connect(refresh)
	Clock.time_changed.connect(_on_time_changed)
	GameState.restored.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree() or _content == null:
		return
	Widgets.clear(_content)
	var orders: Array[String] = Conditions.accepted_order_ids()
	if orders.is_empty():
		_content.add_child(Widgets.label(Text.get_text("ui_journal_empty")))
	for order_id: String in orders:
		var order: Dictionary = DataLoader.get_record(order_id)
		var card: VBoxContainer = Widgets.card(_content, order_id, str(order["title"]))
		var status: Label = Widgets.label(Text.get_text("ui_journal_" + OrderManager.status(order_id)), 16)
		status.name = "Status"
		card.add_child(status)
		var description: Label = Widgets.label(str(order.get("description", Text.get_text("ui_journal_description"))), 16)
		description.name = "Description"
		card.add_child(description)
		if order.get("source") == "shop":
			_shop_details(card, order)
		else:
			_delivery_details(card, order)


func _delivery_details(card: VBoxContainer, order: Dictionary) -> void:
	var planet: Dictionary = Conditions.space_object(str(order["to_planet"]), str(order["to"]))
	var destination: Label = Widgets.label(Text.get_text("ui_order_system", {"name": DataLoader.get_record(str(order["to"]))["name"]}) + "\n" + Text.get_text("ui_order_planet", {"name": planet["name"]}))
	destination.name = "Destination"
	card.add_child(destination)
	var amount: int = 0
	for effect: Dictionary in order["reward"]:
		amount += int(effect.get("money", 0))
	card.add_child(Widgets.label(Text.get_text("ui_journal_reward", {"amount": amount})))
	var active: bool = OrderManager.status(str(order["id"])) == "active"
	var deadline: Label = Widgets.label(Text.get_text("ui_journal_deadline" if active else "ui_journal_closed_deadline", {"days": OrderManager.remaining_days(str(order["id"])), "day": OrderManager.deadline_day(str(order["id"]))}), 15)
	deadline.name = "Deadline"
	card.add_child(deadline)
	if active:
		card.add_child(Widgets.label(Text.get_text("ui_journal_handover"), 15))


func _shop_details(card: VBoxContainer, order: Dictionary) -> void:
	card.add_child(Widgets.label(Text.get_text("ui_journal_giver", {"name": DataLoader.get_record(str(order["giver"]))["name"]})))
	if order.has("need_items"):
		var items: PackedStringArray = []
		for entry: Dictionary in order["need_items"]:
			items.append("%s ×%d" % [DataLoader.get_record(str(entry["item"]))["name"], entry["count"]])
		card.add_child(Widgets.label(Text.get_text("ui_home_quest_fetch", {"items": ", ".join(items)})))
	elif order.has("labor_slots"):
		card.add_child(Widgets.label(Text.get_text("ui_home_quest_labor", {"slots": order["labor_slots"]})))


func _on_time_changed(_day: int, _slot: String) -> void:
	refresh()
