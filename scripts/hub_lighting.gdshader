shader_type canvas_item;

uniform sampler2D light_mask : filter_linear, repeat_disable;
uniform float ambient = 1.0;
uniform float light_gain = 0.0;
uniform bool desaturate = false;

void fragment() {
	float brightness = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec2 step_uv = 1.0 / vec2(textureSize(light_mask, 0));
	float mask = texture(light_mask, UV).r * 0.4;
	mask += texture(light_mask, UV + vec2(step_uv.x, 0.0)).r * 0.15;
	mask += texture(light_mask, UV - vec2(step_uv.x, 0.0)).r * 0.15;
	mask += texture(light_mask, UV + vec2(0.0, step_uv.y)).r * 0.15;
	mask += texture(light_mask, UV - vec2(0.0, step_uv.y)).r * 0.15;
	float source = smoothstep(0.24, 0.90, brightness) * mask;
	vec3 lit = COLOR.rgb * (ambient + light_gain * source);
	if (desaturate) {
		lit = vec3(dot(lit, vec3(0.299, 0.587, 0.114)));
	}
	COLOR = vec4(lit, COLOR.a);
}
