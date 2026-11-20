extends PanelContainer

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Details = preload("res://scripts/module_details.gd")
const Storage = preload("res://scripts/module_storage.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Icon = preload("res://scripts/combat_icon.gd")

var module_id: String = ""
var shop_id: String = ""


func _ready() -> void:
	name = "Product_" + module_id
	custom_minimum_size.x = 230
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", Style.box(Color(0.07, 0.11, 0.15), 10, Color(0.2, 0.32, 0.4), 1))
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var module: Dictionary = DataLoader.get_record(module_id)
	tooltip_text = str(module["description"]) + "\n" + Details.stats(module)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var icon: Icon = Icon.new()
	icon.kind = Details.icon_kind(module)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var title: Label = Widgets.label(str(module["name"]), 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.max_lines_visible = 3
	row.add_child(title)
	var stats: Label = Widgets.label(Details.stats(module), 13)
	stats.custom_minimum_size.y = 34
	column.add_child(stats)
	column.add_child(Widgets.label(Text.get_text("ui_parts_owned", {"count": Storage.count(module_id), "pending": Storage.pending(module_id)}), 12))
	var footer: HBoxContainer = HBoxContainer.new()
	column.add_child(footer)
	var price: Label = Widgets.label(Text.get_text("ui_parts_price", {"price": int(module["cost"])}), 19)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.add_theme_color_override("font_color", Color(1, 0.78, 0.35))
	footer.add_child(price)
	var buy: Button = Widgets.button("Buy_" + module_id, "ui_parts_order" if int(DataLoader.get_record(shop_id)["delivery_days"]) > 0 else "ui_parts_buy", _buy, Conditions.can_buy_module(shop_id, module_id))
	buy.tooltip_text = tooltip_text if not buy.disabled else Text.get_text("ui_parts_unavailable")
	buy.add_theme_stylebox_override("normal", Style.box(Color(0.13, 0.35, 0.36), 6))
	footer.add_child(buy)


func _buy() -> void:
	EffectApplier.buy_module(shop_id, module_id)
