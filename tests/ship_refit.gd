extends Node

const Loadout = preload("res://scripts/ship_loadout.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Math = preload("res://scripts/combat_math.gd")
const State = preload("res://scripts/combat_state.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const Validator = preload("res://scripts/data_validator.gd")
const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All refit content and references validate")
	_check_installation()
	_check_persistence()
	_check_validation()
	await _check_ui()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Ship refit checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _workshop() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_check(not Conditions.can_modify_ship() and EffectApplier.install_module("engine_mk2") == ERR_UNAVAILABLE, "Installation is unavailable outside the workshop")
	EffectApplier.move_player("hub_tech")


func _quiet_flight() -> void:
	EffectApplier.launch_flight()
	for entry: Dictionary in GameState.state["flight"]["npcs"].values():
		entry["cooldown"] = 10000.0


func _check_installation() -> void:
	_workshop()
	var ship: Dictionary = GameState.state["ship"]
	var initial: Dictionary = GameState.serialize()
	_check(Loadout.valid(ship) and ship["modules"].size() == 7, "A new ship has one module in each named slot")
	_check(EffectApplier.install_module("missing") == ERR_UNAVAILABLE and EffectApplier.install_module("engine_mk1") == ERR_UNAVAILABLE and GameState.serialize() == initial, "Unknown and already installed modules preserve state")
	_check(EffectApplier.install_module("engine_mk2", "turret") == ERR_UNAVAILABLE and GameState.serialize() == initial, "The effect rejects a module aimed at an incompatible slot")
	var engine: Dictionary = DataLoader.records["engine_mk2"]
	engine["requires"] = [{"flag": "refit_permission", "is": true}]
	_check(EffectApplier.install_module("engine_mk2") == ERR_UNAVAILABLE and GameState.serialize() == initial, "Module requirements are checked centrally and rejection is atomic")
	engine["requires"] = []
	for module_id: String in ["engine_mk2", "maneuver_mk2", "turret_mk2", "course_mk2", "broadside_mk4", "shield_mk2"]:
		_check(EffectApplier.install_module(module_id) == OK and Loadout.valid(ship), "Installing " + module_id + " preserves slot capacity")
	_check(ship["modules"].size() == 7 and GameState.state["money"] == initial["money"] and Clock.current_slot() == initial["time_slot"], "Free replacements spend no money or time and preserve seven occupied slots")
	_check(Loadout.speed(ship) == 210.0 and Math.movement_budget() == 8 and Math.movement_settings(true)["maneuver_level"] == 1 and Math.player_shield_max() == 20.0, "Installed engines and shield generator affect their actual gameplay stats")
	_check(Math.player_weapons().map(func(weapon: Dictionary) -> String: return str(weapon["id"])) == ["turret_mk2", "course_mk2", "broadside_mk4"], "Weapon replacements preserve mount order and become the combat loadout")
	ship["hull"]["current"] = 60.0
	_check(EffectApplier.install_module("armor_mk2") == OK and ship["hull"]["max"] == 125 and ship["hull"]["current"] == 85.0, "Armour preserves the existing forty points of damage")
	_check(EffectApplier.install_module("armor_mk1") == OK and ship["hull"]["max"] == 100 and ship["hull"]["current"] == 60.0, "Swapping armour back cannot repair the ship")
	EffectApplier.install_module("armor_mk2")
	ship["hull"]["current"] = 10.0
	var damaged: Dictionary = GameState.serialize()
	_check(EffectApplier.install_module("armor_mk1") == ERR_UNAVAILABLE and GameState.serialize() == damaged, "Removing necessary armour cannot destroy the ship in the workshop")
	_quiet_flight()
	_check(EffectApplier.install_module("engine_mk1") == ERR_UNAVAILABLE, "Flight blocks refitting")
	var start: Vector2 = Motion.point(GameState.state["flight"]["pos"])
	EffectApplier.set_flight_target(start + Vector2(500, 0))
	EffectApplier.advance_flight(0.1)
	_check(is_equal_approx(start.distance_to(Motion.point(GameState.state["flight"]["pos"])), 21.0), "The upgraded engine moves the ship at 210 units per second")
	GameState.state["combat"] = State.initial("pirate_light", "")
	_check(GameState.state["combat"]["move_points"] == 8 and GameState.state["combat"]["player"]["shield"] == 20.0, "A new combat uses the installed thrust and shield capacity")
	_check(EffectApplier.install_module("shield_mk1") == ERR_UNAVAILABLE, "Combat blocks refitting")


func _check_persistence() -> void:
	var combat: Dictionary = GameState.state["combat"]
	var target: Vector2i = Math.cell(combat["player"]["pos"]) + Math.DIRECTIONS[int(combat["player"]["facing"])] * 2
	_check(EffectApplier.move_combat(target) == OK, "The upgraded maneuver settings allow a real combat move")
	var saved: Dictionary = GameState.serialize()
	var write_error: Error = GameState.save_game("user://refitted-combat.json")
	var read_error: Error = GameState.load_game("user://refitted-combat.json")
	_check(write_error == OK and read_error == OK and GameState.serialize() == saved, "An upgraded combat loadout round-trips through JSON")
	combat = State.initial("pirate_light", "")
	GameState.state["combat"] = combat
	combat["player"]["shield"] = 4.0
	combat["opponent"]["pos"] = [0, 0]
	combat["movement"]["opponent"] = State.new_turn(combat["opponent"])
	_check(EffectApplier.use_combat_ability("shield_reboot") == OK, "The shield ability recognizes the upgraded capacity")
	EffectApplier.end_combat_turn()
	_check(combat["player"]["shield"] == 14.0, "Delayed recharge can restore above the previous ten-point shield limit")
	_workshop()
	var legacy: Dictionary = GameState.serialize()
	legacy["ship"]["slots"] = {"engine": 1, "weapon": 3, "utility": 2}
	for module_id: String in Loadout.LEGACY_DEFAULTS:
		legacy["ship"]["modules"].erase(module_id)
	legacy["ship"]["hull"]["current"] = 67.0
	_check(GameState.restore(legacy) == OK and Loadout.valid(GameState.state["ship"]), "A previous save gains seven named slots and baseline equipment")
	_check(GameState.state["ship"]["hull"]["current"] == 67.0 and Math.player_shield_max() == 10.0 and Math.movement_budget() == 6, "Migration preserves damage and baseline combat characteristics")
	_quiet_flight()
	GameState.state["combat"] = State.initial("pirate_light", "")
	legacy = GameState.serialize()
	legacy["ship"]["slots"] = {"engine": 1, "weapon": 3, "utility": 2}
	for module_id: String in Loadout.LEGACY_DEFAULTS:
		legacy["ship"]["modules"].erase(module_id)
	_check(GameState.restore(legacy) == OK and GameState.state["combat"]["player"]["shield"] == 10.0, "An old ongoing battle loads with its original shield capacity")
	var valid: Dictionary = GameState.serialize()
	var invalid: Dictionary = valid.duplicate(true)
	invalid["ship"]["modules"].append("engine_mk2")
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == valid, "Two engines cannot load into one slot")
	for bad_modules: Variant in [null, [42]]:
		invalid = valid.duplicate(true)
		invalid["ship"]["modules"] = bad_modules
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == valid, "Malformed equipment is rejected before migration can change active state")
	invalid = valid.duplicate(true)
	invalid["ship"]["movement"] = null
	_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == valid, "Malformed movement settings fail safely during combat migration")


