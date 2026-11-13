extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Appearance = preload("res://scripts/heroine_appearance.gd")
const Portrait = preload("res://scripts/heroine_portrait.gd")
const Runner = preload("res://scripts/dialogue_runner.gd")
const Validator = preload("res://scripts/data_validator.gd")
const Service = preload("res://scripts/hub_service.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const SAVE: String = "res://.godot/stage-nine-save.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All stage-nine content loads without errors")
	_check_appearance_rules()
	_check_privacy()
	_check_persistence()
	_check_content()
	await _check_portrait()
	await _check_vertical_slice()
	await _check_privacy_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 9 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_quiet_flight()


func _quiet_flight() -> void:
	GameState.state["flags"].merge({"courier_test_done": true, "transport_test_done": true, "signal_test_done": true})
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["role"] == "pirate":
			GameState.state["flight"]["npcs"][npc["id"]]["cooldown"] = 10000.0


func _check_appearance_rules() -> void:
	var blueprint: Dictionary = DataLoader.get_record("pilot")
	for sample: Dictionary in [
		{"mood": 100, "face": "happy"}, {"mood": 70, "face": "happy"},
		{"mood": 69, "face": "neutral"}, {"mood": 40, "face": "neutral"},
		{"mood": 39, "face": "annoyed"}, {"mood": 20, "face": "annoyed"},
		{"mood": 19, "face": "sad"}, {"mood": 0, "face": "sad"}
	]:
		_check(Appearance.select(blueprint, {"mood": sample["mood"]})["face"] == sample["face"], "Portrait mood threshold selects " + str(sample["face"]))
	for sample: Dictionary in [{"arousal": 24, "blush": 0}, {"arousal": 25, "blush": 1}, {"arousal": 59, "blush": 1}, {"arousal": 60, "blush": 2}]:
		_check(Appearance.select(blueprint, {"attitude": 30, "arousal": sample["arousal"]})["blush"] == sample["blush"], "Portrait blush thresholds match the schema")
	_check(Appearance.select(blueprint, {"attitude": 29, "arousal": 100})["blush"] == 0, "Blush is hidden below the heroine's touch threshold")
	_check(Appearance.select(blueprint, {})["base"] == "uniform", "The portrait uses its existing JSON base id")


func _check_privacy() -> void:
	_new_game()
	Clock.advance_slots()
	Service.travel("hub_shop")
	GameState.state["heroines"]["shopkeeper"]["attitude"] = 85.0
	GameState.state["heroines"]["shopkeeper"]["mood"] = 100.0
	_check(EffectApplier.apply_effects([{"stat": "shopkeeper.suspicion", "add": 99}]) == OK and not GameState.state["heroines"]["shopkeeper"]["contact_block"], "Suspicion below one hundred leaves communication open")
	_check(EffectApplier.apply_effects([{"stat": "shopkeeper.suspicion", "add": 1}]) == OK, "A suspicion stat effect can reach the disclosure threshold")
	var heroine: Dictionary = GameState.state["heroines"]["shopkeeper"]
	_check(heroine["attitude"] == 45 and heroine["contact_block"], "Disclosure subtracts exactly forty attitude even at high mood")
	_check(GameState.state["pending_scenes"] == ["shopkeeper_disclosure_test"], "Disclosure queues its JSON scene once")
	_check(Conditions.evaluate([{"stat": "shopkeeper.suspicion", "op": ">=", "value": 100}, {"contact_block": "shopkeeper", "is": true}]), "Suspicion and contact conditions read GameState")
	_check(not Conditions.can_talk("shopkeeper") and Conditions.can_open_conversation("shopkeeper"), "Normal interaction is blocked while disclosure remains accessible")
	_check(not Runner.is_available(DataLoader.get_record("shopkeeper_privacy_probe")) and not Runner.is_available(DataLoader.get_record("shopkeeper_reconciliation_test")), "Normal scenes and early reconciliation cannot bypass a pending disclosure")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.apply_effects([{"stat": "shopkeeper.suspicion", "add": 1}]) == OK and heroine["attitude"] == 45 and GameState.state["pending_scenes"].size() == 1, "Further suspicion cannot repeat the penalty or duplicate the queue")
	_check(GameState.save_game(SAVE) == OK and GameState.load_game(SAVE) == OK and GameState.state["heroines"]["shopkeeper"]["attitude"] == 45, "Loading a disclosure never reapplies its penalty")
	_check(Conditions.next_pending_scene() == "shopkeeper_disclosure_test", "The queued scene becomes available in the correct location")
	Service.travel("hub_kitchen")
	_check(Conditions.next_pending_scene().is_empty() and GameState.state["pending_scenes"].size() == 1, "A queued reaction waits for the proper room and heroine")
	Service.travel("hub_shop")
	_check(Runner.choose("shopkeeper_disclosure_test", "acknowledge") == OK and GameState.state["pending_scenes"].is_empty(), "Completing the disclosure removes the pending scene")
	_check(Runner.is_available(DataLoader.get_record("shopkeeper_reconciliation_test")), "The reconciliation placeholder opens after disclosure")
	_check(Runner.choose("shopkeeper_reconciliation_test", "reconcile") == OK, "The placeholder reconciliation applies its JSON effects")
	_check(GameState.state["heroines"]["shopkeeper"]["suspicion"] == 0 and not GameState.state["heroines"]["shopkeeper"]["contact_block"] and Conditions.can_talk("shopkeeper"), "Reconciliation clears suspicion and restores communication")
	_check(GameState.state["heroines"]["shopkeeper"]["attitude"] == 45, "Reconciliation does not invent an attitude refund")
	_check(EffectApplier.apply_effects([{"stat": "shopkeeper.suspicion", "add": 100}]) == OK and GameState.state["pending_scenes"] == ["shopkeeper_disclosure_test"], "A later incident can queue a fresh disclosure")
	_check(not Runner.is_available(DataLoader.get_record("shopkeeper_reconciliation_test")), "A previous seen flag cannot skip a new disclosure")
	_check(GameState.restore(snapshot) == OK, "The privacy fixture can restore an earlier exact state")
	var before: Dictionary = GameState.serialize()
	_check(EffectApplier.apply_effects([{"money": 10}, {"contact_block": "missing", "set": true}]) == ERR_INVALID_DATA and GameState.serialize() == before, "Unknown contact targets reject an entire effect batch")
	_check(EffectApplier.apply_effects([{"stat": "shopkeeper.suspicion", "add": 0.5}]) == ERR_INVALID_DATA and GameState.serialize() == before, "Suspicion remains an integer")
	_new_game()
	_check(EffectApplier.apply_effects([{"stat": "pilot.suspicion", "add": 100}]) == OK and not GameState.state["heroines"]["pilot"]["contact_block"], "The forbids penalty is not applied to tolerates")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK, "The privacy fixture save is removed")


