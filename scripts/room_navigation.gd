extends HBoxContainer

const Widgets = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const VISIBLE_ROOMS: int = 6
const SCROLL_SECONDS: float = 0.28

@onready var previous: Button = $Previous
@onready var next: Button = $Next
@onready var viewport: ScrollContainer = $RoomsViewport
@onready var rooms: HBoxContainer = $RoomsViewport/Locations

var _first_room: int = 0
var _selected_room: String = ""
var _scroll_tween: Tween


func _ready() -> void:
	var gap: int = rooms.get_theme_constant("separation")
	viewport.custom_minimum_size.x = VISIBLE_ROOMS * Widgets.CARD_SIZE + (VISIBLE_ROOMS - 1) * gap
	previous.tooltip_text = Text.get_text("ui_hub_rooms_previous")
	next.tooltip_text = Text.get_text("ui_hub_rooms_next")
	previous.pressed.connect(_scroll_rooms.bind(-1))
	next.pressed.connect(_scroll_rooms.bind(1))
	for button: Button in [previous, next]:
		button.add_theme_stylebox_override("normal", Widgets.box(Color.TRANSPARENT, 12))
		button.add_theme_stylebox_override("hover", Widgets.box(Color(0.0, 0.0, 0.0, 0.35), 12))
		button.add_theme_stylebox_override("pressed", Widgets.box(Color(0.0, 0.0, 0.0, 0.55), 12))
		button.add_theme_stylebox_override("disabled", Widgets.box(Color.TRANSPARENT, 12))
		button.add_theme_stylebox_override("focus", Widgets.box(Color.TRANSPARENT, 12, Color(0.4, 0.8, 0.8), 2))
		button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.45))
	_update_arrows()


func sync(selected_room: String) -> void:
	_first_room = clampi(_first_room, 0, _last_start())
	if selected_room != _selected_room:
		var selected: Node = rooms.get_node_or_null(NodePath(selected_room))
		if selected != null:
			var index: int = selected.get_index()
			_first_room = clampi(_first_room, index - VISIBLE_ROOMS + 1, index)
			_first_room = clampi(_first_room, 0, _last_start())
	_selected_room = selected_room
	_update_arrows()
	_scroll_to_target.call_deferred()


func _scroll_rooms(direction: int) -> void:
	_first_room = clampi(_first_room + direction, 0, _last_start())
	_update_arrows()
	_scroll_to_target()


func _scroll_to_target() -> void:
	if _scroll_tween != null:
		_scroll_tween.kill()
	var gap: int = rooms.get_theme_constant("separation")
	var target: int = roundi(_first_room * (Widgets.CARD_SIZE + gap))
	_scroll_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_scroll_tween.tween_property(viewport, "scroll_horizontal", target, SCROLL_SECONDS)


func _last_start() -> int:
	return maxi(0, rooms.get_child_count() - VISIBLE_ROOMS)


func _update_arrows() -> void:
	previous.disabled = _first_room == 0
	next.disabled = _first_room == _last_start()
	previous.visible = rooms.get_child_count() > VISIBLE_ROOMS
	next.visible = previous.visible
