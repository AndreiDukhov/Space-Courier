extends Node

const LoaderScript = preload("res://scripts/data_loader.gd")
const Validator = preload("res://scripts/data_validator.gd")
const SAVE_TEST_PATH: String = "res://.godot/stage-one-save-test.json"

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Project JSON loads without errors")
	_check(DataLoader.get_record("ship_main").get("id") == "ship_main", "Ship record is indexed")
	_check(Validator.validate(DataLoader.records_by_group, DataLoader.record_sources).is_empty(), "Project references resolve")
	_check_loader()
	_check_references()
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_check_clock()
	_check_persistence()
	_check_save_contract()
	if "--probe-user-save" in OS.get_cmdline_user_args():
		_probe_user_save()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Stage 1 checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_loader() -> void:
	var loader: LoaderScript = LoaderScript.new()
	loader._register_payload([
		{"id": "pilot_hug_01", "choices": [{"id": "stay"}]},
		{"id": "pilot_kiss_01", "choices": [{"id": "stay"}]}
	], "scenes", "fixture.json")
	_check(loader.records.size() == 2, "Choice ids stay local to their scenes")
	_check(loader.load_errors.is_empty(), "Repeated local choice ids are valid")
	loader._register_payload({"id": "pilot_hug_01"}, "scenes", "duplicate.json")
	loader._register_payload({"name": ""}, "scenes", "missing-id.json")
	loader._register_payload(42, "scenes", "scalar.json")
	_check(loader.load_errors.size() == 3, "Loader collects duplicate, missing-id and root-type errors")
	var fixture_path: String = "res://.godot/stage-one-invalid-data.json"
	var fixture_file: FileAccess = FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture_file.store_string("{")
	fixture_file.close()
	loader._load_file(fixture_path)
	_check(loader.load_errors.size() == 4 and "Invalid JSON" in loader.load_errors.back(), "Malformed data JSON is added to the error list")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK, "Malformed fixture is removed")
	loader.free()
	var ship_copy: Dictionary = DataLoader.get_record("ship_main")
	ship_copy["hull"]["current"] = -1
	_check(DataLoader.get_record("ship_main")["hull"]["current"] >= 0, "Records returned to callers are isolated copies")


func _check_references() -> void:
	var groups: Dictionary = {
		"heroines": [{"id": "pilot", "age": 21, "schedule": "pilot", "abilities": ["evasive_maneuver"]}],
		"schedules": [{"heroine": "pilot", "slots": {
			"morning": [{"loc": "ship_bridge", "weight": 1}],
			"day": [{"loc": "ship_bridge", "weight": 1}],
			"evening": [{"loc": "ship_bridge", "weight": 1}],
			"night": [{"loc": "ship_bridge", "weight": 1}]
		}}],
		"abilities": [DataLoader.get_record("evasive_maneuver")],
		"locations": [{"id": "ship_bridge", "connects": []}],
		"scenes": [{"id": "pilot_hug_01", "location": "ship_bridge", "lines": [{"who": "hero"}, {"who": "pilot"}], "conditions": [{"stat": "pilot.attitude", "op": ">=", "value": 0}]}]
	}
	_check(Validator.validate(groups, {}).is_empty(), "Schedules, speakers, abilities and stat references resolve")
	groups["heroines"][0]["age"] = 20
	groups["heroines"][0]["abilities"] = ["missing_ability"]
	groups["scenes"][0]["location"] = "missing_location"
	var errors: Array[String] = Validator.validate(groups, {})
	_check(errors.size() == 3, "Validator reports every invalid age and reference")
	_check("missing_ability" in "\n".join(errors), "Reference errors identify missing ids")
	groups["heroines"][0]["age"] = 21.5
	_check(Validator.validate(groups, {}).size() == 3, "Fractional ages are rejected")
	groups["heroines"][0].erase("age")
	_check(Validator.validate(groups, {}).size() == 3, "Missing ages are rejected")


func _check_clock() -> void:
	Clock.advance_slots(3)
	_check(Clock.current_day() == 1 and Clock.current_slot() == "night", "Three slots reach night")
	var observer: Callable = func(observed_day: int) -> void:
		_check(observed_day == Clock.current_day() and Clock.current_slot() == "morning", "Day signal observes the committed morning state")
	Clock.day_changed.connect(observer)
	Clock.advance_slots()
	Clock.day_changed.disconnect(observer)
	_check(Clock.current_day() == 2 and Clock.current_slot() == "morning", "Midnight advances the day")
	Clock.advance_slots(8)
	_check(Clock.current_day() == 4 and Clock.current_slot() == "morning", "Multiple days advance correctly")
	Clock.advance_slots(-1)
	_check(Clock.current_day() == 4 and Clock.current_slot() == "morning", "Negative advances do nothing")


