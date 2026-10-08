shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// The ocean: one huge flat sheet that follows the glider. Deep blue out at sea, turquoise over
// the shallows and white with foam where it meets the land (it reads the island's height map to
// know how deep the water is). Small waves tilt the surface so it picks up the sky and the sun's
// glitter. It fades into the same haze as the sky at the horizon.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D height_tex : repeat_disable, filter_linear;
// The patch of world the height map covers: x, z of its corner, then its width and depth.
uniform vec4 land_rect = vec4(-1.0, -1.0, 2.0, 2.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 deep_color : source_color = vec3(0.05, 0.22, 0.45);
uniform vec3 shallow_color : source_color = vec3(0.2, 0.62, 0.66);
uniform vec3 sky_color : source_color = vec3(0.3, 0.5, 0.85);
uniform vec3 haze_color : source_color = vec3(0.73, 0.85, 0.96);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);
uniform float haze_distance = 8500.0;

varying vec3 w_pos;

float swell(vec2 p) {
	return texture(noise_tex, p / 310.0 + vec2(TIME * 0.011, TIME * 0.006)).r * 0.6
		+ texture(noise_tex, p / 83.0 - vec2(TIME * 0.02, -TIME * 0.013)).r * 0.4;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_eye);
	vec3 v = to_eye / dist;
	vec2 p = w_pos.xz;

	// Waves, flattening with distance so the far sea is calm, not noisy.
	float calm = 1.0 - smoothstep(800.0, 5000.0, dist);
	float h = swell(p);
	float hx = swell(p + vec2(6.0, 0.0));
	float hz = swell(p + vec2(0.0, 6.0));
	vec3 n = normalize(vec3((h - hx) * 5.0 * calm, 1.0, (h - hz) * 5.0 * calm));

	// How deep is the water here?
	vec2 uv = (p - land_rect.xy) / land_rect.zw;
	float ground = -120.0;
	if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
		ground = texture(height_tex, uv).r;
	}
	float depth = -ground;
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 70.0, depth));
	col *= mix(0.9, 1.08, h);

	// The surface mirrors the sky more at a glancing angle.
	float glance = pow(1.0 - max(dot(n, v), 0.0), 4.0);
	col = mix(col, sky_color, glance * 0.6);
	float glitter = pow(max(dot(reflect(-v, n), sun_dir), 0.0), 220.0);
	col += sun_color * glitter * 1.6;

	// Foam: a ragged white line at the shore that breathes in and out, and a few whitecaps.
	float wash = 9.0 + 5.0 * sin(TIME * 0.7 + h * 12.0);
	float foam = (1.0 - smoothstep(wash * 0.5, wash, depth)) * smoothstep(0.35, 0.6, h + 0.25);
	foam = max(foam, smoothstep(0.76, 0.8, h) * 0.3 * calm);
	col = mix(col, vec3(0.97), foam);

	float haze = 1.0 - exp(-dist / haze_distance);
	haze = max(haze * 0.95, smoothstep(9000.0, 15000.0, dist));
	ALBEDO = mix(col, haze_color, haze);
}
