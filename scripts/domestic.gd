extends Control

signal close_requested

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Kitchen = preload("res://scripts/kitchen.gd")
const Router = preload("res://scripts/scene_router.gd")

var tab: String = "inventory"
var _content: VBoxContainer
var _resources: Label
var _status: Label
var _refresh_queued: bool = false
var _scroll: ScrollContainer
var _title: Label


func _ready() -> void:
	if GameState.state.is_empty():
		GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	if not GameState.state.get("kitchen", {}).is_empty():
		tab = "kitchen"
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.025, 0.045, 0.065, 0.99)
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Widgets.label(Text.get_text("ui_home_title"), 25)
	_title = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Widgets.button("Save", "ui_home_save", _save))
	header.add_child(Widgets.button("Load", "ui_home_load", _load))
	header.add_child(Widgets.button("Close", "ui_room_close" if Conditions.is_inside_ship() else "ui_home_close", _close))
	_resources = Widgets.label("")
	column.add_child(_resources)
	var tabs: HBoxContainer = HBoxContainer.new()
	column.add_child(tabs)
	for tab_id: String in ["inventory", "shop", "kitchen"]:
		var enabled: bool = tab_id == "inventory" or GameState.state.get("location") == "hub_" + ("shop" if tab_id == "shop" else "kitchen")
		tabs.add_child(Widgets.button(tab_id, "ui_home_" + tab_id, _select_tab.bind(tab_id), enabled))
	_status = Widgets.label("")
	_status.add_theme_color_override("font_color", Color(0.6, 0.95, 0.8))
	column.add_child(_status)
	var scroll: ScrollContainer = ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	EffectApplier.domestic_changed.connect(_queue_refresh)
	Clock.time_changed.connect(func(_day: int, _slot: String) -> void: _queue_refresh())
	GameState.restored.connect(_on_restored)
	refresh()


func refresh() -> void:
	_refresh_queued = false
	if not is_instance_valid(_content):
		return
	_resources.text = Text.get_text("ui_home_resources", {"money": GameState.state["money"], "mass": String.num(OrderManager.active_mass(), 2), "capacity": GameState.state["ship"]["cargo"]["max_mass"], "day": Clock.current_day(), "slot": Clock.current_slot()})
	_resources.visible = tab != "kitchen"
	_status.visible = not _status.text.is_empty()
	_title.text = Text.get_text({"inventory": "ui_home_inventory", "kitchen": "ui_home_kitchen"}.get(tab, "ui_home_title"))
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if tab == "kitchen" else ScrollContainer.SCROLL_MODE_AUTO
	Widgets.clear(_content)
	match tab:
		"shop": _render_shop()
		"kitchen":
			var kitchen: Kitchen = Kitchen.new()
			kitchen.finished.connect(_result)
			_content.add_child(kitchen)
		"inventory": _render_inventory()


func _render_shop() -> void:
	var shop: Dictionary = DataLoader.get_record("hub_shop_stock")
	if not Conditions.can_use_shop():
		_content.add_child(Widgets.label(Text.get_text("ui_home_shop_closed")))
		return
	var attitude: float = float(GameState.state["heroines"][shop["owner"]]["attitude"])
	_content.add_child(Widgets.label(Text.get_text("ui_home_shop_hours", {"attitude": String.num(attitude, 1)})))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for entry: Dictionary in shop["items"]:
		var item_id: String = str(entry["item"])
		var column: VBoxContainer = Widgets.card(grid, item_id, str(DataLoader.get_record(item_id)["name"]))
		if attitude < float(entry.get("min_attitude", 0)):
			column.add_child(Widgets.label(Text.get_text("ui_home_locked", {"value": entry["min_attitude"]}), 15))
		column.add_child(Widgets.button("Buy", "ui_home_buy", _buy.bind(item_id), Conditions.can_buy_item("hub_shop_stock", item_id), {"price": int(entry["price"])}))
	_content.add_child(Widgets.label(Text.get_text("ui_home_quests"), 22))
	for order: Dictionary in DataLoader.get_records("orders"):
		if order.get("source") != "shop":
			continue
		var id: String = str(order["id"])
		var column: VBoxContainer = Widgets.card(_content, id, str(order["title"]))
		var description: String = Text.get_text("ui_home_quest_labor", {"slots": order.get("labor_slots", 0)})
		if order.has("need_items"):
			var items: PackedStringArray = []
			for entry: Dictionary in order["need_items"]:
				items.append("%s ×%d" % [DataLoader.get_record(str(entry["item"]))["name"], entry["count"]])
			description = Text.get_text("ui_home_quest_fetch", {"items": ", ".join(items)})
		column.add_child(Widgets.label(description, 16))
		if OrderManager.status(id) == "completed":
			column.add_child(Widgets.label(Text.get_text("ui_home_quest_completed")))
		elif OrderManager.status(id) == "active":
			column.add_child(Widgets.button("Complete", "ui_home_quest_complete", _complete_quest.bind(id), Conditions.can_complete_shop_quest(id)))
		else:
			column.add_child(Widgets.button("Accept", "ui_home_quest_accept", _accept_quest.bind(id), Conditions.can_accept_shop_quest(id)))
	_render_inventory()


