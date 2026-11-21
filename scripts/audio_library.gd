extends RefCounted

var _streams: Dictionary = {}
var _last: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 59231


func pick(sound_id: String) -> AudioStreamWAV:
	var record: Dictionary = DataLoader.get_record(sound_id)
	if not DataLoader.record_sources.has("audio/" + sound_id) or record.get("files", []).is_empty():
		return null
	var paths: Array = record["files"]
	var index: int = 0
	if paths.size() > 1:
		index = (int(_last[sound_id]) + _rng.randi_range(1, paths.size() - 1)) % paths.size() if _last.has(sound_id) else _rng.randi_range(0, paths.size() - 1)
	_last[sound_id] = index
	var path: String = str(paths[index])
	var key: String = path + str(record["loop"])
	if not _streams.has(key):
		var source: AudioStreamWAV = load(path) as AudioStreamWAV
		if source == null:
			return null
		var stream: AudioStreamWAV = source.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if record["loop"] else AudioStreamWAV.LOOP_DISABLED
		stream.loop_begin = 0
		stream.loop_end = roundi(source.get_length() * source.mix_rate)
		_streams[key] = stream
	return _streams[key]


func pitch(sound_id: String) -> float:
	var range: Array = DataLoader.get_record(sound_id).get("pitch", [1.0, 1.0])
	return _rng.randf_range(float(range[0]), float(range[1]))
