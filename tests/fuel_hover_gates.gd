extends Node

const Loadout = preload("res://scripts/ship_loadout.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Validator = preload("res://scripts/data_validator.gd")
const Navigation = preload("res://scripts/galaxy_navigation.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Service = preload("res://scripts/hub_service.gd")
const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")

var check_count: int = 0
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Fuel modules and all content references validate")
	_check_tanks()
	_check_migration()
	await _check_hub()
	await _check_space()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Fuel, hover and gate checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _workshop() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	for module: Dictionary in DataLoader.get_records("modules"):
		GameState.state["module_storage"][module["id"]] = 1
	EffectApplier.move_player("hub_tech")


func _check_tanks() -> void:
	_workshop()
	_check(GameState.state["ship"]["slots"]["fuel_tank"] == 1 and Loadout.installed(GameState.state["ship"], "fuel_tank")["id"] == "fuel_tank_mk1", "A new ship has its baseline tank in the eighth socket")
	EffectApplier.apply_effects([{"fuel": -11.625}])
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.install_module("fuel_tank_mk2", "armor") == ERR_UNAVAILABLE and GameState.serialize() == before, "A tank cannot replace armor")
	_check(EffectApplier.install_module("fuel_tank_mk2", "fuel_tank") == OK and GameState.state["ship"]["fuel"] == {"current": 18.375, "max": 60}, "The upgrade doubles capacity and preserves fractional fuel")
	_check(GameState.state["money"] == before["money"] and GameState.state["time_slot"] == before["time_slot"] and GameState.state["ship"]["hull"] == before["ship"]["hull"], "The test tank replacement preserves money, time and hull")
	_round_trip("upgraded-tank")
	before = GameState.serialize()
	_check(EffectApplier.install_module("fuel_tank_mk2") == ERR_UNAVAILABLE and GameState.serialize() == before, "Reinstalling cannot stack the fuel bonus")
	EffectApplier.apply_effects([{"fuel": 1000}])
	before = GameState.serialize()
	_check(GameState.state["ship"]["fuel"]["current"] == 60 and EffectApplier.install_module("fuel_tank_mk1") == ERR_UNAVAILABLE and GameState.serialize() == before, "A smaller tank is rejected without discarding excess fuel")
	EffectApplier.apply_effects([{"fuel": -31.25}])
	_check(EffectApplier.install_module("fuel_tank_mk1") == OK and GameState.state["ship"]["fuel"] == {"current": 28.75, "max": 30}, "Downsizing is allowed after fuel drops below the smaller capacity")
	for bad: Variant in [-1, 0.5, "30", NAN]:
		var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
		for module: Dictionary in groups["modules"]:
			if module["id"] == "fuel_tank_mk2":
				module["fuel_bonus"] = bad
		_check(not Validator.validate(groups, DataLoader.record_sources).is_empty(), "Invalid fuel bonuses are rejected during content validation")


func _check_migration() -> void:
	_workshop()
	EffectApplier.apply_effects([{"fuel": -17.875}])
	var old: Dictionary = GameState.serialize()
	old["ship"]["slots"].erase("fuel_tank")
	old["ship"]["modules"].erase("fuel_tank_mk1")
	_check(GameState.restore(old) == OK and Loadout.installed(GameState.state["ship"], "fuel_tank")["id"] == "fuel_tank_mk1", "A seven-slot save gains the ordinary tank")
	_check(GameState.state["ship"]["fuel"] == {"current": 12.125, "max": 30}, "Migration preserves the fuel amount and capacity")
	_round_trip("migrated-tank")
	old["ship"]["fuel"]["max"] = 45
	_check(GameState.restore(old) == OK and GameState.state["ship"]["fuel"]["max"] == 45, "Migration preserves a previously balanced base capacity")
	_check(EffectApplier.install_module("fuel_tank_mk2") == OK and GameState.state["ship"]["fuel"]["max"] == 75, "The bonus is added to the saved base instead of hardcoding sixty")
	var valid: Dictionary = GameState.serialize()
	var invalid: Dictionary = valid.duplicate(true)
	invalid["ship"]["modules"].append("fuel_tank_mk1")
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == valid, "Two tanks cannot occupy the same saved slot")


