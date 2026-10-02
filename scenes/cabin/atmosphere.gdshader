// Thin blue rim around the Earth, brightest at the edge of the disc.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 rim_color : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform float rim_power = 3.0;
uniform float strength = 1.2;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * rim * strength;
}
