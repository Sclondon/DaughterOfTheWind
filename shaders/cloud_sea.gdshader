shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// The sea of clouds far below: one big sheet that follows the glider, heaved into billows by
// noise (rounded tops, creased hollows) and lit in the same two tones as the puffs, white on the
// crowns and blue in the creases. It melts into the haze well before its edge, and the sky below
// the horizon is the same haze colour, so no edge shows.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 shade_color : source_color = vec3(0.62, 0.7, 0.84);
uniform vec3 haze_color : source_color = vec3(0.8, 0.88, 0.95);
uniform float haze_distance = 6000.0;
uniform float amp = 170.0;
uniform float reach = 9000.0;
// How far the clouds have drifted on the wind (world XZ).
uniform vec2 drift = vec2(0.0);

varying vec2 sea_pos;
varying vec3 w_pos;

// Round domes with creases between them, from the cell noise in the green channel.
float domes(vec2 uv, float lod) {
	float d = textureLod(noise_tex, uv, lod).g;
	return 1.0 - d * d;
}

// The shape the sheet itself is bent to. Only wide billows: the mesh is too coarse for more.
float swell(vec2 p) {
	float a = textureLod(noise_tex, p / 7300.0, 0.0).r;
	return a * 0.5 + domes(p / 5600.0 + vec2(0.31, 0.11), 0.0) * 0.55;
}

// Smaller billows on top, for the shading only.
float fluff(vec2 p) {
	return domes(p / 1700.0 + vec2(0.7, 0.43), 0.0) * 0.22 + domes(p / 610.0 + vec2(0.2, 0.9), 1.0) * 0.07;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sea_pos = world.xz - drift;
	VERTEX.y += swell(sea_pos) * amp;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	// The small billows fade with distance so they do not shimmer.
	float fine = 1.0 - smoothstep(1500.0, 5000.0, dist);
	float e = 24.0;
	float h = swell(sea_pos) + fluff(sea_pos) * fine;
	float hx = swell(sea_pos + vec2(e, 0.0)) + fluff(sea_pos + vec2(e, 0.0)) * fine;
	float hz = swell(sea_pos + vec2(0.0, e)) + fluff(sea_pos + vec2(0.0, e)) * fine;
	vec3 n = normalize(vec3(-(hx - h) * amp * 2.4, e, -(hz - h) * amp * 2.4));

	float light = dot(n, sun_dir) * 0.5 + 0.5;
	// The creases between billows stay in shade, the crowns catch the sun.
	float crown = smoothstep(0.66, 1.0, h);
	float tone = smoothstep(0.42, 0.72, light) * mix(0.2, 1.0, crown);
	vec3 col = mix(shade_color, lit_color, tone);

	float haze = 1.0 - exp(-dist / haze_distance);
	haze = max(haze * 0.92, smoothstep(reach * 0.45, reach * 0.95, dist));
	ALBEDO = mix(col, haze_color, haze);
}
