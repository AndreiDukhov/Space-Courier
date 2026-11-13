extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Cooking = preload("res://scripts/cooking_math.gd")
const Validator = preload("res://scripts/data_validator.gd")
const Service = preload("res://scripts/hub_service.gd")
const HubScene = preload("res://scenes/hub.tscn")
const DomesticScene = preload("res://scenes/domestic.tscn")
const SAVE: String = "res://.godot/stage-eight-save.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All stage-eight content loads without errors")
	_check_shop()
	_check_cooking()
	_check_mixing()
	_check_serving()
	_check_books_and_orders()
	_check_persistence()
	_check_content()
	await _check_view()
	await _check_scene_flow()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 8 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _food_count(item_id: String) -> int:
	return Inventory.count(item_id, GameState.state["inventory"])


func _shop() -> void:
	if Clock.current_slot() == "morning":
		_check(Service.wait() == OK, "Waiting opens the shop at daytime")
	_check(Service.travel("hub_shop") == OK, "The open shop is a connected building location")


func _check_shop() -> void:
	_new_game()
	_check(not GameState.state.has("stealth") and not GameState.state.has("stealth_passed"), "Deferred stealth does not add save fields")
	_check(GameState.state["inventory"].is_empty(), "The player starts with an empty food inventory")
	_check(Service.travel("hub_shop") == ERR_UNAVAILABLE and Service.occupants("hub_shop").is_empty(), "The closed shop cannot be entered")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.buy_item("hub_shop_stock", "carrot") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Buying from a closed shop is atomic")
	_check(Service.wait() == OK and Service.occupants("hub_shop") == ["shopkeeper"], "The shopkeeper appears during opening slots")
	_check(Service.travel("hub_shop") == OK, "Opening time unlocks the shop entrance")
	_check(not GameState.state["heroines"]["shopkeeper"]["aboard"] and DataLoader.get_schedule("shopkeeper").is_empty(), "The shopkeeper stays off the ship and has no schedule")
	_check(EffectApplier.buy_item("hub_shop_stock", "carrot") == OK and GameState.state["money"] == 992, "Buying charges the JSON price")
	_check(_food_count("carrot") == 1 and GameState.state["ship"]["cargo"]["items"].is_empty(), "Food goes to the player rather than ship cargo")
	_check(OrderManager.active_mass() == 0, "Food contributes no cargo mass")
	_check(Conditions.evaluate([{"item": "carrot", "count": 1}]) and not Conditions.evaluate([{"item": "carrot", "count": 2}]), "Item conditions read the player inventory")
	_check(EffectApplier.sell_item("hub_shop_stock", "carrot") == OK and GameState.state["money"] == 996 and _food_count("carrot") == 0, "Selling uses sell_ratio and removes one item")
	GameState.state["money"] = 0
	snapshot = GameState.serialize()
	_check(EffectApplier.buy_item("hub_shop_stock", "carrot") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Insufficient money cannot create an item")
	GameState.state["money"] = 1000
	GameState.state["ship"]["cargo"]["max_mass"] = 0
	_check(EffectApplier.apply_effects([{"item": "carrot", "add": 100}]) == OK and _food_count("carrot") == 100, "Food can be carried with a full ship hold")
	snapshot = GameState.serialize()
	_check(EffectApplier.apply_effects([{"money": -10}, {"item": "scrap_test", "add": 1}]) == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Mass-bearing items respect cargo capacity before charging money")
	_check(EffectApplier.apply_effects([{"money": 10}, {"item": "carrot", "add": -101}]) == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Insufficient item counts reject the entire effect batch")
	_check(EffectApplier.buy_item("hub_shop_stock", "cookbook_xeno_spices") == ERR_UNAVAILABLE, "Attitude gates protect locked goods")
	_check(EffectApplier.apply_effects([{"item": "missing", "add": 1}]) == ERR_INVALID_DATA, "Unknown item effects are rejected")


func _check_cooking() -> void:
	_new_game()
	_check(EffectApplier.apply_effects([{"item": "carrot", "add": 3}]) == OK, "Cooking fixtures use normal item effects")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "plate") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "A raw ingredient cannot skip straight to the plate")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_02", "carrot", "cut") == ERR_UNAVAILABLE, "An unlearned recipe cannot be cooked")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "cut") == OK and GameState.state["kitchen"]["entries"][0]["steps"].is_empty(), "Placing a carrot does not process it before the button is pressed")
	_check(EffectApplier.process_kitchen_zone("cut") == OK, "The cutting action chops the placed carrot")
	_check(_food_count("carrot") == 3 and Clock.current_slot() == "morning", "Preparation reserves no ingredient or time before confirmation")
	snapshot = GameState.serialize()
	_check(EffectApplier.process_kitchen_zone("cut") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "The same preparation cannot be duplicated")
	_check(not Conditions.can_wait() and not Conditions.can_enter("hub_shop"), "Unfinished cooking stays in the kitchen until completed or cancelled")
	_check(GameState.save_game(SAVE) == OK, "A chopped carrot can be saved")
	EffectApplier.cancel_cooking()
	_check(GameState.load_game(SAVE) == OK and GameState.serialize() == snapshot, "Loading restores the exact preparation and zone")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "fry", 0) == OK and EffectApplier.process_kitchen_zone("fry") == OK and EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "boil", 0) == OK and EffectApplier.process_kitchen_zone("boil") == OK, "Frying and boiling actions work after chopping")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "plate", 0) == OK and Conditions.can_finish_cooking(), "A prepared carrot can be plated")
	_check(EffectApplier.finish_cooking() == OK and _food_count("carrot") == 2 and _food_count("dish_carrot_01") == 1, "Confirmation exchanges one carrot for a dish")
	_check(GameState.state["cooking_skill"] == 1 and Clock.current_slot() == "day" and GameState.state["kitchen"].is_empty(), "Confirmation spends one slot, gains skill and clears the counter")
	_check(GameState.state["inventory"][1]["quality"] == 1, "Dish quality is stored in inventory")
	snapshot = GameState.serialize()
	_check(EffectApplier.finish_cooking() == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Repeated confirmation cannot duplicate food")
	_check(Cooking.quality(0) == 1 and Cooking.quality(4) == 1 and Cooking.quality(5) == 2 and Cooking.quality(10) == 3 and Cooking.quality(100) == 3, "Quality increases every five cooked dishes and caps at three")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "boil") == OK, "Preparation order is flexible")
	EffectApplier.cancel_cooking()
	_check(_food_count("carrot") == 2 and Clock.current_slot() == "day", "Cancelling leaves ingredients and time unchanged")
	_check(Service.travel("hub_shop") == OK and not Conditions.can_use_food(1), "Food cannot be used outside the hub kitchen")


