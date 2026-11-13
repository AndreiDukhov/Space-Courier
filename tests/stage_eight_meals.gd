extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Meals = preload("res://scripts/meal_schedule.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Service = preload("res://scripts/hub_service.gd")
const Appearance = preload("res://scripts/cooking_appearance.gd")
const Token = preload("res://scripts/cooking_token.gd")
const HubScene = preload("res://scenes/hub.tscn")
const DomesticScene = preload("res://scenes/domestic.tscn")
const SAVE: String = "res://.godot/meal-test-save.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All meal revision content loads")
	_check_invitation()
	_check_night()
	_check_multiple()
	_check_shopkeeper()
	_check_persistence()
	await _check_appearance()
	await _check_conversations()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Meal revision checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game(count: int = 2) -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	EffectApplier.apply_effects([{"item": "dish_carrot_01", "add": count}])


func _count() -> int:
	return Inventory.count("dish_carrot_01", GameState.state["inventory"])


func _check_invitation() -> void:
	_new_game()
	_check(Meals.arrival(1, "morning") == {"day": 1, "time_slot": "day"} and Meals.arrival(1, "day") == {"day": 1, "time_slot": "evening"}, "Daytime invitations use the next turn")
	_check(Meals.arrival(1, "evening") == {"day": 2, "time_slot": "morning"} and Meals.arrival(1, "night") == {"day": 2, "time_slot": "morning"}, "Evening and nighttime invitations arrive in the morning")
	Clock.advance_slots()
	_check(Service.travel("hub_tech") == OK and Conditions.is_present("medic"), "The medic can be approached away from the kitchen")
	var mood: float = float(GameState.state["heroines"]["medic"]["mood"])
	_check(EffectApplier.invite_to_meal(0, "medic") == OK, "A meal can be offered away from the kitchen")
	_check(_count() == 1 and Clock.current_slot() == "day" and GameState.state["heroines"]["medic"]["mood"] == mood, "Invitation reserves one dish without spending time or applying food effects early")
	_check(GameState.state["meal_invites"]["medic"] == {"item": "dish_carrot_01", "quality": 1, "day": 1, "time_slot": "evening"}, "Only the approved reservation fields are stored")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.invite_to_meal(0, "medic") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "An invitation cannot reserve a second dish for the same heroine")
	_check(EffectApplier.invite_to_meal(0, "pilot") == ERR_UNAVAILABLE and EffectApplier.invite_to_meal(0, "missing") == ERR_UNAVAILABLE, "Remote or unknown heroines cannot be invited")
	_check(GameState.save_game(SAVE) == OK and GameState.load_game(SAVE) == OK and GameState.serialize() == snapshot, "The pending invitation round-trips through JSON")
	Service.travel("hub_office")
	Clock.advance_slots()
	_check(GameState.state["heroines"]["medic"]["loc"] == "hub_kitchen" and GameState.state["location"] == "hub_office", "The next turn overrides the schedule without moving the player")
	_check(GameState.state["served_days"].get("medic") == 1 and GameState.state["heroines"]["medic"]["mood"] == mood + 6 and _count() == 1, "Arrival consumes the reserved meal and applies food effects exactly once")
	snapshot = GameState.serialize()
	_check(GameState.save_game(SAVE) == OK and GameState.load_game(SAVE) == OK, "A heroine eating her meal can be saved and loaded")
	ScheduleManager.assign_locations()
	_check(GameState.state["heroines"]["medic"]["mood"] == snapshot["heroines"]["medic"]["mood"] and _count() == 1, "Reassigning an arrival slot does not eat another meal or repeat its bonus")
	Clock.advance_slots()
	_check(GameState.state["meal_invites"].is_empty() and GameState.state["heroines"]["medic"]["loc"] == "hub_corridor", "After eating, the heroine resumes her ordinary schedule")


func _check_night() -> void:
	_new_game()
	_check(EffectApplier.use_food(0, "medic") == OK, "The medic receives a morning meal")
	Clock.advance_slots(2)
	Service.travel("hub_showers")
	_check(EffectApplier.invite_to_meal(0, "medic") == OK, "A heroine who ate today can accept a dinner reserved for tomorrow")
	var mood: float = float(GameState.state["heroines"]["medic"]["mood"])
	Clock.advance_slots()
	_check(Clock.current_slot() == "night" and GameState.state["heroines"]["medic"]["loc"] == "hub_corridor" and GameState.state["heroines"]["medic"]["mood"] == mood, "A nighttime next turn neither moves the heroine to dinner nor grants a bonus")
	_check(GameState.save_game(SAVE) == OK and GameState.load_game(SAVE) == OK, "The night before a morning dinner can be saved")
	Clock.advance_slots()
	_check(Clock.current_day() == 2 and GameState.state["heroines"]["medic"]["loc"] == "hub_kitchen" and GameState.state["served_days"].get("medic") == 2, "The postponed dinner happens the following morning")
	_check(GameState.state["heroines"]["medic"]["mood"] == mood + 6, "The morning meal applies its effect once")
	Clock.advance_slots()
	_check(GameState.state["heroines"]["medic"]["loc"] == "hub_tech" and GameState.state["meal_invites"].is_empty(), "Morning dinner ends before the normal daytime workshop visit")