func _check_persistence() -> void:
	_new_game()
	for old_size: int in [22, 21]:
		var old: Dictionary = GameState.serialize()
		old.erase("pending_scenes")
		if old_size == 21:
			old.erase("meal_invites")
		_check(GameState.restore(old) == OK and GameState.state["pending_scenes"].is_empty(), "Previous " + str(old_size) + "-field saves upgrade without losing their state")
	var snapshot: Dictionary = GameState.serialize()
	for value: Variant in [false, ["missing_scene"], ["slice_evening", "slice_evening"], [3]]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["pending_scenes"] = value
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Invalid queued scene references are rejected atomically")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["heroines"]["shopkeeper"]["contact_block"] = "yes"
	_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Contact state must remain a boolean")


func _check_content() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["scenes"] = groups["scenes"].filter(func(scene: Dictionary) -> bool: return scene["id"] != "shopkeeper_disclosure_test")
	_check("missing disclosure" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "A forbids heroine must have a disclosure scene")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["scenes"].append(DataLoader.get_record("shopkeeper_reconciliation_test").duplicate(true))
	_check("must be unique" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Ambiguous reconciliation scenes are reported")
	groups = DataLoader.records_by_group.duplicate(true)
	for scene: Dictionary in groups["scenes"]:
		if scene["id"] == "shopkeeper_disclosure_test":
			scene["conditions"][0]["contact_block"] = "missing_heroine"
	_check("missing_heroine" in "\n".join(Validator.validate(groups, DataLoader.record_sources)), "Contact-condition heroine ids are validated")
	for scene: Dictionary in DataLoader.get_records("scenes"):
		for line: Dictionary in scene.get("lines", []):
			_check(line["text"] == "TODO scene text", "All narrative remains placeholder content")


func _check_portrait() -> void:
	_new_game()
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(80, 100)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var portrait: Portrait = Portrait.new()
	portrait.heroine_id = "pilot"
	portrait.size = Vector2(80, 100)
	viewport.add_child(portrait)
	_check(portrait.has_node("Base") and portrait.has_node("Face") and portrait.has_node("Blush"), "A portrait has three separate layers")
	var previous: PackedByteArray = []
	for mood: int in [80, 50, 25, 10]:
		GameState.state["heroines"]["pilot"]["mood"] = float(mood)
		portrait.refresh()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels: PackedByteArray = viewport.get_texture().get_image().get_data()
		_check(not pixels.is_empty() and pixels != previous, "The rendered face changes across mood bands")
		previous = pixels
	GameState.state["heroines"]["pilot"]["attitude"] = 30.0
	EffectApplier.apply_effects([{"stat": "pilot.arousal", "add": 80}])
	_check(portrait.appearance["blush"] == 2 and portrait.get_node("Blush").visible, "Stat effects update the visible blush layer")
	EffectApplier.apply_effects([{"stat": "pilot.attitude", "add": -30}])
	_check(not portrait.get_node("Blush").visible, "Dropping below touch hides the blush layer")
	viewport.queue_free()
	await get_tree().process_frame


func _check_vertical_slice() -> void:
	get_tree().current_scene = null
	_check(get_tree().change_scene_to_file("res://scenes/boot.tscn") == OK, "The regular project entry point starts")
	var hub: Node = await _wait_scene("Hub")
	_check(hub != null, "The real hub loads")
	if hub == null:
		return
	_quiet_flight()
	hub.get_node("%Locations/hub_office/Travel").pressed.emit()
	hub.get_node("OfficeHotspot/Computer").pressed.emit()
	var terminal: Control = hub.get_node("%TerminalContent").get_child(0)
	terminal.find_child("ord_slice_test", true, false).find_child("Accept", true, false).pressed.emit()
	_check(OrderManager.status("ord_slice_test") == "active" and OrderManager.active_mass() == 1, "The real terminal accepts the slice order and reserves cargo")
	hub.get_node("%CloseTerminal").pressed.emit()
	hub.get_node("%Locations/hub_tech/Travel").pressed.emit()
	hub.get_node("TechHotspot/Computer").pressed.emit()
	hub.get_node("%TerminalContent/ComputerMenu/Launch").pressed.emit()
	var flight: Node = await _wait_scene("SystemFlight")
	_check(flight != null, "The workshop computer launches the actual 3D flight scene")
	if flight == null:
		return
	flight.set_physics_process(false)
	_check(not Conditions.can_deliver_order("ord_slice_test"), "Delivery is unavailable away from the destination planet")
	var snapshot: Dictionary = GameState.serialize()
	_check(EffectApplier.deliver_order("ord_slice_test") == ERR_UNAVAILABLE and GameState.serialize() == snapshot, "An early delivery attempt cannot grant rewards")
	EffectApplier.set_flight_target(Motion.point(Conditions.space_object("earth_2")["pos"]))
	_check(Motion.point(GameState.state["flight"]["target"]) == Vector2(1950, 1200), "The delivery target remains the authored destination planet")
	EffectApplier.advance_flight(12.0)
	_check(Motion.point(GameState.state["flight"]["pos"]).distance_to(Vector2(1950, 1200)) < 1, "The ship reaches the delivery planet through normal real-time motion")
	_check(Conditions.can_deliver_order("ord_slice_test"), "Approaching the correct planet unlocks hand-in through dialogue")
	flight.find_child("ObjectInteractions", true, false).get_node("earth_2/Dialogue").pressed.emit()
	var planet_panel: Control = flight.get_node("PlanetPanel")
	var delivery: Button = planet_panel.find_child("Deliver_ord_slice_test", true, false)
	await _capture("destination")
	delivery.pressed.emit()
	planet_panel.find_child("Close", true, false).pressed.emit()
	_check(OrderManager.status("ord_slice_test") == "completed" and GameState.state["money"] == 1250 and GameState.state["flags"].get("slice_delivery_done", false), "Real delivery grants its JSON rewards once")
	_check(OrderManager.active_mass() == 0 and Clock.current_slot() == "day", "Delivery frees cargo and spends its configured time slot")
	_check(EffectApplier.deliver_order("ord_slice_test") == ERR_UNAVAILABLE and GameState.state["money"] == 1250, "A delivery cannot be completed twice")
	EffectApplier.toggle_flight_pause()
	_check(GameState.save_game(SAVE) == OK, "The completed delivery is saved in paused flight")
	EffectApplier.toggle_flight_pause()
	_fly(Vector2(900, 660))
	flight.find_child("ObjectInteractions", true, false).get_node("earth_1/Dialogue").pressed.emit()
	flight.get_node("PlanetPanel").find_child("Dock", true, false).pressed.emit()
	hub = await _wait_scene("Hub")
	_check(hub != null and GameState.state["location"] == "hub_office", "Returning to Earth docks at the building hub")
	_check(GameState.load_game(SAVE) == OK, "The completed-delivery save can be loaded from the hub")
	flight = await _wait_scene("SystemFlight")
	_check(flight != null and GameState.state["money"] == 1250 and OrderManager.status("ord_slice_test") == "completed", "Restoring flight does not repeat the delivery payout")
	if flight == null:
		return
	flight.set_physics_process(false)
	EffectApplier.toggle_flight_pause()
	_fly(Vector2(900, 660))
	flight.find_child("ObjectInteractions", true, false).get_node("earth_1/Dialogue").pressed.emit()
	flight.get_node("PlanetPanel").find_child("Dock", true, false).pressed.emit()
	hub = await _wait_scene("Hub")
	if hub == null:
		_check(false, "The restored flight returns to the hub")
		return
	hub.get_node("%Wait").pressed.emit()
	hub.get_node("%Locations/hub_kitchen/Travel").pressed.emit()
	hub.get_node("%Locations/hub_shop/Travel").pressed.emit()
	hub.get_node("%People/shopkeeper").pressed.emit()
	var dialogue: Control = hub.get_node("%DialogueContent").get_child(0)
	_check(dialogue.get_node("%SceneId").text == "slice_evening" and Clock.current_slot() == "evening", "Returning from the trip opens its evening scene through normal conversation")
	_check(dialogue.find_child("HeroinePortrait", true, false).has_node("Face"), "The evening scene shows the layered heroine portrait")
	await _capture("evening")
	dialogue.get_node("%Choices/finish").pressed.emit()
	await get_tree().process_frame
	_check(GameState.state["flags"].get("slice_finished", false) and Clock.current_slot() == "night", "The full order-flight-delivery-evening slice finishes")
	_check(not Runner.is_available(DataLoader.get_record("slice_evening")), "The completed evening scene cannot repeat its effects")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK, "The slice verification save is removed")


