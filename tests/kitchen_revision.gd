extends Node

const HubScene = preload("res://scenes/hub.tscn")
const Kitchen = preload("res://scripts/kitchen.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Validator = preload("res://scripts/domestic_validator.gd")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Kitchen and polygon data validate")
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.apply_effects([{"item": "carrot", "add": 4}, {"item": "noodles", "add": 2}])
	for item: String in ["dish_carrot_01", "dish_carrot_noodles"]:
		for quality: int in [1, 2, 3]:
			Inventory.change(GameState.state["inventory"], item, 1, quality)
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	await _check_hotspots(hub)
	await _check_cooking(hub)
	await _check_ship(hub)
	hub.queue_free()
	await _frames()
	_check_polygons()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Kitchen revision checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _point(hub: Control, normalized: Vector2) -> Vector2:
	var dimensions: Vector2 = hub.get_node("%Background").texture.get_size()
	var rendered: Vector2 = dimensions * maxf(hub.size.x / dimensions.x, hub.size.y / dimensions.y)
	return hub.global_position + (hub.size - rendered) * 0.5 + normalized * rendered


func _check_hotspots(hub: Control) -> void:
	var button: Button = hub.get_node("KitchenHotspot/Cook")
	_check(not button._has_point(_point(hub, Vector2(0.035, 0.42)) - button.global_position), "The refrigerator is outside the cooking hotspot")
	_check(not button._has_point(_point(hub, Vector2(0.2, 0.55)) - button.global_position), "The raised lower boundary excludes the lower furniture")
	_check(button._has_point(_point(hub, Vector2(0.20, 0.43)) - button.global_position), "The countertop remains clickable")
	await _click_point(get_viewport(), _point(hub, Vector2(0.035, 0.42)))
	_check(hub._domestic == null, "Clicking the refrigerator does not open cooking")
	await _move(_point(hub, Vector2(0.20, 0.43)))
	await _capture("kitchen-hotspot")
	await _click(button)
	_check(hub._domestic != null and hub._domestic.tab == "kitchen", "The tightened hotspot opens the actual kitchen")


func _kitchen(hub: Control) -> Kitchen:
	return hub._domestic._content.get_child(0) as Kitchen


func _check_cooking(hub: Control) -> void:
	var kitchen: Kitchen = _kitchen(hub)
	var stock: Control = kitchen.find_child("KitchenStock", true, false)
	_check(stock.global_position.x > kitchen.global_position.x + kitchen.size.x * 0.65 and kitchen._counter.size.x > kitchen.size.x * 0.65, "The large workbench occupies the left three quarters")
	var ingredients: ScrollContainer = stock.find_child("IngredientsScroll", true, false)
	var dishes: ScrollContainer = stock.find_child("DishesScroll", true, false)
	_check(ingredients != null and dishes != null and ingredients.global_position.y < dishes.global_position.y, "Ingredients and ready meals have separate stacked scroll lists")
	_check(dishes.get_child(0).get_child_count() == 6, "All ready dishes and their distinct quality stacks are listed")
	await _wheel(dishes)
	_check(dishes.scroll_vertical > 0, "The dish list scrolls independently")
	_check(ingredients.scroll_vertical == 0, "Scrolling dishes does not move ingredients")
	await _capture("kitchen-stock")
	await _drag(kitchen.find_child("carrot", true, false), kitchen._zones["cut"])
	_check(GameState.state["kitchen"]["entries"].size() == 1 and Inventory.count("carrot", GameState.state["inventory"]) == 4, "Dragging reserves a single portion before completion")
	kitchen = _kitchen(hub)
	await _click(kitchen._zones["cut"].get_node("Process"))
	kitchen = _kitchen(hub)
	await _drag(kitchen.find_child("Prepared", true, false), kitchen._zones["plate"])
	kitchen = _kitchen(hub)
	var finish: Button = kitchen._zones["plate"].get_node("Finish")
	_check(finish.is_visible_in_tree() and not finish.disabled and finish.global_position.y < kitchen._zones["plate"].global_position.y, "Plating reveals the clickable finish label above the plate")
	_check(kitchen._counter.get_global_rect().encloses(finish.get_global_rect()), "The finish button remains within the workbench")
	await _capture("plated")
	await _click(finish)
	_check(GameState.state["kitchen"].is_empty() and Inventory.count("carrot", GameState.state["inventory"]) == 3 and Inventory.count("dish_carrot_01", GameState.state["inventory"]) == 4, "Finishing consumes one ingredient and adds exactly one ready dish")
	var ready_count: int = Inventory.count("dish_carrot_01", GameState.state["inventory"])
	EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "boil")
	await _frames()
	var pending: Dictionary = GameState.serialize()
	await _key(KEY_ESCAPE)
	var dialog: ConfirmationDialog = hub._domestic._exit_dialog
	_check(dialog.visible and hub._domestic != null and GameState.serialize() == pending, "Escape shows the loss warning before leaving")
	await _capture("abort-warning")
	await _click(dialog.get_cancel_button())
	_check(not dialog.visible and GameState.serialize() == pending, "Continuing keeps all pending ingredients and processing unchanged")
	await _click(hub._domestic.find_child("Close", true, false))
	_check(dialog.visible, "The close button uses the same confirmation")
	await _key(KEY_ESCAPE)
	_check(not dialog.visible and not PauseMenu.is_open() and GameState.serialize() == pending, "Escape cancels the warning without leaving or opening another menu")
	await _click(hub._domestic.find_child("Close", true, false))
	await _click(dialog.get_ok_button())
	_check(hub._domestic == null and GameState.state["kitchen"].is_empty(), "Confirming leaves the kitchen and clears unfinished cooking")
	_check(Inventory.count("carrot", GameState.state["inventory"]) == 2 and Inventory.count("noodles", GameState.state["inventory"]) == 2 and Inventory.count("dish_carrot_01", GameState.state["inventory"]) == ready_count, "Only used portions are lost; unused ingredients and ready meals remain")
	_check(GameState.state["cooking_skill"] == 1 and GameState.state["time_slot"] == pending["time_slot"] and GameState.state["day"] == pending["day"], "Aborting spends no extra time and adds no skill or dish")
	_check(not PauseMenu.is_open(), "Closing the warning and kitchen does not also open the pause menu")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://kitchen-revision.json") == OK and GameState.load_game("user://kitchen-revision.json") == OK and GameState.serialize() == snapshot, "Ingredient loss and ready dishes round-trip in the existing save format")
	hub.open_domestic("kitchen")
	EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "boil")
	EffectApplier.prepare_ingredient("recipe_carrot_noodles", "noodles", "boil")
	EffectApplier.process_kitchen_zone("boil")
	EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "fry", 0)
	EffectApplier.process_kitchen_zone("fry")
	await _frames()
	_check(_kitchen(hub).find_child("Cancel", true, false) == null, "No redundant clear-counter button covers the kitchen picture")
	await _click(hub._domestic.find_child("Close", true, false))
	_check(hub._domestic._exit_dialog.visible, "Leaving a processed mixture requests confirmation")
	await _click(hub._domestic._exit_dialog.get_ok_button())
	_check(hub._domestic == null and GameState.state["kitchen"].is_empty() and Inventory.count("carrot", GameState.state["inventory"]) == 1 and Inventory.count("noodles", GameState.state["inventory"]) == 1, "Leaving discards each processed portion once")
	snapshot = GameState.serialize()
	EffectApplier.cancel_cooking()
	_check(GameState.serialize() == snapshot, "Repeated clearing cannot remove another portion")