func _check_multiple() -> void:
	_new_game(3)
	GameState.state["heroines"]["pilot"]["aboard"] = false
	GameState.state["heroines"]["medic"]["polygamy"] = "forbids"
	Clock.advance_slots()
	Service.travel("hub_tech")
	_check(Conditions.is_present("pilot") and Conditions.is_present("medic"), "Two heroines can be approached in the same room")
	_check(EffectApplier.invite_to_meal(0, "medic") == OK and EffectApplier.invite_to_meal(0, "pilot") == OK and _count() == 1, "Separate dishes can be reserved for multiple heroines")
	Clock.advance_slots()
	_check(GameState.state["heroines"]["medic"]["loc"] == "hub_kitchen" and GameState.state["heroines"]["pilot"]["loc"] == "hub_kitchen", "Each invited heroine arrives on the agreed turn")
	_check(GameState.state["served_days"].get("pilot") == 1 and GameState.state["served_days"].get("medic") == 1, "Daily serving limits are tracked separately")
	_check(GameState.state["heroines"]["medic"]["suspicion"] == 5, "An automatic meal uses the witnesses actually present in the kitchen")
	_check(not Conditions.can_invite_to_meal(0, "medic"), "A pending or eating heroine cannot accept another reservation")


func _check_shopkeeper() -> void:
	_new_game()
	Clock.advance_slots(2)
	Service.travel("hub_shop")
	_check(EffectApplier.invite_to_meal(0, "shopkeeper") == OK, "The shopkeeper can accept dinner during opening hours")
	Clock.advance_slots(2)
	_check(Clock.current_slot() == "morning" and GameState.state["heroines"]["shopkeeper"]["loc"] == "hub_kitchen" and Conditions.heroine_visible("shopkeeper"), "An invited shopkeeper remains visible in the kitchen despite closed shop hours")
	Clock.advance_slots()
	_check(GameState.state["heroines"]["shopkeeper"]["loc"] == "hub_shop" and not GameState.state["heroines"]["shopkeeper"]["aboard"], "The shopkeeper returns to her shop and stays out of the crew")


func _check_persistence() -> void:
	_new_game()
	var previous: Dictionary = GameState.serialize()
	previous.erase("meal_invites")
	previous.erase("pending_scenes")
	var original: Dictionary = previous.duplicate(true)
	_check(GameState.restore(previous) == OK and GameState.state["meal_invites"].is_empty() and previous == original, "Previous stage-eight saves gain empty invitations without changing the input snapshot")
	var legacy_file: FileAccess = FileAccess.open(SAVE, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(previous))
	legacy_file.close()
	_check(GameState.load_game(SAVE) == OK and GameState.state["meal_invites"].is_empty(), "An actual previous-format save file loads with empty invitations")
	Clock.advance_slots()
	Service.travel("hub_tech")
	GameState.state["inventory"][0]["quality"] = 3
	EffectApplier.invite_to_meal(0, "medic")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE) == OK and GameState.load_game(SAVE) == OK and GameState.serialize() == snapshot, "A reserved quality-three dish survives serialization")
	for field: String in ["item", "quality", "day", "time_slot"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["meal_invites"]["medic"].erase(field)
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Incomplete meal reservation rejects missing " + field)
	for invalid_entry: Dictionary in [
		{"item": "missing", "quality": 1, "day": 1, "time_slot": "evening"},
		{"item": "carrot", "quality": 1, "day": 1, "time_slot": "evening"},
		{"item": "dish_carrot_01", "quality": 4, "day": 1, "time_slot": "evening"},
		{"item": "dish_carrot_01", "quality": 1, "day": 1, "time_slot": "night"},
		{"item": "dish_carrot_01", "quality": 1, "day": 1, "time_slot": "morning"},
		{"item": "dish_carrot_01", "quality": 1, "day": 3, "time_slot": "morning"}
	]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["meal_invites"]["medic"] = invalid_entry
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid reservation data is rejected atomically")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["meal_invites"]["missing"] = invalid["meal_invites"]["medic"].duplicate(true)
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unknown invited heroine ids cannot load")
	var mood: float = float(GameState.state["heroines"]["medic"]["mood"])
	Clock.advance_slots()
	_check(GameState.state["heroines"]["medic"]["mood"] == mood + 9, "The reserved dish retains its quality multiplier at arrival")
	_check(GameState.save_game(SAVE) == OK and GameState.load_game(SAVE) == OK, "The fulfilled quality-three invitation remains valid")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK, "The meal verification save is removed")


