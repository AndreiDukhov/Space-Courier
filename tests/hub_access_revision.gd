extends Node

const HubScene = preload("res://scenes/hub.tscn")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Text = preload("res://scripts/ui_text.gd")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Hub data and refined silhouette validate")
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_check_shop_connections()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	await _shop_visits(hub)
	await _kitchen(hub)
	await _ship(hub)
	await _computers(hub)
	hub.queue_free()
	await _frames()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Hub access revision checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_shop_connections() -> void:
	for _slot: int in range(4):
		var open: bool = Clock.current_slot() in ["day", "evening"]
		for room: Dictionary in DataLoader.get_records("locations"):
			if room.get("area") != "hub" or room["id"] == "hub_shop":
				continue
			GameState.state["location"] = room["id"]
			_check(Conditions.can_enter("hub_shop") == open, "Shop entry follows its hours from " + str(room["id"]) + " during " + Clock.current_slot())
			GameState.state["location"] = "hub_shop"
			_check(Conditions.can_enter(str(room["id"])) == Conditions.location_is_open(str(room["id"])), "The shop has a usable return connection to " + str(room["id"]))
		Clock.advance_slots()
	GameState.state["location"] = "hub_kitchen"
	Clock.advance_slots(2)


func _shop_visits(hub: Control) -> void:
	for source: String in ["hub_tech", "hub_office", "hub_showers"]:
		_check(EffectApplier.move_player(source) == OK, "Reach the source room: " + source)
		await _settled()
		var entrance: Button = hub.get_node("%Locations/hub_shop/Travel")
		_check(not entrance.disabled and not entrance.has_node("ClosedShade"), "The open shop card is enabled in " + source)
		await _click(entrance)
		_check(GameState.state["location"] == "hub_shop", "A real card click enters the shop from " + source)
		var open: Button = hub.find_child("DomesticActions", true, false).get_node_or_null("shop")
		_check(open != null, "The shop exposes its trade entry")
		if open == null:
			return
		await _click(open)
		_check(hub._domestic != null and hub._domestic.tab == "shop", "The trade window opens")
		if hub._domestic == null:
			return
		var close: Button = hub._domestic.find_child("Close", true, false)
		_check(hub.get_global_rect().encloses(close.get_global_rect()), "The shop exit remains visible inside the game window")
		if source == "hub_tech":
			var before: int = Inventory.count("carrot", GameState.state["inventory"])
			await _click(hub._domestic.find_child("carrot", true, false).find_child("Buy", true, false))
			_check(Inventory.count("carrot", GameState.state["inventory"]) == before + 1, "A trade click actually buys food")
			await _capture("shop")
		await _click(close)
		_check(hub._domestic == null, "The exit button closes the trade window")
		await _click(hub.get_node("%Locations/" + source + "/Travel"))
		_check(GameState.state["location"] == source, "A real card click returns from the shop to " + source)
	EffectApplier.move_player("hub_shop")
	hub.open_domestic("shop")
	Clock.advance_slots()
	await _frames()
	_check(not Conditions.can_use_shop(), "Trade becomes unavailable at closing time")
	await _click(hub._domestic.find_child("Close", true, false))
	_check(hub._domestic == null, "Closing hours never trap the player in the trade window")
	await _click(hub.get_node("%Locations/hub_tech/Travel"))
	_check(GameState.state["location"] == "hub_tech", "The player can still leave the closed shop for the workshop")


