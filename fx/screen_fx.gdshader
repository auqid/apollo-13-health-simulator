// Full-screen effects on the 3D view (SPEC.md section 4): CO2 vignette and blur, cold tint,
// condensation droplets and the blackout used for micro-blinks. This sits on a canvas layer under
// the HUD, so the screen it samples is the 3D view only and HUD text never blurs.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
// The vignette starts this far from the centre (0 centre, 1 corner), so the middle stays clear.
uniform float vignette_inner = 0.42;
uniform float vignette_outer = 1.05;
// Blur radius in pixels at 1080p; scaled to the real screen height.
uniform float blur_px = 0.0;
uniform float base_height = 1080.0;
uniform float tint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint_color : source_color = vec3(0.616, 0.722, 0.851);
uniform float condensation : hint_range(0.0, 1.0) = 0.0;
// Droplet grid cells across the screen height; droplets are heavier toward the edges.
uniform float droplet_cells = 16.0;
uniform float droplet_centre_share = 0.25;
uniform float blackout : hint_range(0.0, 1.0) = 0.0;

const vec2 DISK[12] = vec2[12](
	vec2(-0.326, -0.406), vec2(-0.840, -0.074), vec2(-0.696, 0.457), vec2(-0.203, 0.621),
	vec2(0.962, -0.195), vec2(0.473, -0.480), vec2(0.519, 0.767), vec2(0.185, -0.893),
	vec2(0.507, 0.064), vec2(0.896, 0.412), vec2(-0.322, -0.933), vec2(-0.792, -0.598));

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// One droplet per grid cell (some cells empty): a small lens that bends the view behind it,
// a darker rim and a soft highlight. Static, so nothing flickers.
void droplet(vec2 uv, float aspect, out vec2 offset, out float shade, out float highlight) {
	vec2 grid = vec2(uv.x * aspect, uv.y) * droplet_cells;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float present = step(0.45, hash12(cell + 7.0));
	vec2 centre = 0.3 + 0.4 * hash22(cell);
	float radius = mix(0.14, 0.26, hash12(cell + 19.0));
	vec2 d = local - centre;
	float dist = length(d);
	float inside = present * (1.0 - smoothstep(radius * 0.75, radius, dist));
	offset = -d * inside * 0.2 / droplet_cells * vec2(1.0 / aspect, 1.0);
	shade = inside * 0.4;
	highlight = inside * (1.0 - smoothstep(0.0, radius * 0.4, length(d + vec2(radius * 0.25, radius * 0.25)))) * 0.22;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 centred = (uv - 0.5) * vec2(aspect, 1.0);
	float radial = length(centred) / (0.5 * length(vec2(aspect, 1.0)));

	vec2 offset = vec2(0.0);
	float shade = 0.0;
	float highlight = 0.0;
	if (condensation > 0.001) {
		droplet(uv, aspect, offset, shade, highlight);
		// Heavier toward the edges and the bottom of the glass, clear in the middle.
		float edge = smoothstep(0.55, 0.95, radial);
		float bottom = smoothstep(0.28, 0.0, uv.y);
		float amount = condensation * max(edge, bottom * 0.75);
		amount = max(amount, condensation * droplet_centre_share);
		offset *= amount;
		shade *= amount;
		highlight *= amount;
	}

	vec2 sample_uv = uv + offset;
	vec3 color = texture(screen_texture, sample_uv).rgb;
	if (blur_px > 0.05) {
		vec2 radius_uv = vec2(1.0 / aspect, 1.0) * (blur_px / base_height);
		for (int i = 0; i < 12; i++) {
			color += texture(screen_texture, sample_uv + DISK[i] * radius_uv).rgb;
		}
		color /= 13.0;
	}

	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, luma * tint_color * 1.2, tint);
	color = color * (1.0 - shade) + vec3(highlight);
	color *= 1.0 - vignette * smoothstep(vignette_inner, vignette_outer, radial);
	color *= 1.0 - blackout;
	COLOR = vec4(color, 1.0);
}
