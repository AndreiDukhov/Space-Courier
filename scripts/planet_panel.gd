extends Control

signal closed

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var planet_id: String = ""
var npc_id: String = ""
var trading: bool = false
var _column: VBoxContainer
var _result: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Window"
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.035, 0.065, 0.1), 16, Color(0.25, 0.7, 0.7), 2))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	panel.add_child(margin)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 12)
	scroll.add_child(_column)
	body.add_child(Widgets.button("Close", "ui_space_close", closed.emit))
	EffectApplier.orders_changed.connect(_refresh_deferred)
	EffectApplier.domestic_changed.connect(_refresh_deferred)
	GameState.restored.connect(_on_restored)
	refresh()


func _refresh_deferred() -> void:
	if is_inside_tree():
		refresh.call_deferred()


func _on_restored() -> void:
	closed.emit()


func refresh() -> void:
	if not is_inside_tree():
		return
	Widgets.clear(_column)
	var planet: Dictionary = Conditions.space_object(planet_id) if npc_id.is_empty() else DataLoader.get_record(npc_id)
	_column.add_child(Widgets.label(str(planet.get("name", "")), 24))
	_column.add_child(Widgets.label(Text.get_text("ui_space_wallet", {"money": GameState.state["money"]}), 17))
	if not _result.is_empty():
		_column.add_child(Widgets.label(_result, 17))
	var available: bool = Conditions.can_interact_planet(planet_id) if npc_id.is_empty() else Conditions.can_trade_npc(npc_id)
	if not available:
		_column.add_child(Widgets.label(Text.get_text("ui_space_unavailable")))
		return
	if trading:
		_trade(planet)
	else:
		_dialogue(planet)


func _trade(planet: Dictionary) -> void:
	if npc_id.is_empty():
		_fuel_controls()
	var shop_id: String = str(planet["shop"])
	for entry: Dictionary in DataLoader.get_record(shop_id).get("items", []):
		var item_id: String = str(entry["item"])
		_column.add_child(Widgets.button("Buy_" + item_id, "ui_space_buy", _buy.bind(shop_id, item_id), Conditions.can_buy_item(shop_id, item_id), {"name": DataLoader.get_record(item_id)["name"], "price": int(entry["price"])}))
	for item: Dictionary in DataLoader.get_records("items"):
		var item_id: String = str(item["id"])
		if Conditions.can_sell_item(shop_id, item_id):
			_column.add_child(Widgets.button("Sell_" + item_id, "ui_space_sell", _sell.bind(shop_id, item_id), true, {"name": item["name"]}))


func _fuel_controls() -> void:
	var fuel: Dictionary = GameState.state["ship"]["fuel"]
	var price: int = int(DataLoader.get_record(str(GameState.state["current_system"]))["refuel"]["price_per_unit"])
	_column.add_child(Widgets.label(Text.get_text("ui_space_fuel", {"current": String.num(float(fuel["current"]), 2), "max": fuel["max"], "price": price}), 18))
	var missing: float = maxf(0.0, float(fuel["max"]) - float(fuel["current"]))
	_column.add_child(Widgets.button("FuelOne", "ui_space_fuel_one", _fuel.bind(minf(1.0, missing)), Conditions.can_buy_planet_fuel(planet_id, minf(1.0, missing)), {"price": ceili(minf(1.0, missing) * price)}))
	_column.add_child(Widgets.button("FuelFull", "ui_space_fuel_full", _fuel.bind(missing), Conditions.can_buy_planet_fuel(planet_id, missing), {"price": ceili(missing * price)}))


func _dialogue(planet: Dictionary) -> void:
	var event: Dictionary = DataLoader.get_record(str(planet["dialogue"]))
	_column.add_child(Widgets.label(Text.get_text("ui_space_quests"), 21))
	var count: int = 0
	for order_id: String in GameState.state["orders"]:
		var order: Dictionary = DataLoader.get_record(order_id)
		if OrderManager.status(order_id) != "active" or order.get("to_planet") != planet_id:
			continue
		count += 1
		var column: VBoxContainer = Widgets.card(_column, order_id, str(order["title"]))
		column.add_child(Widgets.label(str(order["description"]), 15))
		var payment: int = 0
		for effect: Dictionary in order["reward"]:
			payment += int(effect.get("money", 0))
		column.add_child(Widgets.label(Text.get_text("ui_order_payment", {"amount": payment}), 17))
		column.add_child(Widgets.button("Deliver_" + order_id, "ui_flight_deliver", _deliver.bind(order_id), Conditions.can_deliver_order(order_id)))
	if count == 0:
		_column.add_child(Widgets.label(Text.get_text("ui_space_no_quests")))
	for i: int in range(event.get("options", []).size()):
		var button: Button = Button.new()
		button.text = str(event["options"][i]["text"])
		button.custom_minimum_size.y = 38
		button.disabled = not Conditions.event_is_available(str(planet["dialogue"]))
		button.pressed.connect(_choose.bind(i))
		_column.add_child(button)
	if Conditions.can_dock():
		_column.add_child(Widgets.button("Dock", "ui_flight_dock", _dock))


func _fuel(amount: float) -> void:
	EffectApplier.buy_planet_fuel(planet_id, amount)
	refresh()


func _buy(shop_id: String, item_id: String) -> void:
	EffectApplier.buy_item(shop_id, item_id)
	refresh()


func _sell(shop_id: String, item_id: String) -> void:
	EffectApplier.sell_item(shop_id, item_id)
	refresh()


func _deliver(order_id: String) -> void:
	if EffectApplier.deliver_order(order_id) == OK:
		_result = Text.get_text("ui_flight_delivered", {"name": DataLoader.get_record(order_id)["title"]})
	refresh()


func _choose(index: int) -> void:
	EffectApplier.choose_planet_dialogue(planet_id, index)
	refresh()


func _dock() -> void:
	if EffectApplier.dock_at_hub() == OK:
		closed.emit()
