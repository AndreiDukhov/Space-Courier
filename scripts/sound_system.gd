extends Node

signal sound_started(sound_id: String)
signal reset_audio

const Library = preload("res://scripts/audio_library.gd")
const Listener = preload("res://scripts/audio_listener_follow.gd")
const Music = preload("res://scripts/music_director.gd")
const MAX_VOICES: int = 24

var library: Library = Library.new()
var _voices: Array[Node] = []
var _worlds: Dictionary = {}
var _last_played: Dictionary = {}
var _generation: int = 0
var _location: String = ""


func _ready() -> void:
	if not DataLoader.load_errors.is_empty():
		return
	GameState.restored.connect(clear)
	GameState.settings_changed.connect(apply_settings)
	EffectApplier.location_changed.connect(_on_location_changed)
	EffectApplier.bedroom_action_resolved.connect(_on_door_action)
	EffectApplier.modules_changed.connect(func() -> void: play("sfx_ui_confirm"))
	get_tree().node_added.connect(_on_node_added)
	_location = str(GameState.state.get("location", ""))
	var music: Music = Music.new()
	music.name = "MusicDirector"
	add_child(music)
	apply_settings()


func play(sound_id: String) -> AudioStreamPlayer:
	var record: Dictionary = _one_shot(sound_id)
	if record.is_empty() or record["spatial"]:
		return null
	var stream: AudioStreamWAV = library.pick(sound_id)
	if stream == null:
		return null
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = float(record["volume_db"])
	player.pitch_scale = library.pitch(sound_id)
	add_child(player)
	_track(player, sound_id)
	player.play()
	return player


func play_at(sound_id: String, point: Vector3, parent: Node3D) -> AudioStreamPlayer3D:
	if not is_instance_valid(parent) or not parent.is_inside_tree() or world_paused(parent.get_viewport()):
		return null
	var listener: AudioListener3D = listener_for(parent.get_viewport())
	if listener == null or listener.global_position.distance_to(parent.to_global(point)) > 60.0:
		return null
	var record: Dictionary = _one_shot(sound_id)
	if record.is_empty() or not record["spatial"]:
		return null
	var player: AudioStreamPlayer3D = _spatial_player(sound_id)
	if player == null:
		return null
	var root: Node3D = _worlds[parent.get_viewport().get_instance_id()]["root"].get_ref()
	player.position = root.to_local(parent.to_global(point))
	root.add_child(player)
	_track(player, sound_id)
	player.play()
	return player


func create_loop(sound_id: String, parent: Node3D) -> AudioStreamPlayer3D:
	var record: Dictionary = DataLoader.get_record(sound_id)
	if not record.get("loop", false) or not record.get("spatial", false):
		return null
	var player: AudioStreamPlayer3D = _spatial_player(sound_id)
	if player != null:
		parent.add_child(player)
	return player


func _spatial_player(sound_id: String) -> AudioStreamPlayer3D:
	var stream: AudioStreamWAV = library.pick(sound_id)
	if stream == null:
		return null
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = float(DataLoader.get_record(sound_id)["volume_db"])
	player.max_db = player.volume_db
	player.pitch_scale = library.pitch(sound_id)
	player.unit_size = 12.0
	player.max_distance = 60.0
	player.panning_strength = 0.7
	return player


func apply_settings() -> void:
	var settings: Dictionary = GameState.state.get("settings", {"effects_volume": 1.0, "music_volume": 1.0})
	for field: String in ["effects_volume", "music_volume"]:
		var bus: int = AudioServer.get_bus_index("SFX" if field == "effects_volume" else "Music")
		if bus >= 0:
			var volume: float = float(settings[field])
			AudioServer.set_bus_mute(bus, volume <= 0.0)
			AudioServer.set_bus_volume_db(bus, linear_to_db(volume) if volume > 0.0 else -80.0)


func _one_shot(sound_id: String) -> Dictionary:
	if not DataLoader.record_sources.has("audio/" + sound_id):
		return {}
	var record: Dictionary = DataLoader.get_record(sound_id)
	var now: int = Time.get_ticks_msec()
	if record["loop"] or now - int(_last_played.get(sound_id, -1000)) < (700 if sound_id == "sfx_heat" else 20):
		return {}
	_last_played[sound_id] = now
	return record


func _track(player: Node, sound_id: String) -> void:
	_voices = _voices.filter(func(voice: Node) -> bool: return is_instance_valid(voice))
	while _voices.size() >= MAX_VOICES:
		var oldest: Node = _voices.pop_front()
		oldest.stop()
		oldest.queue_free()
	_voices.append(player)
	player.finished.connect(_release.bind(player))
	player.tree_exiting.connect(func() -> void: _voices.erase(player))
	sound_started.emit(sound_id)


func _release(player: Node) -> void:
	_voices.erase(player)
	if is_instance_valid(player):
		player.queue_free()


func attach_listener(viewport: SubViewport, anchor: Node3D) -> void:
	viewport.audio_listener_enable_3d = true
	var listener: Listener = Listener.new()
	listener.name = "SoundListener"
	anchor.add_child(listener)
	var id: int = viewport.get_instance_id()
	var root: Node3D = Node3D.new()
	root.name = "SoundEffects"
	viewport.add_child(root)
	_worlds[id] = {"listener": weakref(listener), "root": weakref(root), "paused": false}
	viewport.tree_exiting.connect(func() -> void: _worlds.erase(id))


func listener_for(viewport: Viewport) -> AudioListener3D:
	var reference: WeakRef = _worlds.get(viewport.get_instance_id(), {}).get("listener")
	return reference.get_ref() as AudioListener3D if reference != null else null


func world_paused(viewport: Viewport) -> bool:
	return bool(_worlds.get(viewport.get_instance_id(), {}).get("paused", false))


func pause_world(viewport: Viewport, paused: bool) -> void:
	var entry: Dictionary = _worlds.get(viewport.get_instance_id(), {})
	if entry.is_empty() or entry["paused"] == paused:
		return
	entry["paused"] = paused
	for voice: Node in _voices:
		if is_instance_valid(voice) and voice is AudioStreamPlayer3D and voice.get_viewport() == viewport:
			voice.stream_paused = paused


func play_jump() -> void:
	var generation: int = _generation
	play("sfx_jump_depart")
	await get_tree().create_timer(0.28).timeout
	if generation == _generation:
		play("sfx_jump_arrive")


func clear() -> void:
	_generation += 1
	for voice: Node in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_voices.clear()
	_last_played.clear()
	_location = str(GameState.state.get("location", ""))
	reset_audio.emit()


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("sound_bound"):
		node.set_meta("sound_bound", true)
		node.button_down.connect(_button_pressed.bind(node))


func _button_pressed(button: BaseButton) -> void:
	if button.is_visible_in_tree() and not button.disabled:
		play("sfx_ui_cancel" if button.name in [&"Close", &"CloseDialogue", &"CloseTerminal"] else "sfx_ui_click")


func _on_location_changed(location: String) -> void:
	var bedrooms: Array = DataLoader.get_record("hub_corridor_doors").get("doors", []).map(func(door: Dictionary) -> String: return str(door["location"]))
	if location != _location and (location in bedrooms or _location in bedrooms):
		play("sfx_door_open")
	_location = location


func _on_door_action(_door: String, action: String, _scene: String) -> void:
	if action == "knock":
		play("sfx_knock")