func _check_mixing() -> void:
	_new_game()
	EffectApplier.apply_effects([{"item": "carrot", "add": 2}, {"item": "noodles", "add": 2}])
	_check(EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "boil") == OK and EffectApplier.prepare_ingredient("recipe_carrot_noodles", "noodles", "boil") == OK, "Different ingredients can share one pot")
	_check(GameState.state["kitchen"]["entries"].size() == 2 and not Conditions.can_finish_cooking(), "A mixture retains distinct ingredient portions")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "boil") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "A recipe cannot reserve excess portions")
	_check(EffectApplier.apply_effects([{"money": 10}, {"item": "carrot", "add": -2}]) == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "Reserved ingredients cannot be removed through another effect")
	_check(EffectApplier.process_kitchen_zone("boil") == OK and GameState.state["kitchen"]["entries"][0]["steps"] == ["boil"] and GameState.state["kitchen"]["entries"][1]["steps"] == ["boil"], "One cooking button processes every suitable ingredient in the pot")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "plate", 0) == OK and not Conditions.can_finish_cooking(), "Every ingredient must reach the plate before confirmation")
	_check(EffectApplier.prepare_ingredient("recipe_carrot_noodles", "noodles", "plate", 1) == OK and EffectApplier.finish_cooking() == OK, "The assembled mixture produces its authored dish")
	_check(_food_count("carrot") == 1 and _food_count("noodles") == 1 and _food_count("dish_carrot_noodles") == 1 and Clock.current_slot() == "day", "Confirmation consumes each reserved ingredient once and spends one slot")
	_new_game()
	EffectApplier.apply_effects([{"item": "carrot", "add": 1}, {"item": "noodles", "add": 1}])
	EffectApplier.prepare_ingredient("recipe_carrot_noodles", "carrot", "cut")
	EffectApplier.prepare_ingredient("recipe_carrot_noodles", "noodles", "cut")
	_check(EffectApplier.process_kitchen_zone("cut") == OK and GameState.state["kitchen"]["entries"][1]["steps"].is_empty(), "A mixed zone processes only ingredients that support its action")
	EffectApplier.cancel_cooking()


