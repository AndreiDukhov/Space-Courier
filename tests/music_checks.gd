extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const State = preload("res://scripts/combat_state.gd")
const Validator = preload("res://scripts/audio_validator.gd")
const Library = preload("res://scripts/audio_library.gd")

var failures: Array[String] = []
var check_count: int = 0
var _director: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	_check(DataLoader.load_errors.is_empty(), "Music catalog and required ids load")
	_director = SoundSystem.get_node("MusicDirector")
	_check_assets()
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	var hub_snapshot: Dictionary = GameState.serialize()
	await _check_hub()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	await _wait(0.25)
	_check(_director.current_track == "music_space", "Launching selects calm space music")
	_check(_director._players["music_hub"].playing and _director._players["music_space"].playing, "New music overlaps the fading old track")
	await _wait(1.9)
	_check(not _director._players["music_hub"].playing, "The old track stops after the fade")
	await _check_pursuit()
	GameState.state["combat"] = State.initial("pirate_light", "")
	await _wait(0.25)
	_check(_director.current_track == "music_danger", "Tactical combat selects active music")
	GameState.state["combat"] = {}
	await _wait(0.25)
	_check(_director.current_track == "music_space", "Leaving combat restores calm space music")
	_check(GameState.restore(hub_snapshot) == OK, "A hub save restores")
	_check(_director.current_track == "music_hub", "Loading selects the saved location's music immediately")
	await _wait(1.9)
	_check(_director._players.size() == 3 and _director._players.values().filter(func(player: AudioStreamPlayer) -> bool: return player.playing).size() == 1, "Repeated transitions retain only three players and one settled track")
	var snapshot: Dictionary = GameState.serialize()
	await _wait(0.3)
	_check(GameState.serialize() == snapshot, "Music has no gameplay or save-state effects")
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Music checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_assets() -> void:
	var library: Library = Library.new()
	for id: String in ["music_hub", "music_space", "music_danger"]:
		var record: Dictionary = DataLoader.get_record(id)
		_check(Validator.validate(record).is_empty() and record["loop"] and not record["spatial"] and record["volume_db"] <= -24.0, "Music uses the approved quiet non-spatial loop format: " + id)
		var stream: AudioStreamWAV = library.pick(id)
		_check(stream != null and stream.stereo and stream.mix_rate == 44100 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.get_length() > 15.0, "Original stereo PCM music is imported: " + id)
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == roundi(stream.get_length() * stream.mix_rate), "Music loops over the complete composition: " + id)
		_check(stream.data.decode_s16(0) == stream.data.decode_s16(stream.data.size() - 4) and stream.data.decode_s16(2) == stream.data.decode_s16(stream.data.size() - 2), "Both channels have matching loop seams: " + id)


func _check_hub() -> void:
	var bus: int = AudioServer.get_bus_index("Music")
	_check(bus >= 0 and AudioServer.get_bus_send(bus) == &"Master", "Music has a separate bus feeding Master")
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 0.3
	AudioServer.add_bus_effect(bus, capture)
	await _wait(2.1)
	_check(_director.current_track == "music_hub" and _director._players["music_hub"].playing, "The hub plays its calm music")
	var peak: float = 0.0
	var count: int = 0
	for _attempt: int in range(8):
		var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		count += frames.size()
		for frame: Vector2 in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		if peak > 0.0001:
			break
		await _wait(0.12)
	_check(count > 0 and peak > 0.0001 and peak < 0.08, "The real music mixer outputs quiet audio below clipping")
	print("Music mixer: %d frames, peak %.4f" % [count, peak])
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	var player: AudioStreamPlayer = _director._players["music_hub"]
	var before: float = player.get_playback_position()
	EffectApplier.move_player("hub_corridor")
	await _wait(0.3)
	_check(player.get_playback_position() > before and _director.current_track == "music_hub", "Changing hub rooms does not restart the music")
	player.seek(player.stream.get_length() - 0.1)
	await _wait(0.45)
	_check(player.playing and player.get_playback_position() < 1.0, "The real player wraps the complete music loop without stopping")


func _check_pursuit() -> void:
	var pirate: Dictionary = {}
	var remote: Dictionary = {}
	for npc: Dictionary in DataLoader.get_records("npcs"):
		if npc["role"] == "pirate":
			if npc["system"] == GameState.state["current_system"]:
				pirate = npc
			else:
				remote = npc
	var entry: Dictionary = GameState.state["flight"]["npcs"][pirate["id"]]
	entry["status"] = "chase"
	entry["target"] = "another_npc"
	_check(Conditions.music_track() == "music_space", "A pirate chasing another NPC does not trigger danger music")
	entry["target"] = "player"
	await _wait(0.25)
	_check(_director.current_track == "music_danger", "A local pirate pursuing the player triggers active music")
	GameState.state["flight"]["paused"] = true
	GameState.state["flight"]["encounter"] = str(pirate["event"])
	_check(Conditions.music_track() == "music_danger", "The threat music continues during the interception dialog")
	GameState.state["flight"]["encounter"] = ""
	entry["status"] = "cruise"
	entry["target"] = ""
	var other: Dictionary = GameState.state["flight"]["npcs"][remote["id"]]
	other["status"] = "chase"
	other["target"] = "player"
	_check(Conditions.music_track() == "music_space", "A stale pursuit in a different system is ignored")
	other["status"] = "cruise"
	other["target"] = ""
	await _wait(0.25)
	_check(_director.current_track == "music_space", "Escaping restores calm space music")
	EffectApplier.visit_ship()
	await _wait(0.25)
	_check(_director.current_track == "music_space", "The ship interior keeps the space ambience")
	EffectApplier.leave_ship()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
