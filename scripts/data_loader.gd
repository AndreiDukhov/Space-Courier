extends Node

const Validator = preload("res://scripts/data_validator.gd")

var records: Dictionary = {}
var records_by_group: Dictionary = {}
var files: Dictionary = {}
var load_errors: Array[String] = []
var record_sources: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> bool:
	records.clear()
	records_by_group.clear()
	files.clear()
	load_errors.clear()
	record_sources.clear()
	_scan_directory("res://data")
	if not record_sources.has("ship/ship_main"):
		load_errors.append("Missing required ship id 'ship_main' in data/ship/ship.json")
	if not record_sources.has("locations/" + GameState.INITIAL_LOCATION):
		load_errors.append("Missing initial hub location: " + GameState.INITIAL_LOCATION)
	load_errors.append_array(Validator.validate(records_by_group, record_sources))
	if load_errors.is_empty():
		print("DataLoader: loaded %d records from %d files" % [records.size(), files.size()])
	else:
		for message: String in load_errors:
			push_error("DataLoader: " + message)
	return load_errors.is_empty()


func get_record(record_id: String) -> Dictionary:
	var record: Variant = records.get(record_id, {})
	if record is Dictionary:
		return record.duplicate(true)
	return {}


func get_records(group: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records_by_group.get(group, []):
		result.append(record.duplicate(true))
	return result


func get_schedule(schedule_id: String) -> Dictionary:
	for schedule: Dictionary in records_by_group.get("schedules", []):
		if schedule.get("heroine") == schedule_id:
			return schedule.duplicate(true)
	return {}


func _scan_directory(directory_path: String) -> void:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		load_errors.append("Could not open directory: %s" % directory_path)
		return

	var directories: PackedStringArray = directory.get_directories()
	directories.sort()
	for entry_name: String in directories:
		if not entry_name.begins_with("."):
			_scan_directory(directory_path.path_join(entry_name))
	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if file_name.get_extension().to_lower() == "json":
			_load_file(directory_path.path_join(file_name))


func _load_file(file_path: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		load_errors.append("Could not read file: %s" % file_path)
		return

	var parser: JSON = JSON.new()
	var parse_result: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		load_errors.append("Invalid JSON in %s at line %d: %s" % [file_path, parser.get_error_line(), parser.get_error_message()])
		return

	files[file_path] = parser.data
	var group: String = _group_for_file(file_path)
	_register_payload(parser.data, group, file_path)


func _group_for_file(file_path: String) -> String:
	var directory: String = file_path.trim_prefix("res://data/").get_slice("/", 0)
	var file_name: String = file_path.get_file().get_basename()
	if directory == "locations":
		return "schedules" if file_name == "schedules" else "locations"
	if directory in ["galaxy", "ship", "combat"]:
		return file_name
	return directory


func _register_payload(payload: Variant, group: String, source_path: String) -> void:
	if payload is Dictionary:
		_register_record(payload, group, source_path)
	elif payload is Array:
		for entry: Variant in payload:
			if entry is Dictionary:
				_register_record(entry, group, source_path)
			else:
				load_errors.append("Expected an object in %s" % source_path)
	else:
		load_errors.append("Expected an object or an array of objects in %s" % source_path)


func _register_record(record: Dictionary, group: String, source_path: String) -> void:
	var id_field: String = "heroine" if group == "schedules" else "id"
	var raw_id: Variant = record.get(id_field)
	if not raw_id is String or str(raw_id).strip_edges().is_empty():
		load_errors.append("Missing or invalid '%s' in %s" % [id_field, source_path])
		return

	var record_id: String = raw_id
	var source_key: String = "%s/%s" % [group, record_id]
	if record_sources.has(source_key) or (group != "schedules" and records.has(record_id)):
		load_errors.append("Duplicate record id '%s' in %s" % [record_id, source_path])
		return

	var stored_record: Dictionary = record.duplicate(true)
	if group != "schedules":
		records[record_id] = stored_record
	record_sources[source_key] = source_path
	if not records_by_group.has(group):
		records_by_group[group] = []
	records_by_group[group].append(stored_record)