func _kitchen(hub: Control) -> void:
	EffectApplier.move_player("hub_kitchen")
	hub.open_domestic("kitchen")
	await _frames()
	for name: String in ["Save", "Load"]:
		_check(not hub._domestic.find_child(name, true, false).is_visible_in_tree(), "Kitchen hides " + name)
	var close: Button = hub._domestic.find_child("Close", true, false)
	_check(close.text == Text.get_text("ui_kitchen_leave") and close.size.y <= 36, "The kitchen has a compact, clearly named exit")
	_check(hub.get_global_rect().encloses(close.get_global_rect()), "The kitchen exit stays on screen")
	await _capture("kitchen")
	EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "cut")
	await _frames()
	var snapshot: Dictionary = GameState.serialize()
	await _click(close)
	_check(hub._domestic._exit_dialog.visible and GameState.serialize() == snapshot, "The compact exit still asks before losing a used ingredient")
	await _click(hub._domestic._exit_dialog.get_cancel_button())
	_check(GameState.serialize() == snapshot, "Cancelling preserves the unfinished cooking")
	await _click(close)
	await _click(hub._domestic._exit_dialog.get_ok_button())
	_check(hub._domestic == null and GameState.state["kitchen"].is_empty(), "Confirming leaves the kitchen through the same exit")


func _ship(hub: Control) -> void:
	Clock.advance_slots(2)
	EffectApplier.move_player("hub_tech")
	await _settled()
	var ship: Button = hub.get_node("ShipHotspot/Ship")
	for sample: Vector2 in [Vector2(0.74, 0.15), Vector2(0.55, 0.58), Vector2(0.93, 0.60)]:
		_check(ship._has_point(_background_point(hub, sample) - ship.global_position), "The hull and landing supports are selectable")
	for sample: Vector2 in [Vector2(0.38, 0.63), Vector2(0.70, 0.48), Vector2(0.85, 0.63)]:
		var point: Vector2 = _background_point(hub, sample)
		_check(not ship._has_point(point - ship.global_position), "Empty workshop space is outside the silhouette")
		await _point_click(point)
		_check(hub._refit == null, "Empty space does not open modifications")
	var hull: Vector2 = _background_point(hub, Vector2(0.74, 0.15))
	await _move(hull)
	_check(ship.is_hovered() and hub.get_node("ShipHotspot/Hint").visible, "The real hull hover shows the contour and refit hint")
	await _capture("ship")
	await _point_click(hull)
	_check(hub._refit != null, "The refined silhouette opens modifications")
	if hub._refit != null:
		await _click(hub._refit.find_child("Close", true, false))


func _computers(hub: Control) -> void:
	for room: String in ["hub_office", "hub_tech"]:
		EffectApplier.move_player(room)
		await _settled()
		var opened: bool = hub.open_order_terminal() if room == "hub_office" else hub.open_flight_terminal()
		_check(opened, "The PC opens in " + room)
		await _frames()
		var button: Button = hub.get_node("%CloseTerminal")
		var artwork: TextureRect = hub.get_node("Terminal/Artwork")
		var scale: float = artwork.size.y / 800.0
		var screen_edge: float = artwork.global_position.y + 658 * scale
		_check(button.global_position.y > screen_edge + 2 * scale, "The entire power button has a gap below the screen bezel")
		_check(button.get_global_rect().end.y < artwork.global_position.y + 699 * scale, "Power hover and click area stay within the lower frame")
		_check(button.get_theme_constant("icon_max_width") <= roundi(21 * scale), "The power glyph fits the smaller physical button")
		await _move(button.get_global_rect().get_center())
		await _capture(room + "-pc")
		await _click(button)
		_check(not hub.get_node("%Terminal").visible, "The inset power button closes the PC")


func _background_point(hub: Control, normalized: Vector2) -> Vector2:
	var image: Vector2 = hub.get_node("%Background").texture.get_size()
	var rendered: Vector2 = image * maxf(hub.size.x / image.x, hub.size.y / image.y)
	return hub.global_position + (hub.size - rendered) * 0.5 + normalized * rendered


func _click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	if button.get_window() != get_window():
		point += Vector2(button.get_window().position)
	await _point_click(point)


func _point_click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames()


func _move(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await _frames()


func _frames() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _settled() -> void:
	await get_tree().create_timer(0.34).timeout
	await _frames()


func _capture(suffix: String) -> void:
	if "--capture-hub-access" in OS.get_cmdline_user_args():
		if "--small" in OS.get_cmdline_user_args():
			suffix += "-small"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/hub-access-" + suffix + ".png")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
