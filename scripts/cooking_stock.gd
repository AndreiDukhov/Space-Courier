extends RefCounted

const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const State = preload("res://scripts/domestic_state.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Token = preload("res://scripts/cooking_token.gd")
const HubTheme = preload("res://scripts/hub_theme.gd")


static func populate(parent: Control, kitchen: Dictionary) -> void:
	var sidebar: VBoxContainer = VBoxContainer.new()
	sidebar.name = "KitchenStock"
	sidebar.custom_minimum_size.x = 225
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.size_flags_stretch_ratio = 1.0
	sidebar.add_theme_constant_override("separation", 10)
	parent.add_child(sidebar)
	for dishes: bool in [false, true]:
		var stock: VBoxContainer = _panel(sidebar, dishes)
		var total: int = 0
		for entry: Dictionary in GameState.state.get("inventory", []):
			var item_id: String = str(entry["item"])
			var item: Dictionary = DataLoader.get_record(item_id)
			if item.get("type") != ("dish" if dishes else "ingredient"):
				continue
			var available: int = int(entry["count"]) - (0 if dishes else State.reserved(item_id, kitchen))
			if available <= 0:
				continue
			total += 1
			_row(stock, entry, available, dishes)
		if total == 0:
			stock.add_child(Widgets.label(Text.get_text("ui_kitchen_dishes_empty" if dishes else "ui_kitchen_on_counter" if not kitchen.is_empty() else "ui_kitchen_buy_hint"), 14))


static func _panel(parent: Control, dishes: bool) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "DishesPanel" if dishes else "IngredientsPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.85 if dishes else 1.15
	panel.add_theme_stylebox_override("panel", Style.box(HubTheme.CARD, 10, HubTheme.BORDER, 1))
	parent.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(Widgets.label(Text.get_text("ui_kitchen_dishes" if dishes else "ui_kitchen_ingredients"), 19))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "DishesScroll" if dishes else "IngredientsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	return rows


static func _row(parent: Control, entry: Dictionary, count: int, dish: bool) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var item_id: String = str(entry["item"])
	var item: Dictionary = DataLoader.get_record(item_id)
	var token: Token = Token.new()
	token.name = item_id
	token.item_id = item_id
	token.custom_minimum_size = Vector2(58, 58)
	token.tooltip_text = str(item["name"])
	if dish:
		var recipe: Dictionary = Inventory.recipe_for_dish(item_id)
		if not recipe.get("ingredients", []).is_empty():
			token.item_id = str(recipe["ingredients"][0]["item"])
		token.steps.assign(["cut", "fry"])
		token.plated = true
		token.draggable = false
		token.mouse_default_cursor_shape = Control.CURSOR_ARROW
	row.add_child(token)
	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(details)
	details.add_child(Widgets.label(str(item["name"]), 14))
	details.add_child(Widgets.label(Text.get_text("ui_kitchen_dish_detail" if dish else "ui_kitchen_available", {"count": count, "quality": int(entry.get("quality", 1))}), 12))
