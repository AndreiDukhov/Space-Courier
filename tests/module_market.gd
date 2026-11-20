extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Loadout = preload("res://scripts/ship_loadout.gd")
const Storage = preload("res://scripts/module_storage.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Validator = preload("res://scripts/data_validator.gd")
const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatState = preload("res://scripts/combat_state.gd")
var check_count: int = 0
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All content references validate")
	_check_content()
	_check_delivery()
	_check_stations()
	_check_progression()
	_check_unique_refits()
	_check_save()
	await _check_pc()
	await _check_station_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Module market checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	GameState.state["money"] = 100000


func _check_content() -> void:
	_check(DataLoader.get_records("modules").size() == 47 and DataLoader.get_record("hub_module_parts")["modules"].size() == 31, "The catalog contains 47 modules and 31 ordinary parts")
	for faction: String in ["mafia", "police"]:
		var special: Array = DataLoader.get_record(faction + "_module_parts")["modules"]
		_check(special.size() == 8, "Each faction covers all eight ship slots")
		for id: String in special:
			_check(id not in DataLoader.get_record("hub_module_parts")["modules"], "Faction technology is excluded from the ordinary catalog")
	for mount: String in ["turret", "course", "broadside"]:
		var coverage: Dictionary = {}
		var damage: Dictionary = {}
		for module: Dictionary in DataLoader.get_records("modules"):
			if module.get("mount") == mount:
				coverage[int(module["arc_degrees"])] = true
				damage[int(module["dmg"][1])] = true
		_check(coverage.size() >= 3 and damage.size() >= 4, "Every weapon mount has different damage and coverage choices")
	for module: Dictionary in DataLoader.get_records("modules"):
		_check(module["cost"] > 0, "Every part has a positive price")
	_check(DataLoader.get_record("police_turret")["cost"] > DataLoader.get_record("turret_array")["cost"] and DataLoader.get_record("turret_array")["cost"] > DataLoader.get_record("cannon_s")["cost"], "Combined improvements cost more")


func _check_delivery() -> void:
	_new()
	_check(GameState.state["module_storage"].is_empty() and not Conditions.can_buy_module("hub_module_parts", "fuel_tank_mk2"), "There are no free spares or remote PC purchases")
	EffectApplier.move_player("hub_tech")
	_check(not Conditions.can_install_module("fuel_tank_mk2"), "Unowned upgrades cannot be installed")
	GameState.state["money"] = 0
	var saved: Dictionary = GameState.serialize()
	_check(EffectApplier.buy_module("hub_module_parts", "fuel_tank_mk2") == ERR_UNAVAILABLE and GameState.serialize() == saved, "Insufficient funds reject purchases atomically")
	var price: int = int(DataLoader.get_record("fuel_tank_mk2")["cost"])
	GameState.state["money"] = price * 3
	_check(EffectApplier.buy_module("hub_module_parts", "fuel_tank_mk2") == OK and GameState.state["money"] == price * 2, "Orders charge the JSON price immediately")
	_check(Storage.count("fuel_tank_mk2") == 0 and Storage.pending("fuel_tank_mk2") == 1 and not Conditions.can_install_module("fuel_tank_mk2"), "Parts in transit cannot be installed")
	_round_trip("in-transit")
	Clock.advance_slots(3)
	_check(Clock.current_day() == 1 and Storage.count("fuel_tank_mk2") == 0, "Delivery waits until the following day")
	Clock.advance_slots()
	_check(Storage.count("fuel_tank_mk2") == 1 and Storage.pending("fuel_tank_mk2") == 0, "The next morning transfers paid orders to storage")
	Clock.advance_slots(8)
	_check(Storage.count("fuel_tank_mk2") == 1, "Delivered orders cannot pay twice")
	_check(EffectApplier.buy_module("hub_module_parts", "fuel_tank_mk2") == OK and EffectApplier.buy_module("hub_module_parts", "fuel_tank_mk2") == OK, "Multiple orders for the same part are retained")
	Clock.advance_slots(8)
	_check(Storage.count("fuel_tank_mk2") == 3 and GameState.state["money"] == 0, "Skipping days delivers every purchase exactly once")
	_check(EffectApplier.install_module("fuel_tank_mk2") == OK and Storage.count("fuel_tank_mk2") == 2 and Storage.count("fuel_tank_mk1") == 1, "Installation consumes a spare and returns the previous module")
	_check(GameState.state["ship"]["fuel"] == {"current": 30.0, "max": 60}, "Purchased tanks preserve existing fuel")
	_check(EffectApplier.install_module("fuel_tank_mk1") == OK and Storage.count("fuel_tank_mk2") == 3 and Storage.count("fuel_tank_mk1") == 0, "Swapping back conserves all parts")
	_round_trip("refitted")


func _station(id: String, system: String) -> void:
	_new()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	GameState.state["current_system"] = system
	GameState.state["systems"][system] = "visited"
	var station: Dictionary = Conditions.space_object(id)
	GameState.state["flight"]["pos"] = station["pos"].duplicate()
	GameState.state["flight"]["target"] = station["pos"].duplicate()


func _check_stations() -> void:
	for row: Array in [["station_police", "sys_earth", "police", "state", "mafia"], ["station_pirate", "sys_alpha", "mafia", "mafia", "state"]]:
		_station(row[0], row[1])
		var shop: String = row[2] + "_module_parts"
		var module: String = row[2] + "_turret"
		_check(Conditions.can_interact_planet(row[0]) and Conditions.can_use_shop(shop), "Nearby stations permit trading")
		GameState.state["reputation"][row[4]] = 100
		GameState.state["reputation"][row[3]] = 29
		var saved: Dictionary = GameState.serialize()
		_check(EffectApplier.buy_module(shop, module) == ERR_UNAVAILABLE and GameState.serialize() == saved, "The correct faction must reach reputation thirty")
		GameState.state["reputation"][row[3]] = 30
		var money: int = int(GameState.state["money"])
		_check(EffectApplier.buy_module(shop, module) == OK and Storage.count(module) == 1 and GameState.state["module_deliveries"].is_empty() and GameState.state["money"] == money - int(DataLoader.get_record(module)["cost"]), "Station parts are charged and handed over immediately")
		_check(not Conditions.can_install_module(module) and not Conditions.can_buy_planet_fuel(row[0], 1), "Stations cannot perform workshop installations or planetary refuelling")
		GameState.state["flight"]["pos"] = Motion.coordinates(Vector2(10, 10))
		_check(not Conditions.can_use_shop(shop), "Distant station access is rejected")
		_round_trip("station-" + row[2])


func _check_progression() -> void:
	for source: String in ["state", "crime"]:
		_new()
		for number: int in range(1, 6):
			var id: String = "ord_%s_%02d" % [source, number]
			GameState.state["current_system"] = "sys_earth"
			GameState.state["location"] = "hub_office"
			_check(EffectApplier.accept_order(id) == OK, "Faction reputation opens the next test contract")
			GameState.state["current_system"] = "sys_colony_3"
			GameState.state["systems"]["sys_colony_3"] = "visited"
			GameState.state["location"] = "ship_bridge"
			GameState.state["flight"]["pos"] = Conditions.space_object("colony_3_1")["pos"].duplicate()
			_check(EffectApplier.deliver_order(id) == OK, "The existing planet delivery action grants faction reputation")
		_check(GameState.state["reputation"]["state" if source == "state" else "mafia"] == 30, "Normal contracts can reach the unique module threshold from zero")


func _check_unique_refits() -> void:
	for faction: String in ["police", "mafia"]:
		_station("station_police" if faction == "police" else "station_pirate", "sys_earth" if faction == "police" else "sys_alpha")
		GameState.state["reputation"]["state" if faction == "police" else "mafia"] = 30
		var stock: Array = DataLoader.get_record(faction + "_module_parts")["modules"]
		for id: String in stock:
			_check(EffectApplier.buy_module(faction + "_module_parts", id) == OK, "Every faction module can be purchased at its own station")
		GameState.state["current_system"] = "sys_earth"
		GameState.state["location"] = "hub_tech"
		GameState.state["reputation"]["state" if faction == "police" else "mafia"] = 0
		for id: String in stock:
			_check(EffectApplier.install_module(id) == OK and Storage.count(id) == 0, "Owned faction modules fit their slot even after reputation decreases")
		_check(Loadout.speed(GameState.state["ship"]) > 210 and Loadout.speed(GameState.state["ship"]) < 225 and Loadout.shield_max(GameState.state["ship"]) >= 70, "Unique modules improve the ship while preserving the need for boost to escape pirates")
		EffectApplier.launch_flight()
		GameState.state["combat"] = CombatState.initial("pirate_light", "")
		_round_trip(faction + "-equipped-battle")


func _check_save() -> void:
	_new()
	var current: Dictionary = GameState.serialize()
	var old: Dictionary = current.duplicate(true)
	old.erase("module_storage")
	old.erase("module_deliveries")
	_check(GameState.restore(old) == OK and GameState.serialize() == current, "Old saves preserve their installed equipment and gain empty storage")
	for kind: String in ["module", "count", "past", "partial"]:
		var invalid: Dictionary = current.duplicate(true)
		match kind:
			"module": invalid["module_storage"] = {"missing": 1}
			"count": invalid["module_storage"] = {"cannon_s": -1}
			"past": invalid["module_deliveries"] = [{"module": "cannon_s", "count": 1, "arrival_day": 1}]
			"partial": invalid.erase("module_storage")
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == current, "Invalid storage or delivery " + kind + " is rejected atomically")
	for kind: String in ["reference", "days", "price", "reputation"]:
		var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
		for shop: Dictionary in groups["shops"]:
			if shop["id"] == "hub_module_parts":
				match kind:
					"reference": shop["modules"].append("missing")
					"days": shop["delivery_days"] = -1
					"reputation": shop["requires"] = [{"rep": "missing", "op": ">=", "value": 30}]
		if kind == "price":
			groups["modules"][0]["cost"] = -1
		_check(not Validator.validate(groups, DataLoader.record_sources).is_empty(), "Invalid store " + kind + " is reported")


