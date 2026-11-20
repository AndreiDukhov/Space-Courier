extends Control

const Roster = preload("res://scripts/combat_roster.gd")
const Math = preload("res://scripts/combat_math.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")

var camera: Camera3D
var board: Node3D
var _rows: Dictionary = {}
var _hull: Dictionary = {}
var _shield: Dictionary = {}
var _anchors: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_rows()
	RenderingServer.frame_pre_draw.connect(_sync)


func _sync_rows() -> void:
	var actors: Array[String] = Roster.ids()
	for actor: String in _rows.keys():
		if actor not in actors:
			remove_child(_rows[actor])
			_rows[actor].queue_free()
			for cache: Dictionary in [_rows, _hull, _shield]:
				cache.erase(actor)
	for actor: String in actors:
		if _rows.has(actor):
			continue
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "PlayerVitals" if actor == "player" else ("AllyVitals" if Roster.friendly(actor) else "EnemyVitals") + ("2" if actor.ends_with("_2") else "")
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(112, 32)
		row.add_theme_constant_override("separation", 3)
		add_child(row)
		_rows[actor] = row
		_hull[actor] = _bar(row, "Hull", Color(0.2, 0.85, 0.52) if actor == "player" else Color(0.3, 0.65, 1.0) if Roster.friendly(actor) else Color(0.95, 0.28, 0.2))
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
	_sync()


func _sync() -> void:
	if not is_inside_tree():
		return
	if camera == null or board == null or not Conditions.has_combat():
		visible = false
		return
	visible = true
	var combat: Dictionary = GameState.state["combat"]
	_sync_rows()
	for actor: String in _rows:
		var entry: Dictionary = Roster.actor(actor, combat)
		var enemy: Dictionary = {} if actor == "player" else DataLoader.get_record(str(entry["enemy"]))
		var vessel: Node3D = board._vessels[actor]
		var anchor: Vector3 = vessel.global_position + Vector3.UP * 2.0
		var screen: Vector2 = camera.unproject_position(anchor)
		var row: VBoxContainer = _rows[actor]
		row.visible = vessel.visible and not camera.is_position_behind(anchor) and Rect2(Vector2.ZERO, size).has_point(screen)
		row.position = screen - Vector2(56, 34)
		_anchors[actor] = screen
		var hull: Dictionary = GameState.state["ship"]["hull"] if actor == "player" else {"current": entry["hull"], "max": enemy["hull"]}
		_sync_bar(_hull[actor], float(hull["current"]), float(hull["max"]), "ui_tactical_hull")
		_sync_bar(_shield[actor], float(entry["shield"]), Math.player_shield_max() if actor == "player" else float(enemy["shield"]), "ui_tactical_shield")
	_arrange_rows()


func _arrange_rows() -> void:
	var placed: Array[Rect2] = []
	for row: VBoxContainer in _rows.values():
		if not row.visible:
			continue
		var preferred: Vector2 = row.position
		var offsets: Array[Vector2] = [Vector2.ZERO]
		for distance: int in range(1, _rows.size() + 1):
			for direction: Vector2 in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
				offsets.append(direction * (row.size + Vector2(6, 6)) * distance)
		for offset: Vector2 in offsets:
			var position: Vector2 = (preferred + offset).clamp(Vector2(4, 4), (size - row.size - Vector2(4, 4)).max(Vector2(4, 4)))
			var rect: Rect2 = Rect2(position, row.size)
			var clear: bool = true
			for other: Rect2 in placed:
				clear = clear and not rect.intersects(other)
			if clear:
				row.position = position
				break
		placed.append(row.get_rect())
	queue_redraw()


func _draw() -> void:
	for actor: String in _rows:
		var row: Control = _rows[actor]
		if row.visible and _anchors.has(actor):
			var start: Vector2 = row.position + Vector2(row.size.x * 0.5, row.size.y)
			if start.distance_to(_anchors[actor]) > 10.0:
				draw_line(start, _anchors[actor], Color(0.55, 0.7, 0.85, 0.6), 1.0, true)


func _sync_bar(bar: ProgressBar, current: float, maximum: float, text_id: String) -> void:
	bar.max_value = maxf(1.0, maximum)
	bar.value = current
	bar.get_node("Value").text = Text.get_text(text_id, {"current": String.num(current, 1), "max": String.num(maximum, 1)})
