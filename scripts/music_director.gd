extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const FADE_SECONDS: float = 1.8
const POLL_SECONDS: float = 0.15

var current_track: String = ""
var _players: Dictionary = {}
var _mix: Dictionary = {}
var _volumes: Dictionary = {}
var _clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.restored.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var selected: String = Conditions.music_track()
	if selected == current_track:
		return
	current_track = selected
	if selected.is_empty() or _players.has(selected):
		return
	var record: Dictionary = DataLoader.get_record(selected)
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = selected
	player.stream = SoundSystem.library.pick(selected)
	player.bus = &"Music"
	player.pitch_scale = SoundSystem.library.pitch(selected)
	player.volume_db = -80.0
	_volumes[selected] = float(record["volume_db"])
	_mix[selected] = 0.0
	_players[selected] = player
	add_child(player)


func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = POLL_SECONDS
		_refresh()
	for id: String in _players:
		var player: AudioStreamPlayer = _players[id]
		_mix[id] = move_toward(float(_mix[id]), 1.0 if id == current_track else 0.0, delta / FADE_SECONDS)
		if _mix[id] > 0.001:
			player.volume_db = float(_volumes[id]) + linear_to_db(float(_mix[id]))
			if not player.playing:
				player.play()
		else:
			player.stop()