func _check_privacy_view() -> void:
	_new_game()
	EffectApplier.apply_effects([{"flag": "privacy_test_enabled", "set": true}, {"stat": "shopkeeper.attitude", "add": 80}])
	Clock.advance_slots()
	var hub: Node = get_tree().current_scene
	hub.get_node("%Locations/hub_shop/Travel").pressed.emit()
	hub.get_node("%People/shopkeeper").pressed.emit()
	var dialogue: Control = hub.get_node("%DialogueContent").get_child(0)
	_check(dialogue.get_node("%SceneId").text == "shopkeeper_privacy_probe", "The unlocked privacy probe is available through conversation")
	dialogue.get_node("%Choices/witness").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	dialogue = hub.get_node("%DialogueContent").get_child(0)
	_check(hub.get_node("%Conversation").visible and dialogue.get_node("%SceneId").text == "shopkeeper_disclosure_test", "The disclosure automatically opens from its queue")
	_check(GameState.state["heroines"]["shopkeeper"]["attitude"] == 40, "The visible disclosure applies the exact forty-point penalty")
	await _capture("disclosure")
	_check(GameState.save_game(SAVE) == OK, "The active disclosure can be saved")
	hub.get_node("%CloseDialogue").pressed.emit()
	_check(GameState.load_game(SAVE) == OK, "The active disclosure can be restored after closing it")
	await get_tree().process_frame
	await get_tree().process_frame
	dialogue = hub.get_node("%DialogueContent").get_child(0)
	_check(dialogue.get_node("%SceneId").text == "shopkeeper_disclosure_test" and GameState.state["heroines"]["shopkeeper"]["attitude"] == 40, "Loading resumes the queued scene without repeating its penalty")
	dialogue.get_node("%Choices/acknowledge").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hub.open_dialogue("shopkeeper"), "The blocked heroine still exposes the reconciliation scene")
	dialogue = hub.get_node("%DialogueContent").get_child(0)
	_check(dialogue.get_node("%SceneId").text == "shopkeeper_reconciliation_test", "Only reconciliation is available after acknowledgement")
	await _capture("reconciliation")
	dialogue.get_node("%Choices/reconcile").pressed.emit()
	await get_tree().process_frame
	_check(not GameState.state["heroines"]["shopkeeper"]["contact_block"] and GameState.state["pending_scenes"].is_empty(), "The actual reconciliation choice restores normal interaction")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE)) == OK, "The disclosure UI save is removed")


func _fly(position: Vector2) -> void:
	_check(EffectApplier.set_flight_target(position) == OK, "A flight target is set through the regular effect API")
	EffectApplier.advance_flight(12.0)
	_check(Motion.point(GameState.state["flight"]["pos"]).distance_to(position) < 1 and GameState.state["flight"]["encounter"].is_empty(), "The ship travels to the selected planet without a teleport")


func _wait_scene(scene_name: String) -> Node:
	for _frame: int in range(90):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == scene_name:
			return get_tree().current_scene
	return null


func _capture(suffix: String) -> void:
	if "--capture-nine" not in OS.get_cmdline_user_args():
		return
	if "--small-nine" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/stage-nine-" + suffix + ".png") == OK, "The " + suffix + " screenshot renders")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
