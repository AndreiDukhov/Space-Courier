extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Runner = preload("res://scripts/dialogue_runner.gd")
const Validator = preload("res://scripts/data_validator.gd")
const DialogueView = preload("res://scripts/dialogue.gd")
const SAVE_TEST_PATH: String = "res://.godot/stage-two-save-test.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "All dialogue data loads without errors")
	var pilot_scenes: Array[Dictionary] = DataLoader.get_records("scenes").filter(func(scene: Dictionary) -> bool: return str(scene["id"]).begins_with("pilot_test_"))
	_check(pilot_scenes.size() == 3, "The three original pilot test scenes are loaded")
	_check(DataLoader.get_record("pilot")["age"] >= 21, "The test heroine is an adult")
	_check_conditions()
	_check_effects()
	_check_validation()
	_check_runner()
	await _check_view()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 2 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game() -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))


func _check_conditions() -> void:
	_new_game()
	_check(Conditions.evaluate([]), "An empty condition list allows a scene")
	var comparisons: Array = [["==", 20, true], ["!=", 20, false], [">", 20, false], [">=", 20, true], ["<", 20, false], ["<=", 20, true], [">", 19, true], ["<", 21, true]]
	for comparison: Array in comparisons:
		_check(Conditions.evaluate([{"stat": "pilot.attitude", "op": comparison[0], "value": comparison[1]}]) == comparison[2], "Stat comparison '%s' respects its boundary" % comparison[0])
	_check(Conditions.evaluate([{"flag": "pilot_test_01_seen", "is": false}]), "Absent flags default to false")
	_check(not Conditions.evaluate([{"flag": "pilot_test_01_seen", "is": true}]), "Absent flags cannot satisfy true conditions")
	_check(Conditions.evaluate([{"time": ["morning"]}, {"aboard": "pilot", "is": true}]), "Time and aboard conditions read GameState")
	_check(not Conditions.evaluate([{"stat": "pilot.attitude", "op": ">=", "value": 0}, {"time": ["night"]}]), "Every condition must pass")
	_check(not Conditions.evaluate([{"stat": "missing.attitude", "op": ">=", "value": 0}]), "Missing characters fail closed")
	_check(not Conditions.evaluate([{"aboard": "missing", "is": false}]), "A nonexistent character is not treated as absent crew")
	_check(not Conditions.evaluate([{"stat": "pilot.attitude", "op": "unknown", "value": 20}]), "Unknown operators fail closed")
	_check(not Conditions.evaluate([{"flag": "pilot_test_01_seen", "is": 0}]), "Condition value types are checked")
	_check(not Conditions.evaluate([{"time": [1]}]), "Invalid time arrays fail closed")
	_check(not Conditions.evaluate([{"item": "xeno_crystal", "count": 1}]), "Future condition types fail closed")
	_check(not Conditions.evaluate([{"flag": "pilot_test_01_seen", "is": false, "time": ["morning"]}]), "Ambiguous condition objects are rejected")


