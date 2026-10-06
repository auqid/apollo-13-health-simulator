// Faint engine exhaust on a cone mesh: brightest at the nozzle and along the middle of the cone,
// fading toward its far end and its edges, so it has no hard outline. Added onto the scene.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 plume_color : source_color = vec4(1.0, 0.78, 0.5, 1.0);
uniform float strength = 0.0;
// A slow ripple along the plume, well under three times a second.
uniform float ripple_hz = 1.6;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float near_nozzle = pow(1.0 - UV.y, 2.6);
	float ripple = 0.9 + 0.1 * sin(TIME * 6.2832 * ripple_hz - UV.y * 18.0);
	ALBEDO = plume_color.rgb;
	ALPHA = clamp(strength * pow(facing, 4.0) * near_nozzle * ripple, 0.0, 1.0);
}
