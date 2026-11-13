extends Control

signal planet_requested(planet_id: String, trading: bool)
signal gate_requested(route_id: String)
signal npc_requested(npc_id: String, trading: bool)
signal delivery_requested(order_id: String)

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Text = preload("res://scripts/ui_text.gd")
const Navigation = preload("res://scripts/galaxy_navigation.gd")
const PICK_RADIUS: float = 16.0

var camera: Camera3D
var boost: bool = false
var selected_npc: String = ""
var _rows: Dictionary = {}
var _objects: Dictionary = {}
var _npcs: Dictionary = {}
var _delivery_buttons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EffectApplier.galaxy_changed.connect(rebuild)
	EffectApplier.flight_changed.connect(sync)
	EffectApplier.orders_changed.connect(rebuild)
	GameState.restored.connect(rebuild)
	rebuild()


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	_objects.clear()
	_npcs.clear()
	_delivery_buttons.clear()
	selected_npc = ""
	for object: Dictionary in DataLoader.get_record(str(GameState.state.get("current_system", ""))).get("objects", []):
		if object.get("type") not in ["gate", "planet"]:
			continue
		var object_id: String = str(object.get("id", object.get("to_route", "")))
		var row: Container = HBoxContainer.new() if object["type"] == "gate" else HFlowContainer.new()
		row.name = object_id
		row.add_theme_constant_override("separation", 5)
		if object["type"] == "planet":
			row.custom_minimum_size.x = 160
			row.add_theme_constant_override("h_separation", 5)
			row.add_theme_constant_override("v_separation", 5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_rows[object_id] = row
		_objects[object_id] = object
		if object["type"] == "gate":
			_add_button(row, "Enter", "ui_space_enter", gate_requested.emit.bind(object_id))
		elif object.get("inhabited", false):
			_add_button(row, "Trade", "ui_space_trade", planet_requested.emit.bind(object_id, true))
			_add_button(row, "Dialogue", "ui_space_dialogue", planet_requested.emit.bind(object_id, false))
		if object["type"] == "planet":
			for order_id: String in GameState.state["orders"]:
				if not Conditions.is_delivery_destination(order_id, object_id):
					continue
				var order: Dictionary = DataLoader.get_record(order_id)
				var delivery: Button = _add_button(row, "Deliver_" + order_id, "", delivery_requested.emit.bind(order_id))
				delivery.text = Text.get_text("ui_flight_deliver_direct", {"name": order["title"]})
				delivery.tooltip_text = str(order["title"]) + "\n" + str(order["description"])
				delivery.custom_minimum_size.x = 300
				delivery.clip_text = true
				_delivery_buttons[order_id] = delivery
		row.resized.connect(sync)
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["system"] != GameState.state["current_system"]:
			continue
		var npc_id: String = str(npc["id"])
		var row: HBoxContainer = HBoxContainer.new()
		row.name = npc_id
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 5)
		add_child(row)
		_npcs[npc_id] = row
		_add_button(row, "Dialogue", "ui_space_dialogue", npc_requested.emit.bind(npc_id, false))
		if npc.has("shop"):
			_add_button(row, "Trade", "ui_space_trade", npc_requested.emit.bind(npc_id, true))
	sync.call_deferred()


func sync() -> void:
	if not is_inside_tree() or camera == null:
		return
	for object_id: String in _rows:
		var object: Dictionary = _objects[object_id]
		var row: Container = _rows[object_id]
		var near: bool = Conditions.is_near(object["pos"]) if object["type"] == "gate" else Conditions.is_near_planet(object_id)
		_position_row(row, object["pos"], float(object.get("radius", 1.0)) + 2.5, near and row.get_child_count() > 0)
		if object["type"] == "gate":
			row.get_node("Enter").disabled = not Conditions.can_jump(object_id, boost)
			row.get_node("Enter").tooltip_text = _gate_tooltip(object_id)
		elif object.get("inhabited", false):
			var available: bool = Conditions.can_interact_planet(object_id)
			row.get_node("Trade").disabled = not available
			row.get_node("Dialogue").disabled = not available
	for order_id: String in _delivery_buttons:
		_delivery_buttons[order_id].disabled = not Conditions.can_deliver_order(order_id)
	for npc_id: String in _npcs:
		var row: HBoxContainer = _npcs[npc_id]
		var selected: bool = selected_npc == npc_id and GameState.state["flight"]["paused"] and Conditions.can_interact_npc(npc_id)
		_position_row(row, GameState.state["flight"]["npcs"][npc_id]["pos"], 6.0, selected)
		row.get_node("Dialogue").disabled = not Conditions.can_contact_npc(npc_id)
		if row.has_node("Trade"):
			row.get_node("Trade").disabled = not Conditions.can_trade_npc(npc_id)
		for button: Button in row.get_children():
			button.tooltip_text = str(DataLoader.get_record(npc_id)["name"])
			if not Conditions.can_interact_npc(npc_id):
				button.tooltip_text += "\n" + Text.get_text("ui_npc_approach_hint")


func pick_npc(point: Vector2) -> String:
	var nearest: float = PICK_RADIUS
	var result: String = ""
	for npc_id: String in _npcs:
		if not Conditions.can_interact_npc(npc_id):
			continue
		var world: Vector3 = Motion.world_position(GameState.state["flight"]["npcs"][npc_id]["pos"], 2.8)
		if camera.is_position_behind(world):
			continue
		var screen: Vector2 = camera.unproject_position(world)
		var distance: float = point.distance_to(screen)
		if Rect2(Vector2.ZERO, size).has_point(screen) and distance <= nearest:
			nearest = distance
			result = npc_id
	return result


func _position_row(row: Container, position: Array, height: float, available: bool) -> void:
	var world: Vector3 = Motion.world_position(position, height)
	row.visible = available and not camera.is_position_behind(world) and GameState.state["flight"]["encounter"].is_empty() and not Conditions.has_combat()
	var anchor: Vector2 = camera.unproject_position(world) - Vector2(row.size.x / 2.0, row.size.y + 4.0)
	row.position = anchor.clamp(Vector2(4, 4), (size - row.size - Vector2(4, 4)).max(Vector2(4, 4)))


func _gate_tooltip(route_id: String) -> String:
	var route: Dictionary = DataLoader.get_record(route_id)
	var path: Array[String] = [route_id]
	if Conditions.is_destination_known(route_id):
		return Text.get_text("ui_flight_known_gate", {"name": DataLoader.get_record(str(route["to"]))["name"]}) + "\n" + Text.get_text("ui_flight_gate_exact", {"fuel": Navigation.path_cost(path, "expected", boost), "days": int(route["days"])})
	return Text.get_text("ui_flight_gate_hint") + "\n" + Text.get_text("ui_flight_gate_range", {"min": Navigation.path_cost(path, "min", boost), "max": Navigation.path_cost(path, "max", boost), "days": int(route["days"])})


func _add_button(row: Container, node_name: String, text_id: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = Text.get_text(text_id) if not text_id.is_empty() else ""
	button.custom_minimum_size = Vector2(72, 32)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	row.add_child(button)
	return button
