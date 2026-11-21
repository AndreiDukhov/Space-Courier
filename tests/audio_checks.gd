extends Node

const Validator = preload("res://scripts/audio_validator.gd")
const Library = preload("res://scripts/audio_library.gd")
const Motion = preload("res://scripts/flight_motion.gd")
const State = preload("res://scripts/combat_state.gd")
const Math = preload("res://scripts/combat_math.gd")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")
const HubScene = preload("res://scenes/hub.tscn")

var failures: Array[String] = []
var check_count: int = 0
var heard: Array[String] = []


func _ready() -> void:
	SoundSystem.sound_started.connect(func(id: String) -> void: heard.append(id))
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	_check(DataLoader.load_errors.is_empty(), "Audio catalog loads without errors")
	_check_assets()
	_check_validation()
	await _check_mixer()
	await _check_flight()
	await _check_combat()
	await _check_doors()
	SoundSystem.clear()
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Audio checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _fresh(flying: bool = false) -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	if flying:
		EffectApplier.move_player("hub_tech")
		EffectApplier.launch_flight()
		for entry: Dictionary in GameState.state["flight"]["npcs"].values():
			entry["cooldown"] = 10000.0
	SoundSystem.clear()
	heard.clear()


func _check_assets() -> void:
	_fresh()
	var library: Library = Library.new()
	var paths: Array[String] = []
	var records: Array[Dictionary] = DataLoader.get_records("audio").filter(func(record: Dictionary) -> bool: return str(record["id"]).begins_with("sfx_"))
	for record: Dictionary in records:
		_check(Validator.validate(record).is_empty(), "Each sound has a valid catalog record")
		for path: String in record["files"]:
			if path in paths:
				continue
			paths.append(path)
			var stream: AudioStreamWAV = load(path)
			_check(stream.mix_rate == 44100 and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.get_length() > 0.05, "Each clip imports as finite mono PCM16 audio")
		var selected: AudioStreamWAV = library.pick(record["id"])
		_check((selected.loop_mode == AudioStreamWAV.LOOP_FORWARD) == bool(record["loop"]), "Only engine records loop")
		if record["loop"]:
			_check(selected.data.decode_s16(0) == selected.data.decode_s16(selected.data.size() - 2), "Engine loop endpoints match exactly")
	_check(paths.size() == 34 and records.size() == 20, "The effects pack has 34 original clips and 20 sound ids")
	seed(71243)
	var expected: int = randi()
	seed(71243)
	var previous: AudioStreamWAV = null
	for _index: int in range(12):
		var stream: AudioStreamWAV = library.pick("sfx_laser")
		_check(stream != previous, "Consecutive laser variants do not repeat")
		previous = stream
		library.pitch("sfx_laser")
	_check(randi() == expected, "Audio choices never consume gameplay randomness")
	var snapshot: Dictionary = GameState.serialize()
	_check(SoundSystem.play("missing") == null and SoundSystem.play("sfx_engine_idle") == null and GameState.serialize() == snapshot, "Invalid playback leaves game state unchanged")


func _check_validation() -> void:
	for field: String in ["files", "pitch", "volume_db", "loop", "spatial"]:
		var record: Dictionary = DataLoader.get_record("sfx_laser")
		record[field] = null
		_check(not Validator.validate(record).is_empty(), "Malformed audio fields are rejected: " + field)
	for bad: Variant in [["res://audio/missing.wav"], [], ["res://scripts/main.gd"]]:
		var record: Dictionary = DataLoader.get_record("sfx_laser")
		record["files"] = bad
		_check(not Validator.validate(record).is_empty(), "Missing and invalid audio resources are reported")


