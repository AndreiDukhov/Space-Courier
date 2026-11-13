extends Control

signal close_requested
signal flight_requested

const Navigation = preload("res://scripts/galaxy_navigation.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const State = preload("res://scripts/galaxy_state.gd")
const Text = preload("res://scripts/ui_text.gd")
const Chart = preload("res://scripts/galaxy_chart.gd")
const QuestButton = preload("res://scripts/quest_button.gd")

@onready var chart: Chart = %Chart
var _selected_system: String = ""
var _boost: bool = false
var _next_route: String = ""
var _journal: QuestButton


func _ready() -> void:
	if GameState.state.is_empty():
		GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_selected_system = str(GameState.state["current_system"])
	_journal = QuestButton.new()
	_journal.name = "QuestButton"
	_journal.host = self
	%MapSurface.add_child(_journal)
	_journal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart.system_selected.connect(select_system)
	EffectApplier.galaxy_changed.connect(refresh)
	EffectApplier.orders_changed.connect(refresh)
	GameState.restored.connect(_on_restored)
	%Jump.pressed.connect(_jump)
	%Close.pressed.connect(_close)
	%Refuel.pressed.connect(_refuel)
	%Tow.pressed.connect(_tow)
	%Boost.toggled.connect(_on_boost)
	%Save.pressed.connect(_save)
	%Load.pressed.connect(_load)
	%Title.text = Text.get_text("ui_map_title")
	%Legend.text = Text.get_text("ui_map_legend")
	%Jump.text = Text.get_text("ui_flight_launch")
	%Jump.tooltip_text = Text.get_text("ui_flight_map_info")
	%Close.text = Text.get_text("ui_map_close")
	%Boost.text = Text.get_text("ui_map_boost")
	%Boost.visible = false
	%Tow.text = Text.get_text("ui_map_tow", {"price": EffectApplier.TOW_FEE})
	%Save.text = Text.get_text("ui_map_save")
	%Load.text = Text.get_text("ui_map_load")
	refresh()


func select_system(system_id: String) -> void:
	if GameState.state["systems"].get(system_id, "hidden") == "hidden":
		return
	_selected_system = system_id
	refresh()
	if Conditions.can_fly() and system_id == GameState.state["current_system"]:
		EffectApplier.stop_autopilot()
		close_requested.emit()
		return
	if Conditions.can_fly() and EffectApplier.start_autopilot(system_id) == OK:
		close_requested.emit()


func refresh() -> void:
	if not is_node_ready():
		return
	var fuel: Dictionary = GameState.state["ship"]["fuel"]
	%Resources.text = Text.get_text("ui_map_resources", {"day": Clock.current_day(), "fuel": String.num(float(fuel["current"]), 2), "max": fuel["max"], "money": GameState.state["money"]})
	%Current.text = Text.get_text("ui_map_current", {"name": DataLoader.get_record(str(GameState.state["current_system"]))["name"]})
	%Close.disabled = false
	%Jump.text = Text.get_text("ui_flight_back" if Conditions.can_fly() else "ui_flight_launch")
	%Tow.visible = Conditions.can_request_tow()
	%Refuel.disabled = not Conditions.can_refuel()
	%Refuel.visible = Conditions.can_launch()
	%Load.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)
	var system: Dictionary = DataLoader.get_record(str(GameState.state["current_system"]))
	%Refuel.text = Text.get_text("ui_map_refuel", {"price": ceili((float(fuel["max"]) - float(fuel["current"])) * int(system["refuel"]["price_per_unit"]))}) if system["refuel"]["available"] else Text.get_text("ui_map_no_refuel")
	chart.selected_system = _selected_system
	chart.refresh()
	_refresh_plan()
	_refresh_routes()


func _refresh_plan() -> void:
	var path: Array[String] = Navigation.plan(_selected_system, "", _boost)
	_next_route = path[0] if not path.is_empty() else ""
	%Jump.disabled = not Conditions.can_launch() and not Conditions.can_fly()
	if path.is_empty():
		%Plan.text = str(DataLoader.get_record(_selected_system).get("name", "")) if _selected_system == GameState.state["current_system"] else Text.get_text("ui_map_no_path")
	else:
		var names: PackedStringArray = [str(DataLoader.get_record(str(GameState.state["current_system"]))["name"])]
		for route_id: String in path:
			names.append(str(DataLoader.get_record(str(DataLoader.get_record(route_id)["to"]))["name"]))
		%Plan.text = Text.get_text("ui_map_plan", {"names": " → ".join(names), "fuel": Navigation.path_cost(path, "expected", _boost)})
	var warning_id: String = Navigation.return_warning(_selected_system, path, _boost)
	%Warning.text = Text.get_text(warning_id) if not warning_id.is_empty() else ""


func _refresh_routes() -> void:
	for child: Node in %Routes.get_children():
		%Routes.remove_child(child)
		child.queue_free()
	for route: Dictionary in Navigation.visible_routes():
		if route["from"] != GameState.state["current_system"] and route["to"] != GameState.state["current_system"]:
			continue
		var column: VBoxContainer = VBoxContainer.new()
		column.name = str(route["id"])
		column.add_theme_constant_override("separation", 5)
		%Routes.add_child(column)
		var button: Button = Button.new()
		button.name = "Select"
		button.text = Text.get_text("ui_map_route", {"from": DataLoader.get_record(str(route["from"]))["name"], "to": DataLoader.get_record(str(route["to"]))["name"]})
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(select_system.bind(str(route["to"])))
		column.add_child(button)
		var description: Label = Label.new()
		description.name = "Fuel"
		var one_route: Array[String] = [str(route["id"])]
		if route["id"] in GameState.state["known_routes"]:
			description.text = Text.get_text("ui_map_exact", {"fuel": Navigation.path_cost(one_route, "expected", _boost), "days": int(route["days"])})
		else:
			description.text = Text.get_text("ui_map_range", {"min": Navigation.path_cost(one_route, "min", _boost), "max": Navigation.path_cost(one_route, "max", _boost), "days": int(route["days"])})
		description.add_theme_font_size_override("font_size", 13)
		column.add_child(description)
		if Conditions.can_sell_route(str(route["id"])):
			var sell: Button = Button.new()
			sell.name = "Sell"
			sell.text = Text.get_text("ui_map_sell", {"price": int(route["map_value"])})
			sell.pressed.connect(_sell.bind(str(route["id"])))
			column.add_child(sell)
		elif route["id"] in GameState.state["public_routes"]:
			var public_label: Label = Label.new()
			public_label.text = Text.get_text("ui_map_public")
			public_label.add_theme_font_size_override("font_size", 12)
			column.add_child(public_label)


func _jump() -> void:
	if Conditions.can_fly():
		close_requested.emit()
	elif Conditions.can_launch():
		flight_requested.emit()


func _close() -> void:
	close_requested.emit()


func _refuel() -> void:
	EffectApplier.refuel_ship()


func _tow() -> void:
	EffectApplier.request_tow()


func _sell(route_id: String) -> void:
	EffectApplier.sell_route(route_id)


func _on_boost(enabled: bool) -> void:
	_boost = enabled
	refresh()


func _on_restored() -> void:
	_selected_system = str(GameState.state["current_system"])
	refresh()


func _save() -> void:
	%Notice.text = Text.get_text("ui_map_saved" if GameState.save_game() == OK else "ui_map_save_error")
	refresh()


func _load() -> void:
	if GameState.load_game() != OK:
		%Notice.text = Text.get_text("ui_map_save_error")
	refresh()
