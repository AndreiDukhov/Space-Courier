extends PanelContainer

signal back_requested

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Loadout = preload("res://scripts/ship_loadout.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Product = preload("res://scripts/module_product.gd")

var shop_id: String = "hub_module_parts"
var title: String = ""
var _category: String = ""
var _catalog: GridContainer
var _wallet: Label
var _access: Label
var _delivery: Label
var _queue: Label
var _refresh_queued: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size.y = 350
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", Style.box(Color(0.025, 0.045, 0.065), 8))
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var brand: Label = Widgets.label(Text.get_text("ui_parts_brand") if title.is_empty() else title, 22)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	header.add_child(Widgets.button("Close", "ui_parts_back", back_requested.emit))
	var address: Label = Widgets.label(Text.get_text("ui_parts_address"), 12)
	address.add_theme_color_override("font_color", Color(0.4, 0.65, 0.7))
	column.add_child(address)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 14)
	column.add_child(toolbar)
	var categories: OptionButton = OptionButton.new()
	categories.name = "Categories"
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories.add_item(Text.get_text("ui_parts_all"))
	for slot: String in Loadout.SLOTS:
		categories.add_item(Text.get_text("ui_refit_slot_" + slot))
	categories.item_selected.connect(_select_category)
	toolbar.add_child(categories)
	_wallet = Widgets.label("", 15)
	_wallet.autowrap_mode = TextServer.AUTOWRAP_OFF
	toolbar.add_child(_wallet)
	_access = Widgets.label("", 13)
	column.add_child(_access)
	_delivery = Widgets.label("", 13)
	column.add_child(_delivery)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ProductsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_catalog = GridContainer.new()
	_catalog.name = "Products"
	_catalog.columns = 2
	_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog.add_theme_constant_override("h_separation", 10)
	_catalog.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_catalog)
	_queue = Widgets.label("", 12)
	_queue.max_lines_visible = 3
	column.add_child(_queue)
	EffectApplier.modules_changed.connect(_queue_refresh)
	GameState.restored.connect(_queue_refresh)
	Clock.time_changed.connect(func(_day: int, _slot: String) -> void: _queue_refresh())
	refresh()


func _select_category(index: int) -> void:
	_category = "" if index == 0 else Loadout.SLOTS[index - 1]
	refresh()


func _queue_refresh() -> void:
	if is_inside_tree() and not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	var shop: Dictionary = DataLoader.get_record(shop_id)
	_wallet.text = Text.get_text("ui_parts_wallet", {"money": GameState.state["money"]})
	var access: PackedStringArray = []
	for condition: Dictionary in shop.get("requires", []):
		if condition.has("rep"):
			access.append(Text.get_text("ui_parts_rep", {"faction": Text.get_text("ui_parts_faction_" + str(condition["rep"])), "current": GameState.state["reputation"][condition["rep"]], "required": int(condition["value"])}))
	_access.text = " · ".join(access)
	_access.visible = not access.is_empty()
	_access.modulate = Color(0.5, 0.95, 0.75) if Conditions.evaluate(shop.get("requires", [])) else Color(1.0, 0.6, 0.4)
	_delivery.text = Text.get_text("ui_parts_arrival", {"day": Clock.current_day() + int(shop["delivery_days"])}) if int(shop["delivery_days"]) > 0 else Text.get_text("ui_parts_immediate")
	Widgets.clear(_catalog)
	for module_id: String in shop.get("modules", []):
		if not _category.is_empty() and Loadout.slot_for(DataLoader.get_record(module_id)) != _category:
			continue
		var product: Product = Product.new()
		product.module_id = module_id
		product.shop_id = shop_id
		_catalog.add_child(product)
	var queue: PackedStringArray = []
	for entry: Dictionary in GameState.state["module_deliveries"]:
		queue.append(Text.get_text("ui_parts_queue_entry", {"name": DataLoader.get_record(str(entry["module"]))["name"], "count": int(entry["count"]), "day": int(entry["arrival_day"])}))
	_queue.text = Text.get_text("ui_parts_queue") + ": " + (Text.get_text("ui_parts_queue_empty") if queue.is_empty() else "\n".join(queue))
	_queue.tooltip_text = "\n".join(queue)
