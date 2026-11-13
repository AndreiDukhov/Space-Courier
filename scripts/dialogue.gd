extends Control

signal choice_resolved(scene_id: String, result: Error)

const Runner = preload("res://scripts/dialogue_runner.gd")
const MealConversation = preload("res://scripts/meal_conversation.gd")
const Text = preload("res://scripts/ui_text.gd")
const Portrait = preload("res://scripts/heroine_portrait.gd")

@onready var scene_list: VBoxContainer = %SceneList
@onready var stat_list: VBoxContainer = %Stats
@onready var line_list: VBoxContainer = %Lines
@onready var choice_list: VBoxContainer = %Choices
@onready var heroine_label: Label = %HeroineName
@onready var scene_label: Label = %SceneId
@onready var time_label: Label = %Time

var _selected_scene_id: String = ""
var _speaker_filter: String = ""
var _portrait: Portrait


func _ready() -> void:
	if not DataLoader.load_errors.is_empty():
		return
	if GameState.state.is_empty():
		GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	Clock.time_changed.connect(_on_time_changed)
	_portrait = Portrait.new()
	_portrait.name = "HeroinePortrait"
	if _speaker_filter.is_empty():
		get_node("Margin/Columns/Sidebar/Portrait").add_child(_portrait)
		_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var content: VBoxContainer = get_node("Margin/Columns/Content")
		var heading: HBoxContainer = HBoxContainer.new()
		heading.name = "ConversationHeader"
		heading.add_theme_constant_override("separation", 14)
		content.add_child(heading)
		content.move_child(heading, 0)
		heading.add_child(_portrait)
		content.remove_child(scene_label)
		heading.add_child(scene_label)
		scene_label.owner = self
		scene_label.unique_name_in_owner = true
		scene_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scene_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refresh()
	if not _speaker_filter.is_empty():
		var meals: MealConversation = MealConversation.new()
		meals.name = "MealConversation"
		meals.heroine_id = _speaker_filter
		meals.menu_toggled.connect(func(open: bool) -> void: choice_list.visible = not open)
		get_node("Margin/Columns/Content").add_child(meals)


func refresh(preferred_scene_id: String = "") -> void:
	_refresh_stats()
	_clear(scene_list)
	var scenes: Array[Dictionary] = _scenes_for_view()
	var available_ids: Array[String] = []
	for scene: Dictionary in scenes:
		var scene_id: String = str(scene["id"])
		var available: bool = Runner.is_available(scene)
		var button: Button = Button.new()
		button.name = scene_id
		button.text = scene_id
		button.disabled = not available
		button.tooltip_text = JSON.stringify(scene.get("conditions", []), "\t")
		button.custom_minimum_size.y = 42.0
		button.pressed.connect(select_scene.bind(scene_id))
		scene_list.add_child(button)
		if available:
			available_ids.append(scene_id)
	if preferred_scene_id in available_ids:
		_selected_scene_id = preferred_scene_id
	elif _selected_scene_id not in available_ids and not available_ids.is_empty():
		_selected_scene_id = available_ids[0]
	elif not _speaker_filter.is_empty() and available_ids.is_empty():
		_selected_scene_id = ""
	_render_scene(DataLoader.get_record(_selected_scene_id))


func select_scene(scene_id: String) -> bool:
	var scene: Dictionary = DataLoader.get_record(scene_id)
	if not DataLoader.record_sources.has("scenes/" + scene_id) or not Runner.is_available(scene):
		return false
	_selected_scene_id = scene_id
	_render_scene(scene)
	return true


func configure_for_hub(heroine_id: String) -> void:
	_speaker_filter = heroine_id
	get_node("Margin/Columns/Sidebar").hide()
	get_node("Margin/Columns/Divider").hide()
	var margin: MarginContainer = get_node("Margin")
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	get_node("Margin/Columns/Content").add_theme_constant_override("separation", 14)
	get_node("Margin/Columns/Content/Scroll/Lines").add_theme_constant_override("separation", 8)
	get_node("Margin/Columns/Content/SceneId").add_theme_font_size_override("font_size", 22)


