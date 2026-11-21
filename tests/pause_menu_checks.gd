extends Node

const HubScene = preload("res://scenes/hub.tscn")
const FlightScene = preload("res://scenes/system_flight.tscn")
const CombatScene = preload("res://scenes/combat.tscn")
const Motion = preload("res://scripts/flight_motion.gd")
const State = preload("res://scripts/combat_state.gd")

var failures: Array[String] = []
var check_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	_check(DataLoader.load_errors.is_empty(), "Pause menu data loads without errors")
	await _check_hub()
	_check_settings_validation()
	await _check_flight()
	await _check_combat()
	PauseMenu.close()
	get_tree().paused = false
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Pause menu checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _fresh() -> void:
	PauseMenu.close()
	get_tree().paused = false
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	_check(GameState.state["settings"] == {"effects_volume": 1.0, "music_volume": 1.0}, "New games start with the approved volume defaults")


func _check_hub() -> void:
	_fresh()
	var hub: Control = HubScene.instantiate()
	hub.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hub)
	await _frames()
	var snapshot: Dictionary = GameState.serialize()
	await _key(KEY_ESCAPE)
	_check(PauseMenu.is_open() and get_tree().paused and GameState.serialize() == snapshot, "Escape opens a non-mutating pause menu in the hub")
	await _capture("main")
	await _click(PauseMenu.view.main.get_node("Settings"))
	_check(PauseMenu.view.settings.visible and not PauseMenu.view.main.visible, "The settings button opens the two volume controls")
	var effects: HSlider = PauseMenu.view.sliders["effects_volume"]
	var music: HSlider = PauseMenu.view.sliders["music_volume"]
	await _click_at(effects.get_global_rect().position + Vector2(effects.size.x * 0.35, effects.size.y * 0.5))
	_check(GameState.state["settings"]["effects_volume"] > 0.2 and GameState.state["settings"]["effects_volume"] < 0.5, "A real slider click updates the effects volume")
	effects.value = 35
	music.value = 22
	var sfx_bus: int = AudioServer.get_bus_index("SFX")
	var music_bus: int = AudioServer.get_bus_index("Music")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.35)) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.22)), "Each slider changes its own live bus gain")
	effects.value = 0
	_check(AudioServer.is_bus_mute(sfx_bus) and not AudioServer.is_bus_mute(music_bus), "Zero effects volume mutes only effects")
	effects.value = 35
	music.value = 0
	_check(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus), "Zero music volume mutes only music")
	music.value = 22
	await _wait(0.25)
	var director: Node = SoundSystem.get_node("MusicDirector")
	var player: AudioStreamPlayer = director._players["music_hub"]
	var before: float = player.get_playback_position()
	await _wait(0.25)
	_check(player.playing and player.get_playback_position() > before, "Music continues while gameplay is paused in settings")
	await _capture("settings")
	await _key(KEY_ESCAPE)
	_check(PauseMenu.is_open() and PauseMenu.view.main.visible and get_tree().paused, "Escape from settings returns to the main pause menu")
	await _click(PauseMenu.view.main.get_node("Save"))
	_check(FileAccess.file_exists(GameState.SAVE_PATH) and PauseMenu.is_open(), "The pause menu saves to the normal save path and stays open")
	snapshot = GameState.serialize()
	await _key(KEY_ESCAPE)
	_check(not PauseMenu.is_open() and not get_tree().paused, "Escape closes the pause menu and resumes the hub")
	GameState.state["money"] += 10
	EffectApplier.set_audio_volume("effects_volume", 0.9)
	_check(GameState.load_game() == OK and GameState.serialize() == snapshot, "The menu's save restores game state and both volumes")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), linear_to_db(0.35)), "Loading reapplies the saved volume to the mixer")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("settings")
	_check(GameState.restore(legacy) == OK and GameState.state["settings"] == {"effects_volume": 1.0, "music_volume": 1.0}, "A previous save gains default settings")
	var upgraded: Dictionary = GameState.serialize()
	upgraded.erase("settings")
	_check(upgraded == legacy, "The settings migration preserves all existing game progress")
	_check(hub.open_domestic("kitchen"), "The real kitchen opens for Escape priority")
	await _frames()
	await _key(KEY_ESCAPE)
	_check(hub.find_child("Domestic", true, false) == null and not PauseMenu.is_open(), "Escape closes an existing minigame before opening the game menu")
	hub.queue_free()
	await _frames()


