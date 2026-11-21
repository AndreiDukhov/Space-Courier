extends Node3D

var _loops: Dictionary = {}
var _mix: Dictionary = {"cruise": 0.0, "boost": 0.0}
var _volumes: Dictionary = {}


func _ready() -> void:
	for mode: String in _mix:
		_loops[mode] = SoundSystem.create_loop("sfx_engine_" + mode, self)
		_volumes[mode] = float(DataLoader.get_record("sfx_engine_" + mode)["volume_db"])
	SoundSystem.reset_audio.connect(stop)


func stop() -> void:
	for mode: String in _loops:
		_loops[mode].stop()
		_mix[mode] = 0.0


func _process(delta: float) -> void:
	var model: Node3D = get_parent()
	var listener: AudioListener3D = SoundSystem.listener_for(get_viewport())
	var enabled: bool = model.animation_enabled and model.is_visible_in_tree() and listener != null and not SoundSystem.world_paused(get_viewport())
	if enabled:
		enabled = listener.global_position.distance_to(global_position) < 32.0
	var selected: String = ("boost" if model._boost else "cruise") if enabled and model._requested_throttle > 0.0 else ""
	for mode: String in _loops:
		var player: AudioStreamPlayer3D = _loops[mode]
		var target: float = 1.0 if mode == selected else 0.0
		_mix[mode] = move_toward(float(_mix[mode]), target, delta * 5.0)
		if _mix[mode] > 0.001:
			player.volume_db = float(_volumes[mode]) + linear_to_db(float(_mix[mode]))
			player.max_db = player.volume_db
			if not player.playing:
				player.play()
		else:
			player.stop()
