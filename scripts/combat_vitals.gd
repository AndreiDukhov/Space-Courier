extends Control

const Math = preload("res://scripts/combat_math.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var camera: Camera3D
var board: Node3D
var _rows: Dictionary = {}
var _hull: Dictionary = {}
var _shield: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for actor: String in ["player", "opponent"]:
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "PlayerVitals" if actor == "player" else "EnemyVitals"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(112, 32)
		row.add_theme_constant_override("separation", 3)
		add_child(row)
		_rows[actor] = row
		_hull[actor] = _bar(row, "Hull", Color(0.2, 0.85, 0.52) if actor == "player" else Color(0.95, 0.28, 0.2))
		_shield[actor] = _bar(row, "Shield", Color(0.25, 0.6, 1.0))


func _bar(parent: Control, node_name: String, colour: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(112, 13)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", Style.box(Color(0.02, 0.03, 0.05, 0.95), 4))
	bar.add_theme_stylebox_override("fill", Style.box(colour, 4))
	parent.add_child(bar)
	var label: Label = Label.new()
	label.name = "Value"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bar


func _process(_delta: float) -> void:
	if camera == null or board == null or not Conditions.has_combat():
		visible = false
		return
	visible = true
	var combat: Dictionary = GameState.state["combat"]
	var enemy: Dictionary = DataLoader.get_record(str(combat["enemy"]))
	for actor: String in _rows:
		var vessel: Node3D = board.get_node("PlayerShip" if actor == "player" else "EnemyShip")
		var anchor: Vector3 = vessel.global_position + Vector3.UP * 2.0
		var screen: Vector2 = camera.unproject_position(anchor)
		var row: VBoxContainer = _rows[actor]
		row.visible = vessel.visible and not camera.is_position_behind(anchor) and Rect2(Vector2.ZERO, size).has_point(screen)
		row.position = screen - Vector2(56, 34)
		var hull: Dictionary = GameState.state["ship"]["hull"] if actor == "player" else {"current": combat[actor]["hull"], "max": enemy["hull"]}
		_sync_bar(_hull[actor], float(hull["current"]), float(hull["max"]), "ui_tactical_hull")
		_sync_bar(_shield[actor], float(combat[actor]["shield"]), Math.player_shield_max() if actor == "player" else float(enemy["shield"]), "ui_tactical_shield")


func _sync_bar(bar: ProgressBar, current: float, maximum: float, text_id: String) -> void:
	bar.max_value = maxf(1.0, maximum)
	bar.value = current
	bar.get_node("Value").text = Text.get_text(text_id, {"current": String.num(current, 1), "max": String.num(maximum, 1)})
