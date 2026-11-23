extends Button

const Text = preload("res://scripts/ui_text.gd")
var _travel: float = 0.0


func _ready() -> void:
	toggle_mode = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	resized.connect(queue_redraw)
	tooltip_text = Text.get_text("ui_map_boost")


func _process(delta: float) -> void:
	var next: float = move_toward(_travel, 1.0 if button_pressed else 0.0, delta * 7)
	if next != _travel:
		_travel = next
		queue_redraw()


func _draw() -> void:
	var centre: float = size.x * 0.5
	var plate: Rect2 = Rect2(centre - 27, 4, 54, 100)
	var metal: Color = Color("778d97")
	draw_style_box(_box(Color("09141ce6"), 10, Color("3d535d")), plate)
	draw_style_box(_box(Color("172630"), 8, Color("50636b")), plate.grow(-3))
	for y: float in [12.0, 96.0]:
		for x: float in [centre - 19, centre + 19]:
			draw_circle(Vector2(x, y), 2, Color("0a1117"))
			draw_line(Vector2(x - 1, y), Vector2(x + 1, y), metal, 1)
	draw_style_box(_box(Color("02070a"), 5, Color("293d47")), Rect2(centre - 9, 22, 18, 63))
	var pivot: Vector2 = Vector2(centre, 55)
	var tip: Vector2 = Vector2(centre, lerpf(76, 31, _travel))
	draw_line(pivot + Vector2(2, 2), tip + Vector2(2, 2), Color(0, 0, 0, 0.65), 10, true)
	draw_line(pivot, tip, Color("324953"), 8, true)
	draw_line(pivot - Vector2(2, 0), tip - Vector2(2, 0), Color("a4b9bf"), 2, true)
	draw_style_box(_box(Color("647e88"), 4, Color("a8bec2")), Rect2(tip - Vector2(17, 6), Vector2(34, 12)))
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		draw_line(tip + Vector2(x, -3), tip + Vector2(x, 3), Color("354c55"), 1)
	var light: Color = Color("73d6b4") if button_pressed else Color("455963")
	draw_circle(Vector2(centre, 15), 3, light)
	var font: Font = get_theme_default_font()
	var caption: String = Text.get_text("ui_hud_boost")
	var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(centre - width * 0.5, 126), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("d6e5e7"))
	if has_focus() or is_hovered():
		draw_style_box(_box(Color.TRANSPARENT, 10, Color("82b6ba")), plate.grow(1))


func _box(color: Color, radius: int, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = border
	return box