func _check_serving() -> void:
	_new_game()
	EffectApplier.apply_effects([{"item": "dish_carrot_01", "add": 5}])
	_check(EffectApplier.use_food(0, "pilot") == OK and GameState.state["served_days"]["pilot"] == 1, "A present heroine can receive a dish")
	_check(GameState.state["heroines"]["pilot"]["mood"] == 66 and GameState.state["heroines"]["pilot"]["attitude"] == 22, "Neutral food applies the recipe effects")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.use_food(0, "pilot") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "The same heroine cannot receive a second dish that day")
	_check(EffectApplier.use_food(0, "medic") == OK, "Another heroine can receive a dish on the same day")
	_check(EffectApplier.use_food(0, "security") == ERR_UNAVAILABLE, "Absent heroines cannot receive dishes")
	_check(Cooking.taste(["spicy"], {"likes": ["spicy"], "dislikes": []}) == 1.5 and Cooking.taste(["sweet"], {"dislikes": ["sweet"]}) == -1 and Cooking.gain(6, 3, 1.5) == 13.5, "Taste and quality scale food effects")
	_check(EffectApplier.use_food(0) == OK and GameState.state["buffs"].get("steady_hands") == 2, "Eating applies a temporary recipe buff")
	Clock.advance_slots(4)
	_check(not GameState.state["buffs"].has("steady_hands") and Conditions.can_use_food(0, "pilot"), "Buff expiration and serving reset at the next day")
	GameState.state["heroines"]["pilot"]["mood"] = 19
	_check(not Conditions.can_use_food(0, "pilot"), "A heroine below twenty mood refuses food")
	GameState.state["heroines"]["pilot"]["mood"] = 50
	GameState.state["heroines"]["medic"]["polygamy"] = "forbids"
	_check(EffectApplier.use_food(0, "pilot") == OK and GameState.state["heroines"]["medic"]["suspicion"] == 5, "A public serving raises a forbidding witness's suspicion")
	_new_game()
	GameState.state["cooking_skill"] = 10
	EffectApplier.apply_effects([{"item": "carrot", "add": 1}])
	EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "fry")
	EffectApplier.process_kitchen_zone("fry")
	EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "plate", 0)
	EffectApplier.finish_cooking()
	_check(GameState.state["inventory"][0]["quality"] == 3, "The actual cooking action produces quality three at skill ten")
	Clock.advance_slots(3)
	var food: Dictionary = DataLoader.records["pilot"]["food"].duplicate(true)
	DataLoader.records["pilot"]["food"]["likes"] = ["vegetable"]
	_check(EffectApplier.use_food(0, "pilot") == OK and GameState.state["heroines"]["pilot"]["mood"] == 73.5, "Serving applies the quality and liked-taste multipliers to actual mood")
	DataLoader.records["pilot"]["food"] = food


func _check_books_and_orders() -> void:
	_new_game()
	_shop()
	_check(not Conditions.can_accept_shop_quest("shop_quest_02"), "Later shop tasks require the preceding task")
	_check(EffectApplier.accept_shop_quest("shop_quest_01") == OK and EffectApplier.complete_shop_quest("shop_quest_01") == OK, "The first labor task is accepted and completed")
	_check(Clock.current_slot() == "evening" and GameState.state["heroines"]["shopkeeper"]["attitude"] == 10, "Labor spends its slots and rewards attitude")
	_check(EffectApplier.accept_shop_quest("shop_quest_02") == OK and not Conditions.can_complete_shop_quest("shop_quest_02"), "Fetch tasks require actual inventory")
	EffectApplier.buy_item("hub_shop_stock", "carrot")
	EffectApplier.buy_item("hub_shop_stock", "carrot")
	_check(EffectApplier.complete_shop_quest("shop_quest_02") == OK and _food_count("carrot") == 0 and Conditions.can_buy_item("hub_shop_stock", "cookbook_xeno_spices"), "Delivering items consumes them and unlocks the cookbook")
	_check(EffectApplier.complete_shop_quest("shop_quest_02") == ERR_UNAVAILABLE, "Completed tasks cannot pay twice")
	_check(EffectApplier.buy_item("hub_shop_stock", "cookbook_xeno_spices") == OK and OrderManager.active_mass() == 1, "A cookbook uses ordinary mass-bearing ship cargo")
	_check(EffectApplier.read_book(0) == OK and GameState.state["known_recipes"].size() == 4 and OrderManager.active_mass() == 0, "Reading consumes the book, frees mass and permanently teaches recipes")
	_check(EffectApplier.accept_shop_quest("shop_quest_03") == OK, "The final placeholder task opens")
	Clock.advance_slots(40)
	_check(OrderManager.status("shop_quest_03") == "active" and not OrderManager.is_overdue("shop_quest_03"), "Shop tasks never expire or incur failure penalties")
	_check(GameState.state["flags"].get("shopkeeper_story_02_unlocked", false), "Quest rewards unlock a placeholder scene")


