extends Control

signal closed

const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Portrait = preload("res://scripts/heroine_portrait.gd")
const STAT_COLORS: Dictionary = {"attitude": Color(0.86, 0.4, 0.53), "mood": Color(0.28, 0.75, 0.68), "arousal": Color(0.68, 0.43, 0.9)}

var _cards: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.035, 0.84)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.035, 0.055, 0.08), 20, Color(0.3, 0.48, 0.55), 2))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 100
	panel.offset_right = -100
	panel.offset_top = 70
	panel.offset_bottom = -70
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Widgets.label(Text.get_text("ui_room_relationships"), 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Widgets.button("Close", "ui_room_close", func() -> void: closed.emit()))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_cards = GridContainer.new()
	_cards.name = "Characters"
	_cards.columns = 2
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 16)
	_cards.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_cards)
	EffectApplier.relationships_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	Widgets.clear(_cards)
	for heroine: Dictionary in DataLoader.get_records("heroines"):
		var heroine_id: String = str(heroine["id"])
		var column: VBoxContainer = Widgets.card(_cards, heroine_id, str(heroine["name"]))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		column.add_child(row)
		var portrait: Portrait = Portrait.new()
		portrait.heroine_id = heroine_id
		row.add_child(portrait)
		var values: VBoxContainer = VBoxContainer.new()
		values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		values.add_theme_constant_override("separation", 10)
		row.add_child(values)
		for stat: String in STAT_COLORS:
			values.add_child(Widgets.label(Text.get_text("ui_room_" + stat), 15))
			var bar: ProgressBar = ProgressBar.new()
			bar.name = stat
			bar.value = float(GameState.state["heroines"][heroine_id][stat])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(120, 16)
			bar.tooltip_text = Text.get_text("ui_room_stat_value", {"value": String.num(bar.value, 1)})
			bar.add_theme_stylebox_override("background", Style.box(Color(0.08, 0.13, 0.18), 6))
			bar.add_theme_stylebox_override("fill", Style.box(STAT_COLORS[stat], 6))
			values.add_child(bar)
