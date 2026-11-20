extends Control

signal closed
signal side_chosen(side: int)

const Battles = preload("res://scripts/ambient_battle_state.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")

var battle_id: String = ""
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.85)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.035, 0.055, 0.08), 16, Color(0.3, 0.6, 0.7), 2))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 40
	panel.offset_bottom = -40
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Widgets.label(Text.get_text("ui_battle_title"), 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Widgets.button("Close", "ui_room_close", func() -> void: closed.emit()))
	column.add_child(Widgets.label(Text.get_text("ui_battle_hint"), 15))
	var sides: HBoxContainer = HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(sides)
	var battle: Dictionary = Battles.find(battle_id, GameState.state["flight"]["battles"])
	if battle.is_empty():
		closed.emit.call_deferred()
		return
	for index: int in range(2):
		_build_side(sides, battle["sides"][index], index)
	EffectApplier.flight_changed.connect(refresh)
	refresh()


func _build_side(parent: Control, sources: Array, index: int) -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Side" + str(index)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	parent.add_child(column)
	column.add_child(Widgets.label(Text.get_text("ui_battle_role_" + str(DataLoader.get_record(str(sources[0]))["role"])), 22))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var ships: VBoxContainer = VBoxContainer.new()
	ships.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ships.add_theme_constant_override("separation", 12)
	scroll.add_child(ships)
	for npc_id: String in sources:
		var npc: Dictionary = DataLoader.get_record(npc_id)
		var profile: Dictionary = DataLoader.get_record(Loadouts.enemy_for_npc(npc_id))
		var card: VBoxContainer = Widgets.card(ships, npc_id, str(npc["name"]))
		card.add_child(Widgets.label(Text.get_text("ui_battle_stats", {"hull": int(profile["hull"]), "shield": int(profile["shield"]), "move": int(profile["speed"])}), 15))
		card.add_child(Widgets.label(str(profile["description"]), 14))
		for weapon: Dictionary in Loadouts.weapons(str(profile["id"]), GameState.state["flight"]["npcs"][npc_id]["weapons"]):
			card.add_child(Widgets.label(Text.get_text("ui_battle_weapon", {"name": weapon["name"], "min": int(weapon["dmg"][0]), "max": int(weapon["dmg"][1])}), 14))
	var button: Button = Widgets.button("Help" + str(index), "ui_battle_help", side_chosen.emit.bind(index))
	column.add_child(button)
	_buttons.append(button)


func refresh() -> void:
	for index: int in range(_buttons.size()):
		_buttons[index].disabled = not Conditions.can_join_battle(battle_id, index)