func _check_settings_validation() -> void:
	var snapshot: Dictionary = GameState.serialize()
	for value: Variant in [-0.1, 1.1, INF, NAN, "quiet", null]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid["settings"]["effects_volume"] = value
		_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == snapshot, "Malformed saved volumes cannot replace running state")
	var partial: Dictionary = snapshot.duplicate(true)
	partial["settings"].erase("music_volume")
	_check(GameState.restore(partial) == ERR_INVALID_DATA, "A partial settings object is rejected")
	_check(EffectApplier.set_audio_volume("master", 0.5) != OK and EffectApplier.set_audio_volume("effects_volume", -1.0) != OK and GameState.serialize() == snapshot, "Unknown channels and invalid volume actions are rejected centrally")


func _check_flight() -> void:
	_fresh()
	EffectApplier.move_player("hub_tech")
	EffectApplier.launch_flight()
	for entry: Dictionary in GameState.state["flight"]["npcs"].values():
		entry["cooldown"] = 10000.0
	var flight: Control = FlightScene.instantiate()
	flight.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(flight)
	await _frames()
	EffectApplier.set_flight_target(Motion.point(GameState.state["flight"]["pos"]) + Vector2(300, 0))
	flight._following_mouse = true
	await _key(KEY_ESCAPE)
	var snapshot: Dictionary = GameState.serialize()
	await _wait(0.3)
	_check(get_tree().paused and GameState.serialize() == snapshot and not flight._following_mouse, "The menu freezes flight and clears held mouse steering")
	await _key(KEY_ESCAPE)
	await _wait(0.08)
	_check(not get_tree().paused and GameState.state["flight"]["pos"] != snapshot["flight"]["pos"], "Closing the menu resumes actual movement")
	EffectApplier.toggle_flight_pause()
	await _key(KEY_ESCAPE)
	await _click(PauseMenu.view.main.get_node("Resume"))
	_check(not get_tree().paused and GameState.state["flight"]["paused"], "Continuing preserves a pre-existing manual flight pause")
	get_tree().paused = true
	PauseMenu.open()
	PauseMenu.close()
	_check(get_tree().paused, "The menu also preserves an existing global pause")
	get_tree().paused = false
	flight.queue_free()
	await _frames()


func _check_combat() -> void:
	GameState.state["combat"] = State.initial("pirate_light", "")
	var combat: Control = CombatScene.instantiate()
	combat.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(combat)
	await _frames()
	await _key(KEY_ESCAPE)
	_check(PauseMenu.is_open() and get_tree().paused, "The same menu opens over tactical combat")
	var snapshot: Dictionary = GameState.serialize()
	await _click(PauseMenu.view.main.get_node("Save"))
	_check(GameState.load_game() == OK and GameState.serialize() == snapshot, "Saving and loading from the menu also works in combat")
	await _key(KEY_ESCAPE)
	_check(not PauseMenu.is_open() and not get_tree().paused, "Combat resumes without losing the turn")
	combat.queue_free()
	await _frames()


func _capture(suffix: String) -> void:
	if "--capture-pause-menu" in OS.get_cmdline_user_args():
		if "--small" in OS.get_cmdline_user_args():
			suffix += "-small"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/pause-menu-" + suffix + ".png")


func _key(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames()


func _click(button: Button) -> void:
	await _click_at(button.get_global_rect().get_center())


func _click_at(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_viewport().push_input(event, true)
	await _frames()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames() -> void:
	for _frame: int in range(3):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
