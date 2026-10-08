shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// One puff of a cloud: a unit sphere, drawn thousands of times through a MultiMesh.
// It is solid (no blending, so nothing needs sorting) and gets its fluff three ways: the sphere is
// lumped up by noise, its outline is nibbled away by noise, and it is lit in two soft tones using
// a normal that leans toward "away from the middle of the cloud" so the whole cloud shades as one.
//
// Per puff, from the cloud manager:
//   INSTANCE_CUSTOM = (seed, where the flat base cuts it in sphere units, height in its cloud 0..1, spare)
//   COLOR.rgb       = direction from the cloud's core to this puff, packed 0..1

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 shade_color : source_color = vec3(0.62, 0.7, 0.84);
uniform vec3 haze_color : source_color = vec3(0.8, 0.88, 0.95);
uniform vec3 rim_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float haze_distance = 6000.0;
// Puffs dissolve between these distances, which hides cells streaming in and out.
uniform float fade_start = 3000.0;
uniform float fade_end = 3500.0;

varying vec3 w_pos;
varying vec3 w_normal;
varying vec3 l_dir;
varying vec4 puff;
varying vec3 core_dir;
varying float crease;

// Cell-noise domes (green channel) wrapped round the sphere from three sides.
float domes(vec3 dir, float seed) {
	vec3 w = dir * dir;
	float x = textureLod(noise_tex, dir.zy * 0.2 + seed, 0.0).g;
	float y = textureLod(noise_tex, dir.xz * 0.2 + seed * 1.7, 0.0).g;
	float z = textureLod(noise_tex, dir.xy * 0.2 + seed * 2.9, 0.0).g;
	float d = x * w.x + y * w.y + z * w.z;
	return 1.0 - d * d;
}

void vertex() {
	puff = INSTANCE_CUSTOM;
	core_dir = COLOR.rgb * 2.0 - 1.0;
	vec3 dir = normalize(VERTEX);
	float seed = puff.x;
	float big = textureLod(noise_tex, dir.xz * 0.33 + vec2(seed, seed * 1.7) + TIME * 0.003, 0.0).r;
	float small = textureLod(noise_tex, dir.xy * 0.85 + vec2(seed * 3.1, seed * 0.7), 0.0).r;
	// Smaller round lumps on top: the cauliflower look. The creases between them shade darker.
	float dome = domes(dir, seed);
	crease = dome;
	vec3 v = dir * (1.0 + (big - 0.5) * 0.55 + (small - 0.5) * 0.15 + (dome - 0.6) * 0.3);
	// Cumulus sit on a flat base: squash whatever hangs below it.
	if (v.y < puff.y) {
		v.y = mix(v.y, puff.y, 0.82);
	}
	VERTEX = v;
	NORMAL = dir;
	l_dir = dir;
	w_pos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	w_normal = normalize(mat3(MODEL_MATRIX) * dir);
}

float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_eye);
	vec3 v = to_eye / dist;
	vec3 n = normalize(w_normal);
	float facing = dot(n, v);

	// Nibble the outline so it is not a clean circle.
	float grain = texture(noise_tex, l_dir.xz * 1.1 + l_dir.y * 0.6 + puff.x * 5.0).r;
	if (facing < 0.06 + grain * 0.42) {
		discard;
	}
	float fade = (1.0 - smoothstep(fade_start, fade_end, dist)) * smoothstep(3.0, 28.0, dist);
	if (fade < 0.999 && fade < dither(FRAGCOORD.xy)) {
		discard;
	}

	vec3 soft = normalize(mix(n, core_dir, 0.45));
	float light = dot(soft, sun_dir) * 0.5 + 0.5;
	// Undersides and the low parts of a cloud sit in its own shadow.
	light *= mix(0.6, 1.0, smoothstep(-0.7, 0.4, n.y));
	light *= mix(0.78, 1.0, puff.z);
	light *= mix(0.72, 1.0, smoothstep(0.25, 0.7, crease));
	float tone = smoothstep(0.2, 0.68, light);
	vec3 col = mix(shade_color, lit_color, tone);
	col = mix(col, shade_color * 0.84, (1.0 - tone) * smoothstep(0.1, -0.8, n.y) * 0.7);
	// A silver lining when the sun is behind the cloud.
	float against = pow(max(dot(-v, sun_dir), 0.0), 5.0);
	col += rim_color * against * pow(1.0 - facing, 2.0) * 0.7;

	float haze = 1.0 - exp(-dist / haze_distance);
	ALBEDO = mix(col, haze_color, haze * 0.92);
}