func _check_pc() -> void:
	_new()
	EffectApplier.move_player("hub_tech")
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	await _click(hub.get_node("TechHotspot/Computer"))
	await _click(hub.get_node("%TerminalContent/ComputerMenu/Parts"))
	var market: Control = hub.get_node("%TerminalContent/ModuleMarket")
	_check(market.shop_id == "hub_module_parts" and hub.get_node("%Terminal").visible, "The real workshop PC opens the parts website")
	await _capture("website")
	var product: Control = market.find_child("Product_fuel_tank_mk2", true, false)
	market.find_child("ProductsScroll", true, false).ensure_control_visible(product)
	await _frames()
	await _click(product.find_child("Buy_fuel_tank_mk2", true, false))
	_check(Storage.pending("fuel_tank_mk2") == 1 and Storage.count("fuel_tank_mk2") == 0, "A real website click queues the delivery")
	await _capture("order")
	await _click(hub.get_node("%CloseTerminal"))
	Clock.advance_slots(4)
	await _frames()
	await _click(hub.get_node("ShipHotspot/Ship"))
	var refit: Control = hub.get_node("ShipRefit")
	var card: Control = refit._module_cards["fuel_tank_mk2"]
	refit._catalog_scroll.ensure_control_visible(card)
	await _frames()
	await _drag(card, refit._slots["fuel_tank"]["button"])
	_check(Loadout.installed(GameState.state["ship"], "fuel_tank")["id"] == "fuel_tank_mk2" and Storage.count("fuel_tank_mk2") == 0 and Storage.count("fuel_tank_mk1") == 1, "Dragging a delivered part installs it and returns the old module")
	await _capture("owned-refit")
	_round_trip("pc-refit")
	hub.queue_free()
	await _frames()


