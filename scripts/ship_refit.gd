extends Control

signal closed

const Loadout = preload("res://scripts/ship_loadout.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Math = preload("res://scripts/combat_math.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Card = preload("res://scripts/refit_module_card.gd")
const Icon = preload("res://scripts/combat_icon.gd")
const Blueprint = preload("res://art/ui/ship_blueprint.svg")
const POSITIONS: Dictionary = {"engine": Vector2(0.48, 0.88), "maneuver_engine": Vector2(0.16, 0.78), "turret": Vector2(0.48, 0.45), "course": Vector2(0.48, 0.12), "armor": Vector2(0.83, 0.32), "shield": Vector2(0.83, 0.77), "broadside": Vector2(0.16, 0.45)}
const STATS: Dictionary = {"speed": "engine", "maneuver": "maneuver_engine", "broadside": "broadside", "course": "course", "turret": "turret"}
const ICON_KINDS: Dictionary = {"engine": "burn", "maneuver_engine": "evasion", "armor": "armor"}

var _selected: String = "engine"
var _diagram: TextureRect
var _catalog: VBoxContainer
var _catalog_scroll: ScrollContainer
var _module_cards: Dictionary = {}
var _summary: Label
var _notice: Label
var _slots: Dictionary = {}
var _bars: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.025, 0.045, 0.065), 0))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Widgets.label(Text.get_text("ui_refit_title"), 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Widgets.button("Close", "ui_refit_close", func() -> void: closed.emit()))
	column.add_child(Widgets.label(Text.get_text("ui_refit_help"), 16))
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var stats: HBoxContainer = HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 12)
	left.add_child(stats)
	for stat: String in STATS:
		var group: VBoxContainer = VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(group)
		group.add_child(Widgets.label(Text.get_text("ui_refit_" + stat), 14))
		var bar: ProgressBar = ProgressBar.new()
		bar.name = stat
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(80, 14)
		bar.add_theme_stylebox_override("background", Style.box(Color(0.08, 0.15, 0.2), 6))
		bar.add_theme_stylebox_override("fill", Style.box(Color(0.22, 0.78, 0.76), 6))
		group.add_child(bar)
		var value: Label = Widgets.label("", 14)
		group.add_child(value)
		_bars[stat] = {"bar": bar, "value": value}
	_summary = Widgets.label("", 16)
	left.add_child(_summary)
	_diagram = TextureRect.new()
	_diagram.name = "Blueprint"
	_diagram.texture = Blueprint
	_diagram.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_diagram.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diagram.custom_minimum_size = Vector2(570, 360)
	left.add_child(_diagram)
	for slot: String in Loadout.SLOTS:
		var cell: VBoxContainer = VBoxContainer.new()
		cell.name = slot
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 4)
		_diagram.add_child(cell)
		var button: Button = Button.new()
		button.name = "Socket"
		button.custom_minimum_size = Vector2(72, 64)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_select_slot.bind(slot))
		button.set_drag_forwarding(Callable(), _can_drop_module.bind(slot), _drop_module.bind(slot))
		cell.add_child(button)
		var icon: Icon = Icon.new()
		icon.kind = str(ICON_KINDS.get(slot, slot))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 9
		icon.offset_right = -9
		icon.offset_top = 7
		icon.offset_bottom = -7
		var heading: Label = Widgets.label(Text.get_text("ui_refit_slot_" + slot), 12)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.max_lines_visible = 2
		cell.add_child(heading)
		_slots[slot] = {"cell": cell, "button": button, "icon": icon}
	_diagram.resized.connect(_layout_slots)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 332
	body.add_child(right)
	right.add_child(Widgets.label(Text.get_text("ui_refit_catalog"), 21))
	_catalog_scroll = ScrollContainer.new()
	_catalog_scroll.name = "ModulesScroll"
	_catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_catalog_scroll)
	_catalog = VBoxContainer.new()
	_catalog.name = "Modules"
	_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog.add_theme_constant_override("separation", 18)
	_catalog_scroll.add_child(_catalog)
	_build_catalog()
	_notice = Widgets.label("", 15)
	column.add_child(_notice)
	EffectApplier.ship_changed.connect(refresh)
	refresh()
	_layout_slots.call_deferred()