func _check_persistence() -> void:
	_new_game()
	EffectApplier.apply_effects([{"item": "carrot", "add": 2}])
	EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "fry")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.save_game(SAVE) == OK, "The full domestic state serializes")
	EffectApplier.cancel_cooking()
	_check(GameState.load_game(SAVE) == OK and GameState.serialize() == snapshot, "Domestic state round-trips through JSON")
	for field: String in ["inventory", "known_recipes", "served_days", "kitchen", "buffs"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid[field] = false
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid " + field + " is rejected atomically")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["inventory"][0]["count"] = -1
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Negative food counts cannot load")
	invalid = snapshot.duplicate(true)
	invalid["kitchen"]["entries"][0]["steps"] = ["teleport"]
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Unknown preparation steps cannot load")
	invalid = snapshot.duplicate(true)
	invalid["location"] = "hub_office"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "An unfinished kitchen cannot load in another room")
	invalid = snapshot.duplicate(true)
	invalid["ship"]["cargo"]["items"] = [{"item": "carrot", "count": 1}]
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Food cannot be smuggled into ship cargo by a save")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy["kitchen"] = {"recipe": "recipe_carrot_01", "item": "carrot", "steps": ["cut", "fry"], "zone": "fry"}
	legacy["known_recipes"].erase("recipe_carrot_noodles")
	_check(GameState.restore(legacy) == OK and GameState.state["kitchen"]["entries"] == [{"item": "carrot", "steps": ["cut", "fry"], "zone": "fry"}], "Previous one-ingredient saves migrate without losing processing")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK, "The verification save is removed")
	EffectApplier.cancel_cooking()


