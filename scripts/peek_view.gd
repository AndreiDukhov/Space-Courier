extends Control

signal closed

const Art = preload("res://scripts/location_art.gd")
const Text = preload("res://scripts/ui_text.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const HubTheme = preload("res://scripts/hub_theme.gd")
const Lighting = preload("res://scripts/hub_lighting.gd")
const Door = preload("res://scripts/peek_door.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")

var location_id: String = ""
var _room: Control
var _door: Door
var _look: Vector2 = Vector2.ZERO
var _offset: Vector2 = Vector2.ZERO
var _placeholder: Label
var _dragging: bool = false
var _pointer: Vector2
var _motion_time: int = 0
var _caught: CenterContainer


func _ready() -> void:
	name = "PeekView"
	theme = HubTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_build_room()
	_door = Door.new()
	_door.name = "DoorSprites"
	add_child(_door)
	var close: Button = Widgets.button("Close", "ui_peek_close", closed.emit)
	add_child(close)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -180
	close.offset_right = -22
	close.offset_top = 22
	close.offset_bottom = 60
	var hint: Label = Widgets.label(Text.get_text("ui_peek_drag_hint"), 15)
	hint.name = "DragHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("fff2da"))
	hint.add_theme_color_override("font_outline_color", HubTheme.INK)
	hint.add_theme_constant_override("outline_size", 5)
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 24
	hint.offset_right = -24
	hint.offset_top = -54
	hint.offset_bottom = -18
	resized.connect(_layout)
	EffectApplier.peek_changed.connect(_sync)
	PauseMenu.opened.connect(_stop_dragging)
	_layout()
	_sync()


func _build_room() -> void:
	_room = Control.new()
	_room.name = "Room"
	_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_room)
	var texture: Texture2D = Art.new().background_for(DataLoader.get_record(location_id), Clock.current_slot())
	if texture != null:
		var image: TextureRect = TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.material = Lighting.new().material_for(location_id, Clock.current_slot())
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_room.add_child(image)
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var wall: ColorRect = ColorRect.new()
		wall.color = Color("c4d3cd")
		wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_room.add_child(wall)
		wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_placeholder = Widgets.label(Text.get_text("ui_peek_placeholder"), 22)
		_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_placeholder.size = Vector2(140, 90)
		_room.add_child(_placeholder)


func _layout() -> void:
	_room.size = size * 1.16
	if _placeholder != null:
		_placeholder.position = _room.size * Vector2(0.38, 0.5) - _placeholder.size * 0.5
	_door.layout(size)
	_sync()
	_place_room()


func _sync() -> void:
	var peek: Dictionary = GameState.state.get("peek", {})
	if peek.is_empty():
		return
	_door.show_opening(0.0 if peek["noticed"] else float(peek["opening"]))
	get_node("DragHint").visible = not peek["noticed"]
	if peek["noticed"] and _caught == null:
		_stop_dragging()
		_show_caught()


func _show_caught() -> void:
	_caught = CenterContainer.new()
	_caught.name = "Caught"
	add_child(_caught)
	_caught.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = 400
	panel.add_theme_stylebox_override("panel", HubTheme.surface(16, 1.0))
	_caught.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var message: Label = Widgets.label(Text.get_text("ui_peek_caught_empty" if Conditions.peek_occupants().is_empty() else "ui_peek_caught"), 20)
	message.custom_minimum_size.x = 350
	column.add_child(message)
	column.add_child(Widgets.button("Leave", "ui_peek_close", closed.emit))


func _stop_dragging() -> void:
	_dragging = false


func _place_room() -> void:
	_room.position = (size - _room.size) * 0.5 + _offset
	_room.pivot_offset = _room.size * 0.5
	_room.rotation = _offset.x * 0.0001


func _process(delta: float) -> void:
	_offset = _offset.lerp(_look, 1.0 - exp(-delta * 9.0))
	_place_room()


func _gui_input(event: InputEvent) -> void:
	var peek: Dictionary = GameState.state.get("peek", {})
	if peek.is_empty() or peek["noticed"]:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _door.contains_global(get_global_transform() * event.position)
		_pointer = event.position
		_motion_time = Time.get_ticks_usec()
	elif event is InputEventMouseMotion and _dragging:
		var now: int = Time.get_ticks_usec()
		var elapsed: float = clampf(float(now - _motion_time) / 1000000.0, 1.0 / 240.0, 0.1)
		var opening: float = clampf(float(peek["opening"]) + (event.position.x - _pointer.x) / _door.travel_pixels, 0.0, 1.0)
		_pointer = event.position
		_motion_time = now
		EffectApplier.move_peek_door(opening, elapsed)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_look = ((event.position / size - Vector2.ONE * 0.5) * Vector2(80, 36)).clamp(Vector2(-40, -18), Vector2(40, 18))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_stop_dragging()