func _check_persistence() -> void:
	_check(GameState.SAVE_PATH == "user://save.json", "Production saves use the required user path")
	var expected_fields: Array[String] = ["day", "time_slot", "money", "flags", "known_routes", "heroines", "ship", "location", "reputation", "orders", "current_system", "systems", "public_routes", "flight", "combat", "inventory", "known_recipes", "cooking_skill", "buffs", "served_days", "kitchen", "meal_invites", "pending_scenes"]
	_check(GameState.serialize().size() == expected_fields.size() and GameState.serialize().has_all(expected_fields), "Only the agreed state fields are serialized")
	GameState.state["flags"]["stage_one_check"] = true
	var snapshot: Dictionary = GameState.serialize()
	snapshot["flags"]["stage_one_check"] = false
	_check(GameState.state["flags"]["stage_one_check"], "Serialization does not expose mutable state")
	_check(GameState.save_game(SAVE_TEST_PATH) == OK, "State can be serialized to a JSON file")
	GameState.state["day"] = 99
	GameState.state["flags"].clear()
	_check(GameState.load_game(SAVE_TEST_PATH) == OK, "Saved JSON can be restored")
	_check(Clock.current_day() == 4 and GameState.state["flags"]["stage_one_check"], "Persistence restores nested state and time")
	var original_state: Dictionary = GameState.serialize()
	var saved_text: String = FileAccess.get_file_as_string(SAVE_TEST_PATH)
	GameState.state["day"] = 0
	_check(GameState.save_game(SAVE_TEST_PATH) == ERR_INVALID_DATA, "Invalid running state cannot overwrite a save")
	_check(FileAccess.get_file_as_string(SAVE_TEST_PATH) == saved_text, "A rejected save preserves the existing file")
	_check(GameState.restore(original_state) == OK, "A valid snapshot restores successfully")
	_check(GameState.state["day"] is int and GameState.state["money"] is int, "JSON numbers are restored as typed integers")
	var file: FileAccess = FileAccess.open(SAVE_TEST_PATH, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	_check(GameState.load_game(SAVE_TEST_PATH) != OK, "Corrupt JSON is rejected")
	_check(GameState.serialize() == original_state, "A failed load preserves the running state")
	file = FileAccess.open(SAVE_TEST_PATH, FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	_check(GameState.load_game(SAVE_TEST_PATH) == ERR_INVALID_DATA, "Non-object saves are rejected")
	file = FileAccess.open(SAVE_TEST_PATH, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	_check(GameState.load_game(SAVE_TEST_PATH) == ERR_INVALID_DATA, "Incomplete JSON objects are rejected")
	_check(GameState.serialize() == original_state, "A structurally invalid save preserves running state")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH)) == OK, "Temporary verification data is removed")


func _check_save_contract() -> void:
	var original_state: Dictionary = GameState.serialize()
	var invalid_state: Dictionary = original_state.duplicate(true)
	invalid_state.erase("flags")
	_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Missing required fields are rejected")
	invalid_state = original_state.duplicate(true)
	invalid_state["inventory"] = {}
	_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Unapproved top-level fields are rejected")
	for invalid_day: Variant in [0, 1.5, "1"]:
		invalid_state = original_state.duplicate(true)
		invalid_state["day"] = invalid_day
		_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Invalid day values are rejected")
	invalid_state = original_state.duplicate(true)
	invalid_state["time_slot"] = "invalid"
	_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Unknown time slots are rejected")
	invalid_state = original_state.duplicate(true)
	invalid_state["money"] = "1000"
	_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Money must be an integer")
	invalid_state = original_state.duplicate(true)
	invalid_state["flags"] = {"stage_one_check": 1}
	_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Flags must have boolean values")
	invalid_state = original_state.duplicate(true)
	invalid_state["known_routes"] = [7]
	_check(GameState.restore(invalid_state) == ERR_INVALID_DATA, "Route ids must be strings")
	_check(GameState.serialize() == original_state, "Rejected snapshots preserve running state")


func _probe_user_save() -> void:
	if FileAccess.file_exists(GameState.SAVE_PATH):
		print("User save probe: skipped because an existing save.json must be preserved")
		return
	print("User save probe path: " + ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var save_error: Error = GameState.save_game()
	if save_error != OK:
		print("User save probe: save.json is not writable (error %d)" % save_error)
		return
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "The actual user://save.json file is created")
	_check(GameState.load_game() == OK, "The actual user://save.json file can be loaded")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH)) == OK, "The probe save is removed")
	print("User save probe: actual user://save.json verified")


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