func _check_content() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["recipes"][1]["id"] = "unobtainable_recipe"
	_check(not Validator.validate(groups, DataLoader.record_sources).is_empty(), "Unobtainable recipes are reported by DataLoader validation")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["shops"][0]["items"] = groups["shops"][0]["items"].filter(func(entry: Dictionary) -> bool: return entry["item"] != "cookbook_xeno_spices")
	_check("cookbook has no" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "A cookbook without a source is reported")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["recipes"][0]["dish"] = "missing_dish"
	_check("missing_dish" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Recipe output ids are validated")
	groups = DataLoader.records_by_group.duplicate(true)
	for record: Dictionary in groups["ui"]:
		if record["id"] == "kitchen_layout":
			record["zones"]["cut"]["drop_rect"] = [-0.1, 0.2, 0.3, 0.2]
	_check("drop_rect must stay inside" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Kitchen hit regions are validated against the background bounds")


func _check_view() -> void:
	_new_game()
	_shop()
	var shop: Control = DomesticScene.instantiate()
	shop.tab = "shop"
	add_child(shop)
	await get_tree().process_frame
	var buy: Button = shop.find_child("carrot", true, false).find_child("Buy", true, false)
	_check(buy != null and not buy.disabled, "The shop renders an available carrot purchase button")
	buy.pressed.emit()
	await get_tree().process_frame
	_check(_food_count("carrot") == 1, "The actual purchase button adds food")
	await _capture("shop")
	shop.queue_free()
	await get_tree().process_frame
	_check(Service.travel("hub_kitchen") == OK, "The player returns from the shop to the kitchen")
	var view: Control = DomesticScene.instantiate()
	view.tab = "kitchen"
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var token: Control = view.find_child("carrot", true, false)
	var zone: Control = view.find_child("cut", true, false)
	_check(token != null and zone != null and zone._can_drop_data(Vector2.ZERO, {"item": "carrot", "entry": -1}), "The cooking screen exposes a valid ingredient drop target")
	await _drag(token, zone)
	_check(GameState.state["kitchen"].get("entries", [{}])[0].get("zone") == "cut" and GameState.state["kitchen"]["entries"][0]["steps"].is_empty(), "Native mouse dragging places a raw carrot on the pictured board")
	await _press(view.find_child("cut", true, false).get_node("Process"))
	await get_tree().process_frame
	await get_tree().process_frame
	for target: String in ["fry", "boil", "plate"]:
		var prepared: Control = view.find_child("Prepared", true, false)
		var destination: Control = view.find_child(target, true, false)
		if prepared != null:
			await _drag(prepared, destination)
		_check(GameState.state["kitchen"]["entries"][0]["zone"] == target, "Dragging the prepared carrot reaches " + target)
		if target != "plate":
			view.find_child(target, true, false).get_node("Process").pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
	await _capture("kitchen")
	var finish: Button = view.find_child("Finish", true, false)
	_check(finish != null and not finish.disabled, "The confirmation button unlocks after plating")
	finish.pressed.emit()
	await get_tree().process_frame
	_check(_food_count("dish_carrot_01") == 1, "The actual confirmation button cooks the dish")
	EffectApplier.apply_effects([{"item": "carrot", "add": 1}, {"item": "noodles", "add": 1}])
	await get_tree().process_frame
	await get_tree().process_frame
	var select: OptionButton = view.find_child("Recipe", true, false)
	var mixed_index: int = GameState.state["known_recipes"].find("recipe_carrot_noodles")
	select.selected = mixed_index
	select.item_selected.emit(mixed_index)
	await get_tree().process_frame
	await get_tree().process_frame
	await _drag(view.find_child("carrot", true, false), view.find_child("fry", true, false))
	await _drag(view.find_child("noodles", true, false), view.find_child("fry", true, false))
	_check(GameState.state["kitchen"]["entries"].size() == 2, "A second ingredient can be dropped onto an already occupied pan")
	await _press(view.find_child("fry", true, false).get_node("Process"))
	_check(GameState.state["kitchen"]["entries"][0]["steps"] == ["fry"] and GameState.state["kitchen"]["entries"][1]["steps"] == ["fry"], "A real click on the transparent action processes the whole pan")
	await _capture("mixed-pan")
	var cancel_rect: Rect2 = view.find_child("Cancel", true, false).get_global_rect()
	_check(cancel_rect.end.x <= get_viewport().get_visible_rect().end.x and cancel_rect.end.y <= get_viewport().get_visible_rect().end.y, "The cancel action stays fully inside the cooking viewport")
	await _drag(view.find_child("Prepared", true, false), view.find_child("plate", true, false))
	await _drag(view.find_child("Prepared_1", true, false), view.find_child("plate", true, false))
	_check(Conditions.can_finish_cooking(), "Both portions can be assembled on the pictured plate")
	await _capture("mixed-plate")
	await _press(view.find_child("Finish", true, false))
	_check(_food_count("dish_carrot_noodles") == 1, "The normal kitchen flow produces the mixed recipe")
	view.queue_free()
	await get_tree().process_frame
	Clock.advance_slots()
	var inventory_view: Control = DomesticScene.instantiate()
	add_child(inventory_view)
	await get_tree().process_frame
	_check(inventory_view.find_child("pilot", true, false) == null, "Serving is accessed through conversation instead of inventory")
	if not FileAccess.file_exists(GameState.SAVE_PATH):
		inventory_view.find_child("Save", true, false).pressed.emit()
		var snapshot: Dictionary = GameState.serialize()
		EffectApplier.apply_effects([{"money": 100}])
		inventory_view.find_child("Load", true, false).pressed.emit()
		_check(GameState.serialize() == snapshot and FileAccess.file_exists(GameState.SAVE_PATH), "Domestic save/load buttons restore the exact state through user://save.json")
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH)) == OK, "The isolated user-save probe is removed")
	await _capture("inventory")
	inventory_view.queue_free()
	await get_tree().process_frame
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await get_tree().process_frame
	_check(hub.get_node("%Locations").has_node("hub_shop") and hub.has_node("KitchenHotspot/Cook"), "The hub exposes the shop card and pictured kitchen hotspot")
	_check(hub.open_dialogue("pilot"), "The player approaches the heroine for a kitchen conversation")
	await get_tree().process_frame
	var dialogue: Control = hub.get_node("%DialogueContent").get_child(0)
	dialogue.find_child("MealMenu", true, false).pressed.emit()
	await get_tree().process_frame
	var serve: Button = dialogue.find_child("Offer_0", true, false)
	_check(serve != null and not serve.disabled, "Conversation exposes an available dish offer")
	serve.pressed.emit()
	await get_tree().process_frame
	_check(GameState.state["served_days"].get("pilot") == Clock.current_day() and _food_count("dish_carrot_01") == 0, "The conversation consumes the dish and records the heroine's day")
	hub.queue_free()
	await get_tree().process_frame


