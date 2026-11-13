extends RefCounted

const CARD_SIZE: float = 90.0


static func box(color: Color, radius: int = 14, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(width)
	style.border_color = border
	style.corner_detail = 12
	return style


static func identity_color(identifier: String) -> Color:
	return Color.from_hsv(float(absi(identifier.hash()) % 360) / 360.0, 0.45, 0.65)


static func avatar(heroine_id: String, size: float = 24.0) -> PanelContainer:
	var icon: PanelContainer = PanelContainer.new()
	icon.name = heroine_id
	icon.custom_minimum_size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.tooltip_text = str(DataLoader.get_record(heroine_id).get("name", heroine_id))
	icon.add_theme_stylebox_override("panel", box(identity_color(heroine_id), int(size / 3.0)))
	var initial: Label = Label.new()
	initial.text = heroine_id.left(1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.add_theme_font_size_override("font_size", int(size * 0.55))
	icon.add_child(initial)
	return icon
