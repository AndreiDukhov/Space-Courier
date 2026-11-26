shader_type canvas_item;

void fragment() {
	COLOR = texture(TEXTURE, UV);
	COLOR.a = step(0.5, COLOR.a);
}
