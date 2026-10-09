shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// One puff of a cloud: a unit sphere, drawn thousands of times through a MultiMesh.
// It is solid (no blending, so nothing needs sorting) and gets its fluff three ways:
//  - the sphere is swollen into soft round billows by noise;
//  - it is lit in flat tones using a normal that leans hard toward "away from the middle of
//    the cloud", so a heap of puffs shades as one mass and not as a pile of separate balls;
//  - its rim is feathered: a thin band at the silhouette thins out, wider in some places than
//    others (slow noise, never a nibbled edge: that looked torn, not fluffy).
// On top of the tones some puffs carry a painted curl, a brush-stroke spiral in the manner of
// Okami or The Wind Waker (the same drawing as the explosion puffs in shaders/burst).
//
// Per puff, from the cloud manager:
//   INSTANCE_CUSTOM = (seed, where the flat base cuts it in sphere units, height in its cloud 0..1,
//                      kind: 0 a puff of the heap, 1 a little tuft on its edge)
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
// How much of the painted curls to draw (0 none).
uniform float curls = 1.0;

varying vec3 w_pos;
varying vec3 w_normal;
varying vec3 l_dir;
varying vec4 puff;
varying vec3 core_dir;
varying float crease;
varying float feather;

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
	vec3 v = dir * (1.0 + (big - 0.5) * 0.3 + (small - 0.5) * 0.06 + (dome - 0.55) * 0.3);
	// Cumulus sit on a flat base: squash whatever hangs below it.
	if (v.y < puff.y) {
		v.y = mix(v.y, puff.y, 0.82);
	}
	// How wide the soft rim is just here: slow noise round the puff, drifting a little.
	feather = textureLod(noise_tex, dir.zx * 0.21 + dir.y * 0.13 + vec2(seed * 2.3, seed) + TIME * 0.004, 0.0).r;
	VERTEX = v;
	NORMAL = dir;
	l_dir = dir;
	w_pos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	w_normal = normalize(mat3(MODEL_MATRIX) * dir);
}

float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// One arm of a spiral round the point `axis` on the puff, as a brush stroke (0..1).
float curl(vec3 d, vec3 axis, float seed, float size) {
	vec3 side = normalize(cross(axis, vec3(0.31, 0.9, 0.3)));
	vec3 up = cross(side, axis);
	vec2 q = vec2(dot(d, side), dot(d, up)) / size;
	float r = length(q);
	float a = atan(q.y, q.x);
	float arm = sin(a + log(r + 0.05) * 4.4 + seed * 6.283);
	// The stroke swells in the middle of its run and tapers to nothing at both ends.
	float body = smoothstep(0.1, 0.3, r) * (1.0 - smoothstep(0.62, 0.95, r));
	float stroke = smoothstep(0.93 - 0.1 * body, 0.97 - 0.06 * body, arm) * body;
	return stroke * smoothstep(0.15, 0.4, dot(d, axis));
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_eye);
	vec3 v = to_eye / dist;
	vec3 n = normalize(w_normal);
	float facing = dot(n, v);

	float fade = (1.0 - smoothstep(fade_start, fade_end, dist)) * smoothstep(3.0, 28.0, dist);
	// The feathered rim. Tufts are nearly all rim.
	float band = mix(0.05, 0.3, smoothstep(0.35, 0.7, feather)) + puff.w * 0.12;
	fade *= smoothstep(0.0, band, facing);
	if (fade < 0.999 && fade < dither(FRAGCOORD.xy)) {
		discard;
	}

	// Mostly the cloud's own roundness, a little of the puff's: the heap reads as one mass.
	vec3 soft = normalize(mix(n, core_dir, 0.68));
	float light = dot(soft, sun_dir) * 0.5 + 0.5;
	// Undersides and the low parts of a cloud sit in its own shadow.
	light *= mix(0.62, 1.0, smoothstep(-0.7, 0.4, mix(n.y, core_dir.y, 0.35)));
	light *= mix(0.78, 1.0, puff.z);
	light *= mix(0.8, 1.0, smoothstep(0.25, 0.7, crease));
	// Cel shading: lit, a half tone, or shade.
	float tone = smoothstep(0.3, 0.36, light) * 0.6 + smoothstep(0.54, 0.6, light) * 0.4;
	vec3 col = mix(shade_color, lit_color, tone);
	col = mix(col, shade_color * 0.84, (1.0 - tone) * smoothstep(0.1, -0.8, n.y) * 0.7);

	// Painted curls: two to a puff, on about two puffs in three, fading with distance.
	float seed = puff.x;
	float paint = curls * step(fract(seed * 7.31), 0.66) * (1.0 - puff.w) * (1.0 - smoothstep(1800.0, 4200.0, dist));
	if (paint > 0.0) {
		vec3 d = normalize(l_dir);
		float t = seed * 39.0;
		vec3 a1 = normalize(vec3(cos(t), 0.45, sin(t)));
		vec3 a2 = normalize(vec3(cos(t + 2.6), 0.1, sin(t + 2.6)));
		float stroke = max(curl(d, a1, seed, 0.78), curl(d, a2, seed + 0.37, 0.55)) * paint;
		// A blue stroke on the white, a paler one in the shade.
		vec3 ink = mix(mix(shade_color, lit_color, 0.4), mix(shade_color, lit_color, 0.22), tone);
		col = mix(col, ink, stroke * 0.85);
	}

	// A silver lining when the sun is behind the cloud.
	float against = pow(max(dot(-v, sun_dir), 0.0), 5.0);
	col += rim_color * against * pow(1.0 - facing, 2.0) * 0.7;

	float haze = 1.0 - exp(-dist / haze_distance);
	ALBEDO = mix(col, haze_color, haze * 0.92);
}
