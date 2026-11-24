extends RefCounted

const Style = preload("res://scripts/hub_widgets.gd")
const PAPER: Color = Color("f6e8d1")
const CARD: Color = Color("fff3df")
const INK: Color = Color("493528")
const MUTED: Color = Color("7c644b")
const BORDER: Color = Color("c8a475")
const ACCENT: Color = Color("b47731")
const GLOW: Color = Color("ffce7b")
static var _theme: Theme


static func surface(radius: int = 14, opacity: float = 0.96) -> StyleBoxFlat:
	var box: StyleBoxFlat = Style.box(Color(PAPER, opacity), radius, BORDER, 1)
	box.shadow_color = Color(0.27, 0.15, 0.07, 0.14)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	return box


static func make() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 16
	_theme.set_color("font_color", "Label", INK)
	for type: String in ["Button", "OptionButton"]:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var fill: Color = Color("efdab7")
			var border: Color = BORDER
			if state == "hover":
				fill = Color("ffe5b6")
				border = ACCENT
			elif state == "pressed":
				fill = Color("e5c58f")
			elif state == "disabled":
				fill = Color("e8decd")
				border = Color("d1c4b0")
			var button: StyleBoxFlat = Style.box(fill, 8, border, 1)
			button.content_margin_left = 14
			button.content_margin_right = 14
			button.content_margin_top = 7
			button.content_margin_bottom = 7
			_theme.set_stylebox(state, type, button)
		_theme.set_stylebox("focus", type, Style.box(Color.TRANSPARENT, 8, ACCENT, 2))
		_theme.set_color("font_color", type, INK)
		_theme.set_color("font_focus_color", type, INK)
		_theme.set_color("font_hover_color", type, Color("3e2817"))
		_theme.set_color("font_hover_pressed_color", type, INK)
		_theme.set_color("font_pressed_color", type, INK)
		_theme.set_color("font_disabled_color", type, Color("91816a"))
	_theme.set_stylebox("panel", "PanelContainer", surface(12))
	_theme.set_stylebox("card", "PanelContainer", Style.box(CARD, 12, Color("d9bd95"), 1))
	_theme.set_stylebox("background", "ProgressBar", Style.box(Color("e0ccad"), 5))
	_theme.set_stylebox("fill", "ProgressBar", Style.box(ACCENT, 5))
	var tooltip: StyleBoxFlat = surface(7, 1.0)
	tooltip.set_content_margin_all(8)
	_theme.set_stylebox("panel", "TooltipPanel", tooltip)
	_theme.set_color("font_color", "TooltipLabel", INK)
	var dialog: StyleBoxFlat = surface(12, 1.0)
	dialog.set_content_margin_all(18)
	_theme.set_stylebox("panel", "AcceptDialog", dialog)
	var window: StyleBoxFlat = surface(12, 1.0)
	window.content_margin_top = 32
	window.expand_margin_top = 32
	_theme.set_stylebox("embedded_border", "Window", window)
	_theme.set_stylebox("embedded_unfocused_border", "Window", window)
	_theme.set_color("title_color", "Window", INK)
	_theme.set_color("title_unfocused_color", "Window", MUTED)
	return _theme
