extends PanelContainer

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/hub_widgets.gd")
const Loadouts = preload("res://scripts/enemy_loadout.gd")

var _event_id: String = ""


func _ready() -> void:
	%EncounterTitle.text = Text.get_text("ui_encounter_title")
	%EncounterBody.text = Text.get_text("ui_encounter_body")
	add_theme_stylebox_override("panel", Widgets.box(Color(0.035, 0.065, 0.1, 0.99), 16, Color(0.35, 0.8, 0.75), 2))
	%EncounterSave.text = Text.get_text("ui_map_save")
	%EncounterLoad.text = Text.get_text("ui_map_load")
	%EncounterSave.pressed.connect(_save)
	%EncounterLoad.pressed.connect(_load)
	EffectApplier.flight_changed.connect(refresh)
	GameState.restored.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	var event_id: String = str(GameState.state.get("flight", {}).get("encounter", ""))
	visible = not event_id.is_empty()
	%EncounterLoad.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)
	_refresh_ship_preview(event_id)
	if event_id == _event_id:
		for index: int in range(%EventChoices.get_child_count()):
			%EventChoices.get_child(index).disabled = not Conditions.can_choose_flight_event(event_id, index)
		return
	_event_id = event_id
	%EncounterNotice.text = ""
	for child: Node in %EventChoices.get_children():
		%EventChoices.remove_child(child)
		child.queue_free()
	if event_id.is_empty():
		return
	var options: Array = DataLoader.get_record(event_id).get("options", [])
	for i: int in range(options.size()):
		var button: Button = Button.new()
		button.name = "Option" + str(i)
		button.text = str(options[i]["text"])
		button.custom_minimum_size.y = 42.0
		button.disabled = not Conditions.can_choose_flight_event(event_id, i)
		button.pressed.connect(_choose.bind(event_id, i))
		%EventChoices.add_child(button)


func _refresh_ship_preview(event_id: String) -> void:
	var enemy_id: String = Loadouts.enemy_for_event(event_id)
	%ShipDescriptionScroll.visible = not enemy_id.is_empty()
	anchor_left = 0.17 if not enemy_id.is_empty() else 0.25
	anchor_right = 0.83 if not enemy_id.is_empty() else 0.75
	anchor_top = 0.08 if not enemy_id.is_empty() else 0.3
	anchor_bottom = 0.92 if not enemy_id.is_empty() else 0.7
	if enemy_id.is_empty():
		return
	var enemy: Dictionary = DataLoader.get_record(enemy_id)
	var npc_id: String = Conditions.encounter_npc(event_id)
	var weapon_ids: Array = GameState.state["flight"]["npcs"][npc_id]["weapons"] if not npc_id.is_empty() else []
	var weapons: Array = Loadouts.weapons(enemy_id, weapon_ids) if not npc_id.is_empty() else enemy["weapons"]
	var lines: Array[String] = [Text.get_text("ui_enemy_ship_summary", {"name": enemy["name"], "hull": int(enemy["hull"]), "shield": int(enemy["shield"]), "movement": int(enemy["speed"]), "description": enemy["description"]}), Text.get_text("ui_enemy_equipped" if not npc_id.is_empty() else "ui_enemy_possible")]
	for weapon: Dictionary in weapons:
		lines.append(Text.get_text("ui_enemy_weapon_summary", {"name": weapon["name"], "min": int(weapon["dmg"][0]), "max": int(weapon["dmg"][1]), "range": int(weapon["range"]), "ap": int(weapon["ap_cost"]), "arc": int(weapon["arc_degrees"])}))
	lines.append(Text.get_text("ui_enemy_one_shot"))
	%ShipDescription.text = "\n".join(lines)


func _choose(event_id: String, option_index: int) -> void:
	EffectApplier.choose_flight_event(event_id, option_index)
	refresh()


func _save() -> void:
	%EncounterNotice.text = Text.get_text("ui_map_saved" if GameState.save_game() == OK else "ui_map_save_error")
	refresh()


func _load() -> void:
	if GameState.load_game() != OK:
		%EncounterNotice.text = Text.get_text("ui_map_save_error")
	refresh()