func _check_scene_flow() -> void:
	get_tree().current_scene = null
	_check(get_tree().change_scene_to_file("res://scenes/boot.tscn") == OK, "The real project entry point starts")
	var hub: Node = await _wait_scene("Hub")
	_check(hub != null, "The project boots into the hub")
	if hub == null:
		return
	await _capture("hub")
	_check(Service.wait() == OK and Service.travel("hub_shop") == OK, "The real hub reaches the shop after it opens")
	Service.travel("hub_kitchen")
	Service.travel("hub_office")
	_check(hub.get_node("%Background").texture.resource_path == "res://art/backgrounds/hub_office.png", "The supplied office image is visible in the actual hub")
	await _capture("office")
	Service.travel("hub_kitchen")
	Service.travel("hub_shop")
	hub.find_child("DomesticActions", true, false).get_node("shop").pressed.emit()
	await get_tree().process_frame
	var overlay: Control = hub.find_child("Domestic", true, false)
	_check(overlay != null, "The shop button opens the domestic overlay in the real hub")
	overlay.find_child("carrot", true, false).find_child("Buy", true, false).pressed.emit()
	overlay.find_child("Close", true, false).pressed.emit()
	await get_tree().process_frame
	Service.travel("hub_kitchen")
	EffectApplier.prepare_ingredient("recipe_carrot_01", "carrot", "cut")
	var cooking: Dictionary = GameState.serialize()
	EffectApplier.cancel_cooking()
	Service.travel("hub_tech")
	EffectApplier.launch_flight()
	get_tree().change_scene_to_file("res://scenes/system_flight.tscn")
	var flight: Node = await _wait_scene("SystemFlight")
	_check(flight != null, "Flight remains reachable after a food purchase")
	if flight == null:
		return
	flight.set_physics_process(false)
	EffectApplier.toggle_flight_pause()
	var in_flight: Dictionary = GameState.serialize()
	_check(GameState.restore(cooking) == OK, "A cooking snapshot can be restored from flight")
	hub = await _wait_scene("Hub")
	_check(hub != null and GameState.serialize() == cooking, "Restoring returns to the hub with exact unfinished cooking")
	if hub == null:
		return
	_check(hub.find_child("Domestic", true, false) != null and hub.find_child("Prepared", true, false) != null, "The unfinished kitchen automatically reopens with the prepared ingredient")
	_check(GameState.restore(in_flight) == OK, "A flight snapshot can be restored while the kitchen overlay is open")
	flight = await _wait_scene("SystemFlight")
	_check(flight != null and GameState.serialize() == in_flight, "The kitchen overlay restores the correct flight scene without losing inventory")
	if flight != null:
		flight.set_physics_process(false)


func _wait_scene(scene_name: String) -> Node:
	for _frame: int in range(90):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == scene_name:
			return get_tree().current_scene
	return null


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
	move.relative = to - from
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	get_viewport().push_input(up, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _press(button: Button) -> void:
	await get_tree().process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-domestic" not in OS.get_cmdline_user_args():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if "--small-domestic" in OS.get_cmdline_user_args():
		suffix += "-small"
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/stage-eight-" + suffix + ".png") == OK, "The " + suffix + " view renders to a screenshot")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