func _check_effects() -> void:
	_new_game()
	_check(EffectApplier.apply_effects([{"stat": "pilot.mood", "add": 15}, {"stat": "pilot.attitude", "add": 8}]) == OK, "A batch of effects is accepted")
	_check(_stat("mood") == 75 and _stat("attitude") == 30, "Effects run in order and use the new mood")
	_check(EffectApplier.apply_effects([{"stat": "pilot.attitude", "add": -8}]) == OK and _stat("attitude") == 24, "High mood reduces attitude losses")
	_new_game()
	_check(EffectApplier.apply_effects([{"stat": "pilot.mood", "add": -30}, {"stat": "pilot.attitude", "add": 8}]) == OK and _stat("attitude") == 26, "Low mood reduces attitude gains at the boundary")
	_check(EffectApplier.apply_effects([{"stat": "pilot.attitude", "add": -8}]) == OK and _stat("attitude") == 16, "Low mood increases attitude losses")
	_new_game()
	_check(EffectApplier.apply_effects([{"stat": "pilot.mood", "add": 10}, {"stat": "pilot.attitude", "add": 3}]) == OK and is_equal_approx(_stat("attitude"), 23.75), "High mood starts at 70 and preserves fractional gains")
	_new_game()
	_check(EffectApplier.apply_effects([{"stat": "pilot.arousal", "add": 80}]) == OK and _stat("arousal") == 0, "Arousal cannot grow below the touch threshold")
	_check(EffectApplier.apply_effects([{"stat": "pilot.attitude", "add": 10}, {"stat": "pilot.arousal", "add": 999}]) == OK and _stat("arousal") == 100, "Arousal grows at the touch threshold and clamps to 100")
	_check(EffectApplier.apply_effects([{"advance_time": 2}]) == OK and _stat("arousal") == 50, "Every advanced time slot reduces arousal by 25")
	Clock.advance_slots()
	_check(_stat("arousal") == 25, "Direct clock advances use the same decay handler")
	_check(EffectApplier.apply_effects([{"stat": "pilot.mood", "add": 999}, {"stat": "pilot.attitude", "add": -999}, {"stat": "pilot.arousal", "add": -999}]) == OK, "Large stat changes are supported")
	_check(_stat("mood") == 100 and _stat("attitude") == 0 and _stat("arousal") == 0, "All stat bounds are enforced")
	_new_game()
	_check(EffectApplier.apply_effects([{"flag": "effect_check", "set": true}, {"money": 125}, {"fuel": -5}]) == OK, "Flags, money and fuel use the central applier")
	_check(Conditions.evaluate([{"flag": "effect_check", "is": true}]) and GameState.state["money"] == 1125 and GameState.state["ship"]["fuel"]["current"] == 25, "Resource effects update GameState")
	_check(EffectApplier.apply_effects([{"fuel": 999}]) == OK and GameState.state["ship"]["fuel"]["current"] == 30, "Fuel cannot exceed tank capacity")
	_check(EffectApplier.apply_effects([{"fuel": -999}]) == OK and GameState.state["ship"]["fuel"]["current"] == 0, "Fuel cannot become negative")
	var original_state: Dictionary = GameState.serialize()
	_check(EffectApplier.apply_effects([{"money": 10}, {"stat": "missing.mood", "add": 1}]) == ERR_INVALID_DATA, "Every target is checked before applying effects")
	_check(GameState.serialize() == original_state, "A failed batch cannot apply its first effects")
	_check(EffectApplier.apply_effects([{"money": 1.5}]) == ERR_INVALID_DATA, "Money remains an integer")
	_check(EffectApplier.apply_effects([{"advance_time": -1}]) == ERR_INVALID_DATA, "Effects cannot move time backwards")
	_check(EffectApplier.apply_effects([{"flag": "invalid_check", "set": true}, {"unknown_effect": "xeno_crystal"}]) == ERR_INVALID_DATA, "Unknown effect types are rejected before mutation")
	_check(GameState.serialize() == original_state, "Rejected effect schemas preserve GameState")


func _check_validation() -> void:
	var groups: Dictionary = DataLoader.records_by_group.duplicate(true)
	groups["scenes"][0]["conditions"] = [{"stat": "pilot.attitude", "op": "unknown", "value": 0}]
	_check("Invalid stat comparison" in "\n".join(Validator.validate(groups, {})), "Data validation reports invalid operators at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["scenes"][0]["choices"][0]["effects"] = [{"stat": "pilot.mood", "add": "invalid"}]
	_check("Invalid stat effect" in "\n".join(Validator.validate(groups, {})), "Data validation reports invalid effects at startup")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["scenes"][0]["choices"].append(groups["scenes"][0]["choices"][0].duplicate(true))
	_check("duplicate choice id" in "\n".join(Validator.validate(groups, {})), "Choice ids must be unique within a scene")
	groups = DataLoader.records_by_group.duplicate(true)
	groups["scenes"][0]["lines"] = [42]
	_check("lines must contain objects" in "\n".join(Validator.validate(groups, {})), "Malformed lines are rejected before rendering")


func _check_runner() -> void:
	_new_game()
	_check(Runner.is_available(DataLoader.get_record("pilot_test_01")), "The first scene starts available")
	_check(not Runner.is_available(DataLoader.get_record("pilot_test_02")) and not Runner.is_available(DataLoader.get_record("pilot_test_03")), "Follow-up scenes start locked")
	var initial_state: Dictionary = GameState.serialize()
	_check(Runner.choose("pilot_test_02", "increase") == ERR_UNAVAILABLE and GameState.serialize() == initial_state, "A locked scene cannot apply effects")
	_check(Runner.choose("pilot_test_01", "missing") == ERR_INVALID_PARAMETER and GameState.serialize() == initial_state, "Unknown choices preserve state")
	_check(Runner.choose("ship_main", "missing") == ERR_INVALID_PARAMETER, "A non-scene record cannot be played")
	_check(Runner.choose("pilot_test_01", "raise_mood") == OK, "The positive opening choice succeeds")
	_check(_stat("attitude") == 30 and _stat("mood") == 75 and _stat("arousal") == 0, "Choice changes and scene-end reset are applied")
	_check(Clock.current_slot() == "day" and GameState.state["flags"]["pilot_test_01_seen"], "On-end flags and time are applied")
	_check(not Runner.is_available(DataLoader.get_record("pilot_test_01")) and Runner.is_available(DataLoader.get_record("pilot_test_02")), "Completing a scene closes it and opens its successor")
	var completed_state: Dictionary = GameState.serialize()
	_check(Runner.choose("pilot_test_01", "raise_mood") == ERR_UNAVAILABLE and GameState.serialize() == completed_state, "A repeated choice cannot duplicate rewards")
	_check(GameState.save_game(SAVE_TEST_PATH) == OK, "Dialogue state can be saved")
	_new_game()
	_check(GameState.load_game(SAVE_TEST_PATH) == OK and _stat("attitude") == 30, "Dialogue stats restore from JSON")
	_check(Runner.is_available(DataLoader.get_record("pilot_test_02")) and not Runner.is_available(DataLoader.get_record("pilot_test_01")), "Scene gates restore from saved flags")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH)) == OK, "The dialogue verification save is removed")
	_new_game()
	var scene: Dictionary = DataLoader.records["pilot_test_01"]
	var on_end: Array = scene["on_end"]
	scene["on_end"] = [{"stat": "missing.mood", "add": 1}]
	initial_state = GameState.serialize()
	_check(Runner.choose("pilot_test_01", "raise_mood") == ERR_INVALID_DATA and GameState.serialize() == initial_state, "Choice and on-end effects are validated as a single batch")
	scene["on_end"] = on_end