func _check_validation() -> void:
	for field: String in ["speed", "maneuver_level", "hull_bonus", "shield"]:
		var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
		for module: Dictionary in groups["modules"]:
			if module.has(field):
				module[field] = -1
				break
		_check(not Validator.validate(groups, DataLoader.record_sources).is_empty(), "Startup validation rejects negative " + field)


func _check_ui() -> void:
	_workshop()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	var ship_button: Button = hub.get_node("ShipHotspot/Ship")
	_check(ship_button.is_visible_in_tree() and not ship_button.get_global_rect().intersects(hub.get_node("TechHotspot/Computer").get_global_rect()), "The ship and computer have separate clickable areas")
	await _capture("workshop")
	await _click(ship_button)
	_check(hub.has_node("ShipRefit"), "A real ship click opens modifications")
	if not hub.has_node("ShipRefit"):
		hub.queue_free()
		return
	var refit: Control = hub.get_node("ShipRefit")
	_check(refit._slots.size() == 7 and refit._bars.size() == 5 and refit._catalog.get_child_count() == 7, "The refit screen has seven slots, five bars and seven catalog categories")
	_check(refit._module_cards.size() == DataLoader.get_records("modules").size(), "Every available module appears in the same catalog")
	for module: Dictionary in DataLoader.get_records("modules"):
		var card: Control = refit._module_cards[module["id"]]
		_check(str(card.get_parent().get_parent().name) == Loadout.slot_for(module), "The module is grouped under its equipment category")
	_check(refit._module_cards["engine_mk2"].tooltip_text.contains("210"), "A module tooltip contains its description")
	await _capture("engine")
	var before: Dictionary = GameState.serialize()
	await _click(refit._module_cards["engine_mk2"])
	_check(GameState.serialize() == before, "Clicking a tile does not install its module")
	await _drag(refit._module_cards["engine_mk2"], refit._slots["turret"]["button"])
	_check(GameState.serialize() == before, "Dropping into an incompatible socket preserves the ship")
	await _drag(refit._module_cards["engine_mk2"], refit._summary)
	_check(GameState.serialize() == before, "Cancelling a drag outside the sockets preserves the ship")
	await _drag(refit._module_cards["engine_mk2"], refit._slots["engine"]["button"])
	_check(Loadout.speed(GameState.state["ship"]) == 210.0 and refit._module_cards["engine_mk2"].disabled and refit._bars["speed"]["bar"].value == 210.0, "A real drag replaces the engine and updates the tile and speed bar")
	await _wheel(refit._catalog_scroll, MOUSE_BUTTON_WHEEL_DOWN)
	_check(refit._catalog_scroll.scroll_vertical > 0, "The catalog scrolls down with the mouse wheel")
	var wheel_position: int = refit._catalog_scroll.scroll_vertical
	await _wheel(refit._catalog_scroll, MOUSE_BUTTON_WHEEL_UP)
	_check(refit._catalog_scroll.scroll_vertical < wheel_position, "The catalog scrolls back up with the mouse wheel")
	GameState.state["ship"]["modules"].erase("shield_mk1")
	refit.refresh()
	await _frames()
	_check(not refit._slots["shield"]["icon"].visible, "An empty socket shows its frame without an installed icon")
	refit._catalog_scroll.ensure_control_visible(refit._module_cards["shield_mk2"])
	await _frames()
	var scroll_position: int = refit._catalog_scroll.scroll_vertical
	await _drag(refit._module_cards["shield_mk2"], refit._slots["shield"]["button"])
	_check(Math.player_shield_max() == 20.0 and refit._slots["shield"]["icon"].visible, "A dragged generator fills an empty socket")
	_check(refit._catalog_scroll.scroll_vertical == scroll_position, "Installing keeps the catalog at its current scroll position")
	refit._catalog_scroll.ensure_control_visible(refit._module_cards["broadside_mk4"])
	await _frames()
	await _drag(refit._module_cards["broadside_mk4"], refit._slots["broadside"]["button"])
	_check(Loadout.installed(GameState.state["ship"], "broadside")["id"] == "broadside_mk4", "A dragged module replaces the shared weapons of both broadsides")
	await _click(refit._slots["course"]["button"])
	_check(refit._module_cards.size() == DataLoader.get_records("modules").size() and refit._catalog.get_child_count() == 7, "Selecting another socket keeps all catalog categories available")
	await _capture("broadside")
	await _click(refit.find_child("Close", true, false))
	_check(not hub.has_node("ShipRefit") and GameState.state["location"] == "hub_tech", "Closing modifications returns to the workshop")
	_quiet_flight()
	hub.queue_free()
	await _frames()
	var flight: Control = FlightScene.instantiate()
	add_child(flight)
	flight.set_physics_process(false)
	await _frames()
	await _capture("flight")
	flight.queue_free()
	await _frames()
	GameState.state["combat"] = State.initial("pirate_light", "")
	var combat: Control = CombatScene.instantiate()
	add_child(combat)
	await _frames()
	_check(combat.find_child("Tiles", true, false).get_child_count() > 0, "Combat renders its tactical grid")
	await _capture("combat")
	combat.queue_free()
	await _frames()


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _drag(source: Control, destination: Control) -> void:
	var from: Vector2 = source.get_global_rect().get_center()
	var to: Vector2 = destination.get_global_rect().get_center()
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = from + Vector2(24, 0)
	move.relative = Vector2(24, 0)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	move = InputEventMouseMotion.new()
	move.position = to
	move.relative = to - from - Vector2(24, 0)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	get_viewport().push_input(up, true)
	await _frames()


func _wheel(control: Control, button_index: int) -> void:
	for _notch: int in range(4):
		for pressed: bool in [true, false]:
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.button_index = button_index
			event.pressed = pressed
			event.position = control.get_global_rect().get_center()
			get_viewport().push_input(event, true)
		await _frames()


func _capture(suffix: String) -> void:
	if "--capture-ship-refit" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/ship-refit-" + suffix + ".png") == OK, "The " + suffix + " view renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
