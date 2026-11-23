extends RefCounted

const Style = preload("res://scripts/hub_widgets.gd")
static var _theme: Theme


static func make() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 16
	for type: String in ["Button", "OptionButton"]:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var fill: Color = Color("142731")
			var border: Color = Color("35505b")
			if state == "hover":
				fill = Color("203d47")
				border = Color("6fa9ad")
			elif state == "pressed":
				fill = Color("091a22")
				border = Color("71c2ba")
			elif state == "disabled":
				fill = Color("101a20")
				border = Color("24333b")
			var box: StyleBoxFlat = Style.box(fill, 7, border, 1)
			box.content_margin_left = 14
			box.content_margin_right = 14
			box.content_margin_top = 7
			box.content_margin_bottom = 7
			box.shadow_color = Color(0, 0, 0, 0.25)
			box.shadow_size = 3
			box.shadow_offset = Vector2(0, 2)
			_theme.set_stylebox(state, type, box)
		_theme.set_stylebox("focus", type, Style.box(Color.TRANSPARENT, 7, Color("87c9c5"), 1))
		_theme.set_color("font_color", type, Color("e5ece9"))
		_theme.set_color("font_hover_color", type, Color("f6fffb"))
		_theme.set_color("font_pressed_color", type, Color("a9ddd8"))
		_theme.set_color("font_disabled_color", type, Color("65767d"))
	_theme.set_color("font_color", "Label", Color("d9e4e5"))
	_theme.set_stylebox("panel", "PanelContainer", Style.box(Color("0d1b25"), 8, Color("2b424c"), 1))
	_theme.set_stylebox("background", "ProgressBar", Style.box(Color("091117"), 4))
	_theme.set_stylebox("fill", "ProgressBar", Style.box(Color("478b88"), 4))
	var dialog: StyleBoxFlat = Style.box(Color("11222c"), 8, Color("48636d"), 1)
	dialog.set_content_margin_all(18)
	_theme.set_stylebox("panel", "AcceptDialog", dialog)
	var window: StyleBoxFlat = Style.box(Color("13232d"), 8, Color("48636d"), 1)
	window.content_margin_top = 32
	window.expand_margin_top = 32
	window.shadow_color = Color(0, 0, 0, 0.4)
	window.shadow_size = 10
	_theme.set_stylebox("embedded_border", "Window", window)
	_theme.set_stylebox("embedded_unfocused_border", "Window", window)
	_theme.set_color("title_color", "Window", Color("e5ece9"))
	return _theme
