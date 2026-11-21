extends AudioListener3D


func _ready() -> void:
	top_level = true
	_process(0.0)
	make_current()


func _process(_delta: float) -> void:
	global_position = get_parent().global_position
	global_rotation = Vector3.ZERO