func _scenes_for_view() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scene: Dictionary in DataLoader.get_records("scenes"):
		if _speaker_filter.is_empty():
			result.append(scene)
			continue
		for line: Dictionary in scene.get("lines", []):
			if line.get("who") == _speaker_filter:
				result.append(scene)
				break
	return result


func _render_scene(scene: Dictionary) -> void:
	_refresh_stats()
	_clear(line_list)
	_clear(choice_list)
	scene_label.text = str(scene.get("id", ""))
	if not _speaker_filter.is_empty() and scene.is_empty():
		scene_label.text = Text.get_text("ui_food_talk_title", {"name": DataLoader.get_record(_speaker_filter).get("name", "")})
		var placeholder: Label = Label.new()
		placeholder.text = Text.get_text("ui_food_talk_placeholder")
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line_list.add_child(placeholder)
	for line: Dictionary in scene.get("lines", []):
		var speaker_id: String = str(line.get("who", ""))
		var speaker: Dictionary = DataLoader.get_record(speaker_id)
		var speaker_label: Label = Label.new()
		speaker_label.text = str(speaker.get("name", speaker_id))
		speaker_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.9))
		line_list.add_child(speaker_label)
		var text_label: Label = Label.new()
		text_label.text = str(line.get("text", ""))
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.add_theme_font_size_override("font_size", 22 if _speaker_filter.is_empty() else 20)
		text_label.custom_minimum_size.y = 46.0 if _speaker_filter.is_empty() else 32.0
		line_list.add_child(text_label)
	if not Runner.is_available(scene):
		return
	for choice: Dictionary in scene.get("choices", []):
		var button: Button = Button.new()
		button.name = str(choice["id"])
		button.text = str(choice["text"])
		button.custom_minimum_size.y = 48.0
		button.pressed.connect(_on_choice_pressed.bind(str(scene["id"]), str(choice["id"])))
		choice_list.add_child(button)


func _refresh_stats() -> void:
	_clear(stat_list)
	var heroines: Array[Dictionary] = DataLoader.get_records("heroines")
	if heroines.is_empty():
		return
	var blueprint: Dictionary = heroines[0]
	if not _speaker_filter.is_empty():
		blueprint = DataLoader.get_record(_speaker_filter)
	for line: Dictionary in DataLoader.get_record(_selected_scene_id).get("lines", []):
		var speaker: String = str(line.get("who", ""))
		if GameState.state.get("heroines", {}).has(speaker):
			blueprint = DataLoader.get_record(speaker)
			break
	heroine_label.text = str(blueprint.get("name", ""))
	if is_instance_valid(_portrait):
		_portrait.heroine_id = str(blueprint.get("id", ""))
		_portrait.refresh()
	var stats: Dictionary = GameState.state.get("heroines", {}).get(blueprint["id"], {})
	for stat_name: String in blueprint.get("stats", {}):
		var label: Label = Label.new()
		label.name = stat_name
		label.text = "%s: %s" % [stat_name, String.num(float(stats.get(stat_name, 0)), 2)]
		label.add_theme_font_size_override("font_size", 20)
		stat_list.add_child(label)
	time_label.text = "%d / %s" % [Clock.current_day(), Clock.current_slot()]


func _on_choice_pressed(scene_id: String, choice_id: String) -> void:
	var scene: Dictionary = DataLoader.get_record(scene_id)
	var result: Error = Runner.choose(scene_id, choice_id)
	if result != OK and result != ERR_UNAVAILABLE:
		push_error("Dialogue: could not apply choice '%s' in '%s'" % [choice_id, scene_id])
	var preferred_scene_id: String = ""
	for next_id: String in scene.get("next", []):
		if Runner.is_available(DataLoader.get_record(next_id)):
			preferred_scene_id = next_id
			break
	refresh(preferred_scene_id)
	choice_resolved.emit(scene_id, result)


func _on_time_changed(_day: int, _time_slot: String) -> void:
	_refresh_stats()


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