func _check_ship(hub: Control) -> void:
	EffectApplier.move_player("hub_tech")
	await _frames()
	var ship: Button = hub.get_node("ShipHotspot/Ship")
	var outside: Vector2 = _point(hub, Vector2(0.38, 0.63))
	_check(ship.get_global_rect().has_point(outside) and not ship._has_point(outside - ship.global_position), "The silhouette rejects empty space inside its bounding rectangle")
	await _click_point(get_viewport(), outside)
	_check(not hub.has_node("ShipRefit"), "Clicking outside the hull does not open refitting")
	var hull: Vector2 = _point(hub, Vector2(0.74, 0.15))
	_check(ship._has_point(hull - ship.global_position) and ship.polygon.size() > 20, "The authored contour includes the visible hull")
	await _move(hull)
	await _capture("ship-hover")
	await _click_point(get_viewport(), hull)
	_check(hub.has_node("ShipRefit"), "Clicking the highlighted hull opens the real refit screen")
	await _key(KEY_ESCAPE)
	await _click(hub.get_node("TechHotspot/Computer"))
	await _capture("console")
	var monitor: Control = hub.get_node("Terminal")
	_check(monitor.has_node("ScreenGlass") and hub.get_node("%TerminalContent").theme != null, "Both PC screens share glass, material and control styling")
	await _click(hub.get_node("%TerminalContent/ComputerMenu/Parts"))
	await _capture("parts")
	await _click(hub.get_node("%CloseTerminal"))
	EffectApplier.move_player("hub_office")
	await _frames()
	await _click(hub.get_node("OfficeHotspot/Computer"))
	await _capture("orders")


func _check_polygons() -> void:
	var record: Dictionary = DataLoader.get_record("hub_ship_hotspot")
	for polygon: Variant in [[], [[0.1, 0.1], [0.2, 0.2]], [[0.4, 0.1], [2.0, 0.2], [0.5, 0.3]], [[0.4, 0.1], [0.4, 0.1], [0.5, 0.3]], [[0.4, 0.1], [0.5, INF], [0.6, 0.3]]]:
		record["zones"]["ship"]["drop_polygon"] = polygon
		_check(not Validator.validate_hub_hotspot(record).is_empty(), "Malformed or out-of-bounds hotspot polygons are rejected")


func _key(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames()


func _click(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	if button.get_window() != get_window():
		point += Vector2(button.get_window().position)
	await _click_point(get_viewport(), point)


func _click_point(viewport: Viewport, point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		viewport.push_input(event, true)
	await _frames()


func _move(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	get_viewport().push_input(event, true)
	await _frames()


func _drag(source: Control, target: Control) -> void:
	var from: Vector2 = source.get_global_rect().get_center()
	var to: Vector2 = target.get_global_rect().get_center()
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	get_viewport().push_input(down, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = from + Vector2(14, 0)
	motion.relative = Vector2(14, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await _frames()
	motion = InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await _frames()
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	get_viewport().push_input(up, true)
	await _frames()


func _wheel(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-kitchen-revision" in OS.get_cmdline_user_args():
		if "--small" in OS.get_cmdline_user_args():
			suffix += "-small"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/kitchen-revision-" + suffix + ".png")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
