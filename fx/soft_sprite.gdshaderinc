// Shared by soft_puff.gdshader (gas, steam, spray) and soft_glow.gdshader (plasma, flashes).
// A round sprite that always faces the camera, with a soft edge broken up a little so it reads
// as gas rather than a disc. Each sprite sets its own colour and opacity through instance
// uniforms, so one material serves a whole cloud.

uniform float edge_power : hint_range(0.5, 4.0) = 1.8;
// 0 keeps the edge smooth; higher breaks it into wisps.
uniform float wisp : hint_range(0.0, 1.0) = 0.35;
uniform float brightness = 1.0;
instance uniform vec4 puff_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform float puff_seed = 0.0;

float sprite_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sprite_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = sprite_hash(i);
	float b = sprite_hash(i + vec2(1.0, 0.0));
	float c = sprite_hash(i + vec2(0.0, 1.0));
	float d = sprite_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	// Face the camera and keep the instance scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float detail = sprite_noise(p * 2.2 + puff_seed * 37.0) * 0.65 + sprite_noise(p * 5.1 - puff_seed * 11.0) * 0.35;
	float edge = r + (detail - 0.5) * wisp;
	float shape = pow(clamp(1.0 - edge, 0.0, 1.0), edge_power);
	ALBEDO = puff_color.rgb * brightness;
	ALPHA = shape * puff_color.a;
}
