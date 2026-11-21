extends MeshInstance3D

const G = preload("res://scripts/model_geometry.gd")
const Conditions = preload("res://scripts/condition_evaluator.gd")
const PORTAL_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float phase = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float a = atan(p.y, p.x);
	float spiral = pow(0.5 + 0.5 * sin(a * 5.0 + r * 24.0 - phase * 4.0), 3.0);
	float edge = 1.0 - smoothstep(0.65, 1.0, r);
	ALBEDO = mix(vec3(0.07, 0.04, 0.21), vec3(0.35, 0.75, 1.0), spiral * (0.3 + r * 0.7));
	ALPHA = edge * (0.45 + spiral * 0.4);
}
"""

var _phase: float = 0.0
var _portal: ShaderMaterial


func configure() -> void:
	var disc: PlaneMesh = PlaneMesh.new()
	disc.size = Vector2(2.5, 2.5)
	var view: MeshInstance3D = G.part(self, "Vortex", disc, Vector3.ZERO, Color.WHITE)
	var shader: Shader = Shader.new()
	shader.code = PORTAL_SHADER
	_portal = ShaderMaterial.new()
	_portal.shader = shader
	view.material_override = _portal
	G.ring(self, "InnerRim", Vector3(0, 0.02, 0), 0.87, 0.025, Color(0.2, 0.7, 1.0), true)
	for index: int in range(8):
		var angle: float = TAU * index / 8.0
		var brace: MeshInstance3D = G.box(self, "Anchor", Vector3(cos(angle) * 1.24, 0, sin(angle) * 1.24), Vector3(0.18, 0.16, 0.38), Color(0.18, 0.22, 0.32))
		brace.rotation.y = -angle


func _process(delta: float) -> void:
	if _portal == null or not Conditions.can_tick_flight():
		return
	_phase += delta
	_portal.set_shader_parameter("phase", _phase)
	rotation.y = _phase * 0.07