func _check_mixer() -> void:
	_fresh()
	var bus: int = AudioServer.get_bus_index("SFX")
	_check(bus >= 0 and AudioServer.get_bus_effect_count(0) > 0 and AudioServer.get_bus_effect(0, 0) is AudioEffectLimiter, "The SFX bus routes through the master limiter")
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 0.3
	AudioServer.add_bus_effect(bus, capture)
	var buffer: PackedVector2Array = PackedVector2Array()
	var peak: float = 0.0
	for _attempt: int in range(12):
		SoundSystem.play("sfx_ui_confirm")
		await get_tree().create_timer(0.12).timeout
		var frames: int = capture.get_frames_available()
		if frames > 0:
			buffer = capture.get_buffer(frames)
			for frame: Vector2 in buffer:
				peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		if peak > 0.001:
			break
	_check(buffer.size() > 0 and peak > 0.001 and peak < 0.95, "The actual mixer produces audible samples below clipping")
	print("Audio mixer: %d frames, peak %.4f" % [buffer.size(), peak])
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	AudioServer.set_bus_mute(0, true)
	SoundSystem.clear()
	for _voice: int in range(27):
		SoundSystem.play("sfx_jump_depart")
		await get_tree().create_timer(0.025).timeout
	_check(SoundSystem._voices.size() <= SoundSystem.MAX_VOICES, "One-shot polyphony stays bounded")
	SoundSystem.play_jump()
	SoundSystem.clear()
	heard.clear()
	await get_tree().create_timer(0.32).timeout
	_check(heard.is_empty() and SoundSystem._voices.is_empty(), "Reset cancels pending jump audio and active voices")


func _check_flight() -> void:
	_fresh(true)
	var view: Control = FlightScene.instantiate()
	add_child(view)
	view.set_physics_process(false)
	await _frames()
	var model: Node3D = view._player.get_node("ShipModel")
	var engines: Node3D = model.get_node("EngineAudio")
	var bus: int = AudioServer.get_bus_index("SFX")
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 0.3
	AudioServer.add_bus_effect(bus, capture)
	await get_tree().create_timer(0.24).timeout
	_check(engines._loops.values().all(func(player: AudioStreamPlayer3D) -> bool: return not player.playing), "A stationary ship has no engine hum")
	EffectApplier.set_flight_target(Motion.point(GameState.state["flight"]["pos"]) + Vector2(200, 0))
	capture.clear_buffer()
	await get_tree().create_timer(0.24).timeout
	_check(engines._loops["cruise"].playing and engines._loops["cruise"].volume_db <= -38.0, "Moving engines use the quieter catalog volume")
	var samples: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var peak: float = 0.0
	for frame: Vector2 in samples:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	_check(samples.size() > 0 and peak > 0.00001 and peak < 0.012, "The actual engine mix remains quiet even at zero listener distance")
	print("Engine mixer: %d frames, peak %.5f" % [samples.size(), peak])
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	view._on_boost(true)
	await get_tree().create_timer(0.24).timeout
	_check(engines._loops["boost"].playing and not engines._loops["cruise"].playing and engines._loops["boost"].volume_db <= -34.0 and engines._loops["boost"].max_db == engines._loops["boost"].volume_db, "Boost respects the quieter catalog volume and near-field ceiling")
	model.set_motion(false, true)
	await get_tree().create_timer(0.24).timeout
	_check(engines._loops.values().all(func(player: AudioStreamPlayer3D) -> bool: return not player.playing), "Stopping silences engines even with boost selected")
	model.set_motion(true, true)
	EffectApplier.toggle_flight_pause()
	await get_tree().create_timer(0.24).timeout
	_check(not engines._loops["boost"].playing, "Pause silences engine loops")
	EffectApplier.toggle_flight_pause()
	await _frames()
	SoundSystem.clear()
	heard.clear()
	var parent: Node3D = view.get_node("%Space")
	var point: Vector3 = view._player.position
	_check(SoundSystem.play_at("sfx_laser", point, parent) != null and SoundSystem.play_at("sfx_laser", point + Vector3(90, 0, 0), parent) == null, "Nearby space sounds play while distant ones are culled")
	var snapshot: Dictionary = GameState.serialize()
	_check(GameState.restore(snapshot) == OK, "The flight snapshot restores")
	heard.clear()
	await get_tree().create_timer(0.12).timeout
	_check(heard.is_empty() and GameState.serialize() == snapshot, "Loading does not replay one-shots or alter fuel")
	view.queue_free()
	await _frames()
	_check(SoundSystem._voices.is_empty(), "Leaving a flight scene releases its spatial voices")