func _check_appearance() -> void:
	_new_game(1)
	EffectApplier.apply_effects([{"item": "carrot", "add": 1}])
	var view: Control = DomesticScene.instantiate()
	view.tab = "kitchen"
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var steps: Array[String] = []
	for zone: String in ["cut", "boil", "fry", "plate"]:
		_check(EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", zone, -1 if zone == "cut" else 0) == OK, "A drop moves the ingredient to " + zone)
		if zone != "plate":
			EffectApplier.process_kitchen_zone(zone)
			steps.append(zone)
		await get_tree().process_frame
		await get_tree().process_frame
		var prepared: Token = view.find_child("Prepared", true, false)
		_check(prepared != null and prepared.steps == steps and prepared.plated == (zone == "plate"), "The visible token immediately reflects the complete processing state")
		_check(prepared.tooltip_text == Appearance.ingredient_name("carrot", steps, zone == "plate") and not prepared.tooltip_text.is_empty(), "Tooltip and visible name reflect processing")
		_check(view.find_child("PreparedName", true, false).text == prepared.tooltip_text, "The changed ingredient name is visible without hovering")
		_check(view.find_child("carrot", true, false) == null, "The ingredient on the counter is not duplicated in stock")
		await _capture("ingredient-" + zone)
	view.queue_free()
	await get_tree().process_frame
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(84, 84)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var token: Token = Token.new()
	token.size = Vector2(84, 84)
	viewport.add_child(token)
	var previous_image: PackedByteArray = []
	for state: Array in [[], ["cut"], ["cut", "boil"], ["cut", "boil", "fry"]]:
		token.steps.assign(state)
		token.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels: PackedByteArray = viewport.get_texture().get_image().get_data()
		_check(not pixels.is_empty() and pixels != previous_image, "The actual ingredient drawing changes after each processing step")
		previous_image = pixels
	viewport.queue_free()
	await get_tree().process_frame
	EffectApplier.cancel_cooking()


func _check_conversations() -> void:
	_new_game()
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await get_tree().process_frame
	_check(hub.open_dialogue("medic"), "A heroine without authored scenes can still be approached")
	await get_tree().process_frame
	var dialogue: Control = hub.get_node("%DialogueContent").get_child(0)
	_check("TODO scene text" in dialogue.get_node("%Lines").get_child(0).text, "New conversation narrative remains a placeholder")
	dialogue.find_child("MealMenu", true, false).pressed.emit()
	await get_tree().process_frame
	await _capture("offer")
	dialogue.find_child("Offer_0", true, false).pressed.emit()
	await get_tree().process_frame
	_check(_count() == 1 and GameState.state["served_days"].get("medic") == 1, "A kitchen conversation serves the selected dish immediately")
	hub.get_node("%CloseDialogue").pressed.emit()
	Clock.advance_slots()
	Service.travel("hub_tech")
	_check(hub.open_dialogue("medic"), "The same heroine can be approached away from the kitchen")
	dialogue = hub.get_node("%DialogueContent").get_child(0)
	await get_tree().process_frame
	_check(dialogue.find_child("MealMenu", true, false).disabled, "The conversation respects an already served heroine's daily limit")
	hub.get_node("%CloseDialogue").pressed.emit()
	_new_game()
	Clock.advance_slots()
	Service.travel("hub_tech")
	_check(hub.open_dialogue("medic"), "A fresh daytime conversation can offer a future dinner")
	dialogue = hub.get_node("%DialogueContent").get_child(0)
	await get_tree().process_frame
	dialogue.find_child("MealMenu", true, false).pressed.emit()
	await get_tree().process_frame
	await _capture("invite")
	dialogue.find_child("Offer_0", true, false).pressed.emit()
	await get_tree().process_frame
	_check(GameState.state["meal_invites"].has("medic") and _count() == 1 and Clock.current_slot() == "day", "The conversation reserves the dish without advancing time")
	hub.get_node("%CloseDialogue").pressed.emit()
	hub.get_node("%Wait").pressed.emit()
	_check(hub.get_node("%Locations/hub_kitchen/Occupants").has_node("medic"), "The next-turn kitchen card shows the invited heroine")
	Service.travel("hub_kitchen")
	hub.open_dialogue("medic")
	await get_tree().process_frame
	await _capture("eating")
	hub.queue_free()
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-meals" not in OS.get_cmdline_user_args():
		return
	if "--small-meals" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/meal-" + suffix + ".png") == OK, "The " + suffix + " screenshot renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