func _check_station_view() -> void:
	_station("station_police", "sys_earth")
	for npc: Dictionary in DataLoader.get_records("npcs"):
		GameState.state["flight"]["defeated_npcs"].append(str(npc["id"]))
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	var trade: Button = view._interactions.get_node("station_police/Trade")
	_check(trade.is_visible_in_tree() and not trade.disabled, "Nearby stations show their overhead trade action")
	await _capture("station-map")
	await _click(trade)
	var panel: Control = view.get_node("PlanetPanel")
	var buy: Button = panel.find_child("Buy_police_turret", true, false)
	_check(buy.disabled and panel.find_child("ModuleMarket", true, false) != null, "Station stock displays the reputation lock")
	await _capture("station-locked")
	GameState.state["reputation"]["state"] = 30
	panel.refresh()
	await _frames()
	await _click(panel.find_child("Buy_police_turret", true, false))
	_check(Storage.count("police_turret") == 1 and Storage.pending("police_turret") == 0, "A real station purchase grants the unique part immediately")
	await _capture("station-purchase")
	view.queue_free()
	await _frames()


func _round_trip(label: String) -> void:
	var saved: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://parts-" + label + ".json") == OK and GameState.load_game("user://parts-" + label + ".json") == OK and GameState.serialize() == saved, "The " + label + " state round-trips exactly")


func _click(button: Control) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _drag(source: Control, target: Control) -> void:
	var start: Vector2 = source.get_global_rect().get_center()
	var end: Vector2 = target.get_global_rect().get_center()
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = start
	get_viewport().push_input(press, true)
	var previous: Vector2 = start
	for step: int in range(1, 8):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = start.lerp(end, float(step) / 7.0)
		motion.relative = motion.position - previous
		get_viewport().push_input(motion, true)
		previous = motion.position
		await _frames()
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = end
	get_viewport().push_input(press, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture-parts" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var suffix: String = "-small" if "--small-parts" in OS.get_cmdline_user_args() else ""
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/parts-" + label + suffix + ".png") == OK, "The " + label + " screen renders")


func _check(value: bool, message: String) -> void:
	check_count += 1
	if not value:
		failures.append(message)