func _check_view() -> void:
	_new_game()
	var packed_scene: PackedScene = load("res://scenes/dialogue.tscn")
	var view: DialogueView = packed_scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	_check(view.get_node("%SceneId").text == "pilot_test_01", "The dialogue view opens the first available scene")
	_check(view.get_node("%Choices").get_child_count() == 2, "Choices are generated from JSON")
	_check(view.get_node("%SceneList/pilot_test_02").disabled and view.get_node("%SceneList/pilot_test_03").disabled, "Locked scenes are visibly disabled")
	_check(view.get_node("%HeroineName").text == DataLoader.get_record("pilot")["name"], "The heroine label comes from JSON")
	_check(view.get_node("%Lines").get_child(1).text == DataLoader.get_record("pilot_test_01")["lines"][0]["text"], "Dialogue lines come from JSON")
	await _capture(view, "initial")
	view.get_node("%Choices/raise_mood").pressed.emit()
	_check(view.get_node("%SceneId").text == "pilot_test_02" and _stat("attitude") == 30, "A choice button applies effects and opens the next scene")
	_check("30" in view.get_node("%Stats/attitude").text and "75" in view.get_node("%Stats/mood").text, "The displayed stats refresh after the choice")
	_check(not view.select_scene("pilot_test_01"), "The view cannot reopen a closed scene")
	view.get_node("%Choices/decrease").pressed.emit()
	_check(_stat("attitude") == 27 and view.get_node("%SceneId").text == "pilot_test_03", "A loss closes the high-threshold path and opens recovery")
	view.get_node("%Choices/recover").pressed.emit()
	_check(_stat("attitude") == 52 and view.get_node("%Choices").get_child_count() == 0, "The complete positive path has no repeated choices")
	_new_game()
	view.refresh()
	view.get_node("%Choices/lower_mood").pressed.emit()
	_check(_stat("attitude") == 10 and _stat("mood") == 25, "The negative opening choice lowers both stats")
	_check(view.get_node("%SceneId").text == "pilot_test_03" and view.get_node("%SceneList/pilot_test_02").disabled, "The negative path offers recovery instead of the locked scene")
	await _capture(view, "recovery")
	view.get_node("%Choices/recover").pressed.emit()
	_check(_stat("attitude") == 30 and _stat("mood") == 60 and view.get_node("%SceneId").text == "pilot_test_02", "Recovery reopens the high-threshold scene")
	view.get_node("%Choices/increase").pressed.emit()
	_check(_stat("attitude") == 34 and _stat("mood") == 65, "The full recovery path completes correctly")
	_check(view.get_node("%Choices").get_child_count() == 0, "All completed scenes stay closed")
	view.queue_free()
	await get_tree().process_frame


func _capture(view: Control, suffix: String) -> void:
	if "--capture-dialogue" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = view.get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "The dialogue viewport can be captured")
	if image != null and not image.is_empty():
		_check(image.save_png("res://.godot/stage-two-" + suffix + ".png") == OK, "The dialogue capture is saved")


func _stat(stat_name: String) -> float:
	return float(GameState.state["heroines"]["pilot"][stat_name])


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
