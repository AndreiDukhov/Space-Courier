extends VBoxContainer

signal menu_toggled(open: bool)

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var heroine_id: String = ""
var _expanded: bool = false
var _notice: String = ""
var _queued: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	EffectApplier.domestic_changed.connect(_queue_refresh)
	Clock.time_changed.connect(func(_day: int, _slot: String) -> void: _queue_refresh())
	refresh()


func refresh() -> void:
	_queued = false
	if not is_inside_tree():
		return
	Widgets.clear(self)
	var status: String = Conditions.meal_offer_status(heroine_id)
	if not _notice.is_empty():
		add_child(Widgets.label(_notice, 16))
	if not status.is_empty():
		add_child(Widgets.label(Text.get_text("ui_food_" + status), 16))
		_expanded = false
	menu_toggled.emit(_expanded)
	var kitchen: bool = GameState.state.get("location") == "hub_kitchen"
	if not _expanded:
		add_child(Widgets.button("MealMenu", "ui_food_menu" if kitchen else "ui_food_invite_menu", _open, status.is_empty() and Conditions.domestic_available()))
		return
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.y = 130
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var choices: VBoxContainer = VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 8)
	scroll.add_child(choices)
	var dishes: int = 0
	for index: int in range(GameState.state.get("inventory", []).size()):
		var entry: Dictionary = GameState.state["inventory"][index]
		var item: Dictionary = DataLoader.get_record(str(entry["item"]))
		if item.get("type") != "dish":
			continue
		dishes += 1
		var name: String = Text.get_text("ui_food_quality", {"dish": item["name"], "quality": int(entry["quality"])})
		choices.add_child(Widgets.label(name, 16))
		var allowed: bool = Conditions.can_use_food(index, heroine_id) if kitchen else Conditions.can_invite_to_meal(index, heroine_id)
		choices.add_child(Widgets.button("Offer_" + str(index), "ui_food_offer" if kitchen else "ui_food_invite", _choose.bind(index), allowed, {"dish": item["name"]}))
	if dishes == 0:
		choices.add_child(Widgets.label(Text.get_text("ui_food_no_dishes"), 16))
	add_child(Widgets.button("Back", "ui_food_back", _back))


func _open() -> void:
	_expanded = true
	_notice = ""
	refresh()


func _back() -> void:
	_expanded = false
	refresh()


func _choose(index: int) -> void:
	var kitchen: bool = GameState.state.get("location") == "hub_kitchen"
	var result: Error = EffectApplier.use_food(index, heroine_id) if kitchen else EffectApplier.invite_to_meal(index, heroine_id)
	_notice = Text.get_text("ui_home_error")
	if result == OK:
		var heroine_name: String = str(DataLoader.get_record(heroine_id)["name"])
		if kitchen:
			var heroine: Dictionary = GameState.state["heroines"][heroine_id]
			_notice = Text.get_text("ui_home_serve_result", {"name": heroine_name, "mood": String.num(float(heroine["mood"]), 1), "attitude": String.num(float(heroine["attitude"]), 1)})
		else:
			var invitation: Dictionary = GameState.state["meal_invites"][heroine_id]
			_notice = Text.get_text("ui_food_invited", {"name": heroine_name, "day": int(invitation["day"]), "slot": Text.get_text("ui_food_slot_" + str(invitation["time_slot"]))})
	_expanded = false
	_queue_refresh()


func _queue_refresh() -> void:
	if is_inside_tree() and not _queued:
		_queued = true
		refresh.call_deferred()
