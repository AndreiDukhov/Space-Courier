extends Control

var accepts: Callable
var received: Callable
var occupied: bool = false
var _hovered: bool = false


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw())


func _draw() -> void:
	if _hovered or occupied:
		var colour: Color = Color(0.4, 1.0, 0.7, 0.65 if _hovered else 0.2)
		draw_rect(Rect2(Vector2.ZERO, size), colour, false, 1.5)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.get("item") is String or not data.get("entry") is int:
		return false
	return accepts.is_valid() and bool(accepts.call(str(data["item"]), int(data["entry"])))


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data) and received.is_valid():
		received.call(str(data["item"]), int(data["entry"]))