func refresh() -> void:
	var ship: Dictionary = GameState.state["ship"]
	for slot: String in _slots:
		var module: Dictionary = Loadout.installed(ship, slot)
		_slots[slot]["icon"].visible = not module.is_empty()
		var button: Button = _slots[slot]["button"]
		button.tooltip_text = Text.get_text("ui_refit_slot_" + slot) + "\n" + str(module.get("name", Text.get_text("ui_refit_empty"))) + "\n" + _module_hint(module)
		button.add_theme_stylebox_override("normal", Style.box(Color(0.04, 0.10, 0.14, 0.94), 10, Color(0.35, 0.95, 0.85) if slot == _selected else Color(0.2, 0.4, 0.48), 2))
	for stat: String in STATS:
		var module: Dictionary = Loadout.installed(ship, STATS[stat])
		var maximum: float = 1.0
		for candidate: Dictionary in DataLoader.get_records("modules"):
			if Loadout.slot_for(candidate) == STATS[stat]:
				maximum = maxf(maximum, _stat_value(candidate, stat))
		var value: float = _stat_value(module, stat)
		_bars[stat]["bar"].max_value = maximum
		_bars[stat]["bar"].value = value
		_bars[stat]["value"].text = Text.get_text("ui_refit_level", {"level": int(value) - 1}) if stat == "maneuver" else String.num(value, 1)
		_bars[stat]["bar"].tooltip_text = _module_hint(module)
	_summary.text = Text.get_text("ui_refit_condition", {"current": String.num(float(ship["hull"]["current"]), 1), "max": ship["hull"]["max"], "shield": Loadout.shield_max(ship), "move": Math.movement_budget()})
	for card: Card in _module_cards.values():
		card.refresh_status()


func _build_catalog() -> void:
	for slot: String in Loadout.SLOTS:
		var category: VBoxContainer = VBoxContainer.new()
		category.name = slot
		category.add_theme_constant_override("separation", 8)
		_catalog.add_child(category)
		category.add_child(Widgets.label(Text.get_text("ui_refit_slot_" + slot), 17))
		var grid: GridContainer = GridContainer.new()
		grid.name = "Items"
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		category.add_child(grid)
		for module: Dictionary in DataLoader.get_records("modules"):
			if Loadout.slot_for(module) != slot:
				continue
			var card: Card = Card.new()
			card.name = str(module["id"])
			card.module_id = str(module["id"])
			card.kind = str(ICON_KINDS.get(slot, slot))
			card.tooltip_text = _module_hint(module)
			card.pressed.connect(_select_slot.bind(slot))
			grid.add_child(card)
			card.custom_minimum_size = Vector2(148, 122)
			_module_cards[module["id"]] = card


func _layout_slots() -> void:
	for slot: String in _slots:
		var cell: Control = _slots[slot]["cell"]
		cell.size = Vector2(128, 104)
		cell.position = (POSITIONS[slot] * _diagram.size - Vector2(64, 32)).clamp(Vector2.ZERO, _diagram.size - cell.size)


func _stat_value(module: Dictionary, stat: String) -> float:
	if stat == "speed":
		return float(module.get("speed", 0))
	if stat == "maneuver":
		return 1.0 + float(GameState.state["ship"]["movement"]["maneuver_level"]) + float(module.get("maneuver_level", 0))
	return Math.weapon_power(module) if not module.is_empty() else 0.0


func _module_hint(module: Dictionary) -> String:
	var hint: String = str(module.get("description", Text.get_text("ui_refit_empty")))
	if module.get("slot") == "weapon":
		hint += "\n" + Text.get_text("ui_refit_weapon_detail", {"min": module["dmg"][0], "max": module["dmg"][1], "range": module["range"], "ap": module["ap_cost"]})
	return hint


func _select_slot(slot: String) -> void:
	_selected = slot
	_notice.text = ""
	refresh()


func _can_drop_module(_position: Vector2, data: Variant, slot: String) -> bool:
	return data is String and Conditions.can_install_module(data, slot)


func _drop_module(_position: Vector2, data: Variant, slot: String) -> void:
	if not data is String:
		return
	_selected = slot
	_notice.text = Text.get_text("ui_refit_installed", {"name": DataLoader.get_record(data).get("name", "")}) if EffectApplier.install_module(data, slot) == OK else Text.get_text("ui_refit_failed")
