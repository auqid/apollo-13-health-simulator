// The South Pacific for the parachute descent and splashdown: a few long swells moving the
// surface, small ripples in the normals, deep blue looking down and sky colour at grazing angles.
shader_type spatial;
render_mode cull_back;

uniform vec4 deep_color : source_color = vec4(0.015, 0.09, 0.17, 1.0);
uniform vec4 sky_color : source_color = vec4(0.45, 0.6, 0.75, 1.0);
uniform float swell_height = 0.45;
uniform float ripple_strength = 0.35;
uniform float speed = 0.6;

// Direction (xy), wavelength in metres (z), share of the swell height (w). Long enough for the
// mesh grid to follow; shorter waves are only in the ripples below.
const vec4 SWELLS[3] = vec4[3](vec4(0.95, 0.31, 80.0, 0.55), vec4(-0.42, 0.91, 52.0, 0.3), vec4(0.71, -0.7, 34.0, 0.15));
const vec4 RIPPLES[3] = vec4[3](vec4(0.2, 0.98, 2.3, 1.0), vec4(0.94, -0.33, 1.4, 0.7), vec4(-0.8, -0.6, 0.9, 0.5));

varying vec3 world_position;

vec3 surface(vec2 p, float t) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		vec2 direction = normalize(SWELLS[i].xy);
		float k = 6.2832 / SWELLS[i].z;
		float phase = dot(p, direction) * k + t * sqrt(9.8 * k) * speed;
		float amplitude = swell_height * SWELLS[i].w;
		height += sin(phase) * amplitude;
		slope += direction * cos(phase) * amplitude * k;
	}
	return vec3(height, slope);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wave = surface(world_position.xz, TIME);
	VERTEX.y += wave.x;
	NORMAL = normalize(vec3(-wave.y, 1.0, -wave.z));
}

void fragment() {
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		vec2 direction = normalize(RIPPLES[i].xy);
		float k = 6.2832 / RIPPLES[i].z;
		float phase = dot(world_position.xz, direction) * k + TIME * sqrt(9.8 * k) * speed;
		slope += direction * cos(phase) * RIPPLES[i].w * 0.05 * k;
	}
	vec3 ripple = normalize(vec3(-slope.x, 1.0, -slope.y) * vec3(ripple_strength, 1.0, ripple_strength));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, 0.5));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	ALBEDO = mix(deep_color.rgb, sky_color.rgb, fresnel * 0.85);
	ROUGHNESS = 0.12;
	SPECULAR = 0.55;
}