func _render_inventory() -> void:
	_content.add_child(Widgets.label(Text.get_text("ui_home_inventory"), 22))
	if GameState.state["inventory"].is_empty() and GameState.state["ship"]["cargo"]["items"].is_empty():
		_content.add_child(Widgets.label(Text.get_text("ui_home_empty")))
	if GameState.state.get("location") != "hub_kitchen" and not GameState.state["inventory"].is_empty():
		_content.add_child(Widgets.label(Text.get_text("ui_home_food_locked"), 15))
	for index: int in range(GameState.state["inventory"].size()):
		_inventory_card(GameState.state["inventory"][index], index, true)
	for index: int in range(GameState.state["ship"]["cargo"]["items"].size()):
		_inventory_card(GameState.state["ship"]["cargo"]["items"][index], index, false)
	if GameState.state["buffs"].has("steady_hands"):
		_content.add_child(Widgets.label(Text.get_text("ui_home_buff", {"day": GameState.state["buffs"]["steady_hands"]})))


func _inventory_card(entry: Dictionary, index: int, food: bool) -> void:
	var item_id: String = str(entry["item"])
	var item: Dictionary = DataLoader.get_record(item_id)
	var column: VBoxContainer = Widgets.card(_content, item_id + str(index), Text.get_text("ui_home_food_stack" if food else "ui_home_stack", {"name": item["name"], "count": entry["count"], "mass": float(item.get("mass", 0)) * int(entry["count"])}))
	if entry.has("quality"):
		column.add_child(Widgets.label(Text.get_text("ui_home_quality", {"quality": entry["quality"]}), 15))
	if item["type"] == "cookbook":
		column.add_child(Widgets.button("Read", "ui_home_read", _read.bind(index), Conditions.can_read_book(index)))
	if food and item["type"] == "dish" and GameState.state.get("location") == "hub_kitchen":
		column.add_child(Widgets.button("Eat", "ui_home_eat", _eat.bind(index), Conditions.can_use_food(index)))
		column.add_child(Widgets.label(Text.get_text("ui_food_conversation_hint"), 15))
	if Conditions.can_sell_item("hub_shop_stock", item_id):
		var price: int = floori(float(item["sell_price"]) * float(DataLoader.get_record("hub_shop_stock")["sell_ratio"]))
		column.add_child(Widgets.button("Sell", "ui_home_sell", _sell.bind(item_id), true, {"price": price}))


func _select_tab(value: String) -> void:
	tab = value
	refresh()


func _queue_refresh() -> void:
	if not is_inside_tree():
		return
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


func _result(result: Error) -> void:
	_status.text = Text.get_text("ui_home_done" if result == OK else "ui_home_error", {"code": result})
	_queue_refresh()


func _buy(item_id: String) -> void:
	_result(EffectApplier.buy_item("hub_shop_stock", item_id))


func _sell(item_id: String) -> void:
	_result(EffectApplier.sell_item("hub_shop_stock", item_id))


func _read(index: int) -> void:
	_result(EffectApplier.read_book(index))


func _eat(index: int) -> void:
	_result(EffectApplier.use_food(index))


func _accept_quest(order_id: String) -> void:
	_result(EffectApplier.accept_shop_quest(order_id))


func _complete_quest(order_id: String) -> void:
	_result(EffectApplier.complete_shop_quest(order_id))


func _save() -> void:
	var result: Error = GameState.save_game()
	_result(result)
	if result == OK:
		_status.text = Text.get_text("ui_home_saved")


func _load() -> void:
	var result: Error = GameState.load_game()
	_result(result)
	if result == OK:
		_status.text = Text.get_text("ui_home_loaded")


func _on_restored() -> void:
	if not is_inside_tree():
		return
	if get_tree().current_scene == self and Router.current_path() != "res://scenes/hub.tscn":
		get_tree().call_deferred("change_scene_to_file", Router.current_path())
	else:
		if not GameState.state.get("kitchen", {}).is_empty():
			tab = "kitchen"
		_queue_refresh()


func _close() -> void:
	if close_requested.get_connections().is_empty():
		get_tree().change_scene_to_file("res://scenes/hub.tscn")
	else:
		close_requested.emit()