func _check_combat() -> void:
	_fresh(true)
	GameState.state["combat"] = State.initial("pirate_light", "")
	var combat: Dictionary = GameState.state["combat"]
	combat["player"]["pos"] = [13, 12]
	combat["player"]["facing"] = 2
	combat["opponents"][0]["pos"] = [16, 12]
	combat["movement"]["player"] = State.new_turn(combat["player"])
	combat["movement"]["opponent"] = State.new_turn(combat["opponents"][0])
	var view: Control = CombatScene.instantiate()
	add_child(view)
	await _frames()
	var weapon: Dictionary = DataLoader.records["course_cannon"].duplicate(true)
	DataLoader.records["course_cannon"]["accuracy"] = {"close": 1.0, "far": 1.0, "hull_penalty": 0.0, "crew_mood_bonus": 0.0}
	DataLoader.records["course_cannon"]["critical"]["chance"] = 0.0
	DataLoader.records["course_cannon"]["dmg"] = [1, 1]
	heard.clear()
	var before_shot: Dictionary = GameState.serialize()
	_check(EffectApplier.shoot_combat("course_cannon", Vector2i(16, 12)) == OK, "The normal combat action fires")
	await get_tree().create_timer(0.6).timeout
	_check("sfx_autocannon" in heard and "sfx_explosion" in heard and ("sfx_shield_hit" in heard or "sfx_impact" in heard), "The resolved shot plays its weapon, hit and explosion cues")
	var snapshot: Dictionary = GameState.serialize()
	heard.clear()
	_check(GameState.restore(snapshot) == OK, "The resolved shot restores")
	await get_tree().create_timer(0.35).timeout
	_check(heard.is_empty() and GameState.serialize() == snapshot, "Loading a resolved shot never replays its audio or damage")
	_check(GameState.restore(before_shot) == OK, "The pre-shot state restores for cancellation")
	EffectApplier.shoot_combat("course_cannon", Vector2i(16, 12))
	await get_tree().create_timer(0.05).timeout
	snapshot = GameState.serialize()
	_check(GameState.restore(snapshot) == OK, "Loading during a beam cancels the current sound")
	heard.clear()
	await get_tree().create_timer(0.5).timeout
	_check(heard.is_empty() and GameState.serialize() == snapshot, "A canceled beam cannot create a late hit sound or damage")
	DataLoader.records["course_cannon"] = weapon
	view.queue_free()
	await _frames()


func _check_doors() -> void:
	_fresh()
	EffectApplier.move_player("hub_corridor")
	GameState.state["heroines"]["mechanic"]["loc"] = "hub_mechanic_bedroom"
	var hub: Control = HubScene.instantiate()
	add_child(hub)
	await _frames()
	heard.clear()
	await _click(hub.get_node("%Locations/hub_tech/Travel"))
	_check(heard.count("sfx_ui_click") == 1 and GameState.state["location"] == "hub_tech", "A real navigation click sounds once before its button is replaced")
	EffectApplier.move_player("hub_corridor")
	await _frames()
	heard.clear()
	var snapshot: Dictionary = GameState.serialize()
	await _click(hub.get_node("%Locations/hub_shop/Travel"))
	_check(heard.is_empty() and GameState.serialize() == snapshot, "A disabled room button remains silent and cannot change state")
	heard.clear()
	EffectApplier.use_bedroom_door("door_mechanic", "knock")
	_check("sfx_knock" in heard, "Knocking plays the recorded knock sequence")
	heard.clear()
	EffectApplier.use_bedroom_door("door_mechanic", "enter")
	_check("sfx_door_open" in heard, "Entering a bedroom plays its door sound")
	await get_tree().create_timer(0.03).timeout
	heard.clear()
	EffectApplier.exit_bedroom()
	_check("sfx_door_open" in heard, "The bedroom exit also plays the door")
	hub.queue_free()
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
	for _frame: int in range(3):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