func _check_hub() -> void:
	_workshop()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	for path: String in ["TechHotspot/Computer", "ShipHotspot/Ship"]:
		await _check_glow(hub.get_node(path), "workshop-monitor" if path.contains("Computer") else "workshop-ship")
	await _click(hub.get_node("ShipHotspot/Ship").get_global_rect().get_center())
	var refit: Control = hub.get_node("ShipRefit")
	_check(refit._slots.has("fuel_tank") and refit._catalog.has_node("fuel_tank") and refit._bars["fuel"]["bar"].value == 30, "The refit shows the tank socket, category and capacity bar")
	refit._catalog_scroll.ensure_control_visible(refit._module_cards["fuel_tank_mk2"])
	await _frames()
	await _drag(refit._module_cards["fuel_tank_mk2"], refit._slots["fuel_tank"]["button"])
	_check(GameState.state["ship"]["fuel"] == {"current": 30.0, "max": 60} and refit._bars["fuel"]["bar"].value == 60, "A real drag installs the tank and updates its capacity bar")
	_check(refit._summary.text.replace(".0", "").contains("30/60") and refit._slots["fuel_tank"]["button"].tooltip_text.contains("60"), "The tank capacity is shown in the ship summary and socket tooltip")
	var socket: Control = refit._slots["fuel_tank"]["button"]
	for slot: String in refit._slots:
		if slot != "fuel_tank":
			_check(not socket.get_global_rect().intersects(refit._slots[slot]["button"].get_global_rect()), "The eighth socket stays separate from every existing socket")
	await _capture("tank-refit")
	await _click(refit.find_child("Close", true, false).get_global_rect().get_center())
	Service.travel("hub_office")
	await _frames()
	await _check_glow(hub.get_node("OfficeHotspot/Computer"), "office-monitor")
	await _click(hub.get_node("OfficeHotspot/Computer").get_global_rect().get_center())
	_check(hub.get_node("%Terminal").visible, "The illuminated monitor still opens its normal menu")
	hub.queue_free()
	await _frames()


func _check_glow(button: Button, label: String) -> void:
	await _hover(Vector2(12, get_viewport().get_visible_rect().size.y - 12))
	await RenderingServer.frame_post_draw
	var point: Vector2 = button.get_global_rect().get_center()
	var before: float = _luminance(point)
	var saved: Dictionary = GameState.serialize()
	await _hover(point)
	await RenderingServer.frame_post_draw
	_check(button.get_draw_mode() == BaseButton.DRAW_HOVER and _luminance(point) > before, "Hover visibly brightens the active " + label)
	_check(GameState.serialize() == saved, "Hover does not activate the hotspot or spend a turn")
	await _capture(label)
	await _hover(Vector2(12, get_viewport().get_visible_rect().size.y - 12))
	_check(button.get_draw_mode() == BaseButton.DRAW_NORMAL, "Moving away removes the hotspot's hover state")


func _luminance(point: Vector2) -> float:
	var pixels: Image = get_viewport().get_texture().get_image()
	var pixel: Vector2i = Vector2i(point * Vector2(pixels.get_size()) / get_viewport().get_visible_rect().size)
	return pixels.get_pixelv(pixel).get_luminance()


