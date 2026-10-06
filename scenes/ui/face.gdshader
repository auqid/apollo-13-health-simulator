// A crew member's photo, reacting to how they are: drained toward blue in the cold, trembling
// when shivering, flushed with fever, greyer and dimmer when worn out. Changes are gradual and
// nothing flashes; the tremble moves the photo by a pixel or two.
shader_type canvas_item;

uniform float cold : hint_range(0.0, 1.0) = 0.0;
uniform float shiver : hint_range(0.0, 1.0) = 0.0;
uniform float flush : hint_range(0.0, 1.0) = 0.0;
uniform float tired : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cold_color : source_color = vec3(0.616, 0.722, 0.851);
uniform vec3 flush_color : source_color = vec3(1.0, 0.45, 0.36);
// How far shivering moves the photo, as a share of its size: about two pixels in the HUD.
uniform float shiver_reach = 0.03;
// Seconds of play, set by the HUD, so the tremble stops while the game is paused.
uniform float clock = 0.0;

void fragment() {
	vec2 uv = UV;
	if (shiver > 0.0) {
		uv += vec2(sin(clock * 47.0), sin(clock * 39.0 + 1.3)) * shiver * shiver_reach;
	}
	vec4 photo = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	vec3 color = photo.rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	// Cold: the colour drains toward a cool blue.
	color = mix(color, luma * cold_color * 1.15, cold * 0.6);
	// Worn out: greyer and dimmer, most at the edges.
	color = mix(color, vec3(dot(color, vec3(0.299, 0.587, 0.114))), tired * 0.45);
	float edge = smoothstep(0.3, 0.75, length(UV - vec2(0.5)));
	color *= 1.0 - tired * (0.15 + 0.35 * edge);
	// Fever last, so the flush still shows on a cold, tired face: warmest in the middle of the face.
	float face = 1.0 - smoothstep(0.12, 0.5, length((UV - vec2(0.5, 0.4)) * vec2(1.0, 0.8)));
	float warm = dot(color, vec3(0.299, 0.587, 0.114)) * 1.5;
	color = mix(color, warm * flush_color, flush * 0.7 * face);
	COLOR = vec4(color, photo.a);
}
