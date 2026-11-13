extends Control

@onready var status_indicator: ColorRect = %StatusIndicator


func _ready() -> void:
	if not DataLoader.load_errors.is_empty():
		status_indicator.color = Color(0.8, 0.15, 0.15)
		return

	var heroines: Array[Dictionary] = DataLoader.get_records("heroines")
	var ship_record: Dictionary = DataLoader.get_record("ship_main")
	GameState.start_new_game(heroines, ship_record)
	status_indicator.color = Color(0.2, 0.8, 0.6)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/hub.tscn")
