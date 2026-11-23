extends RefCounted


static func fits(label: Label3D, camera: Camera3D, reserved: Array[Rect2]) -> bool:
	if camera.is_position_behind(label.global_position):
		return false
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var scale: float = (viewport_size.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else viewport_size.y) / camera.size * label.pixel_size
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var lines: PackedStringArray = label.text.split("\n")
	var width: float = 0.0
	for line: String in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * scale)
	var height: float = font.get_height(label.font_size) * scale * lines.size()
	var origin: Vector2 = camera.unproject_position(label.global_position) + label.offset * scale - Vector2(0, height * 0.5)
	origin.x -= 0.0 if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else width if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT else width * 0.5
	var rect: Rect2 = Rect2(origin, Vector2(width, height)).grow(4)
	if not Rect2(Vector2.ZERO, viewport_size).encloses(rect):
		return false
	for area: Rect2 in reserved:
		if rect.intersects(area):
			return false
	return true