func _check_space() -> void:
	_workshop()
	EffectApplier.install_module("fuel_tank_mk2")
	EffectApplier.launch_flight()
	EffectApplier.apply_effects([{"money": 5000}])
	_check(Conditions.can_buy_planet_fuel("earth_1", 30.0) and EffectApplier.buy_planet_fuel("earth_1", 30.0) == OK and GameState.state["ship"]["fuel"]["current"] == 60, "Planet refuelling fills the expanded tank")
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	_check(view.get_node("%FuelValue").text.replace(".0", "").contains("60/60"), "The fuel row displays the expanded capacity")
	var unknown: String = ""
	for object: Dictionary in DataLoader.get_record("sys_earth")["objects"]:
		if object["type"] != "gate":
			continue
		var route: String = str(object["to_route"])
		_check(view._indicators.has_node(route), "Every local wormhole receives an edge indicator")
		_check(view._indicators.get_node(route + "/Content/Name").text == view.gate_name(route, int(view._indicators._gate_numbers[route])), "The edge and world use the same gate label")
		if not Conditions.is_destination_known(route):
			unknown = route
	_check(not unknown.is_empty(), "An unexplored local gate is available for the disclosure check")
	if not unknown.is_empty():
		var destination: String = str(DataLoader.get_record(str(DataLoader.get_record(unknown)["to"]))["name"])
		_check(not view._indicators.get_node(unknown + "/Content/Name").text.contains(destination), "An unknown gate arrow does not disclose its destination")
		EffectApplier.apply_effects([{"unlock_route": unknown}])
		await _frames()
		_check(view._indicators.get_node(unknown + "/Content/Name").text.contains(destination), "Learning the route updates the arrow's destination")
		_round_trip("known-gate")
	await _frames()
	_check_indicator_layout(view._indicators, "initial Earth flight")
	await _capture("gates")
	for system: Dictionary in DataLoader.get_records("systems"):
		GameState.state["current_system"] = system["id"]
		GameState.state["systems"][system["id"]] = "visited"
		EffectApplier.galaxy_changed.emit()
		await _frames()
		var expected: int = system["objects"].filter(func(object: Dictionary) -> bool: return object["type"] in ["planet", "station", "gate"]).size()
		_check(view._indicators.get_child_count() == expected, "The indicator inventory matches planets, stations and gates in " + str(system["id"]))
		for position: Vector2 in [Vector2(120, 120), Vector2(2880, 120), Vector2(120, 2160), Vector2(2880, 2160)]:
			GameState.state["flight"]["pos"] = Motion.coordinates(position)
			GameState.state["flight"]["target"] = Motion.coordinates(position)
			EffectApplier.flight_changed.emit()
			await _frames()
			_check_indicator_layout(view._indicators, str(system["id"]) + str(position))
	view.queue_free()
	await _frames()


func _check_indicator_layout(indicators: Control, label: String) -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, indicators.size)
	var visible: Array[Rect2] = []
	var clear: bool = true
	var details: String = ""
	for row: Control in indicators.get_children():
		if not row.visible:
			continue
		var rect: Rect2 = row.get_rect()
		clear = clear and bounds.encloses(rect) and not rect.intersects(indicators.reserved_rect)
		if not bounds.encloses(rect) or rect.intersects(indicators.reserved_rect):
			details += " " + str(row.name) + str(rect)
		for other: Rect2 in visible:
			clear = clear and not rect.intersects(other)
			if rect.intersects(other):
				details += " overlap " + str(row.name) + str(rect) + str(other)
		visible.append(rect)
	_check(clear, "Labels fit the map and avoid each other and the quest button in " + label + details)


func _round_trip(label: String) -> void:
	var saved: Dictionary = GameState.serialize()
	var write_error: Error = GameState.save_game("user://fuel-" + label + ".json")
	var read_error: Error = GameState.load_game("user://fuel-" + label + ".json")
	if GameState.serialize() != saved:
		print("Round-trip difference ", label, " ", _difference(saved, GameState.serialize(), "state"))
	_check(write_error == OK and read_error == OK and GameState.serialize() == saved, "The " + label + " state round-trips through JSON (%s, %s)" % [write_error, read_error])


func _difference(left: Variant, right: Variant, path: String) -> String:
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key):
				return path + "." + str(key) + " missing"
			if left[key] != right[key]:
				return _difference(left[key], right[key], path + "." + str(key))
	elif left is Array and right is Array and left.size() == right.size():
		for index: int in range(left.size()):
			if left[index] != right[index]:
				return _difference(left[index], right[index], path + "[" + str(index) + "]")
	return path + " expected " + str(left) + " actual " + str(right)


func _hover(position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	get_viewport().push_input(event, true)
	await _frames()


func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		get_viewport().push_input(event, true)
	await _frames()


func _drag(source: Control, target: Control) -> void:
	var from: Vector2 = source.get_global_rect().get_center()
	var to: Vector2 = target.get_global_rect().get_center()
	await _hover(from)
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	for position: Vector2 in [from + Vector2(24, 0), to]:
		var move: InputEventMouseMotion = InputEventMouseMotion.new()
		move.position = position
		move.relative = position - from
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(move, true)
		await get_tree().process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	get_viewport().push_input(up, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture-fuel-hover-gates" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var suffix: String = "-small" if "--small" in OS.get_cmdline_user_args() else ""
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/fuel-hover-gates-" + label + suffix + ".png") == OK, "The " + label + " screen renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
