shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

// The painted backdrop inland of the cliffs, in the manner of a film's background painting:
// four flat cut-outs standing one behind the other, each a wall parallel to the coast.
//   1. a wood of round-crowned trees with giant old trees towering out of it
//   2. green hills patched with woods
//   3. a range of grey-blue mountains
//   4. a far, higher range under snow
// Each is drawn in a few flat tones, lit from the sun's side, and paler and bluer the further
// off it stands.
//
// The mesh is only a piece of a big sphere round the glider (coast.gd), there to give the shader
// pixels to fill. For each pixel the shader works out where its line of sight crosses each
// wall (they stand at the world x positions in `planes`) and paints the nearest one that has
// something there, so the walls keep their places in the world as the glider moves.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 sun_dir = vec3(-0.5, 0.55, -0.67);
uniform vec3 haze_color : source_color = vec3(0.73, 0.85, 0.96);
uniform float haze_distance = 14000.0;
// World x of the wood, the hills, the mountains and the far range.
uniform vec4 planes = vec4(7000.0, 10000.0, 15000.0, 23000.0);
// The height of the tableland the wood stands on.
uniform float ground = 870.0;

varying vec3 w_pos;

float hash11(float n) {
	return fract(sin(mod(n, 4096.0) * 127.1) * 43758.5453);
}

// Smooth noise (0..1) along a line, and leafy cell noise over a patch.
float smooth_at(float u, float row) {
	return textureLod(noise_tex, vec2(u, row), 0.0).r;
}

float leafy(vec2 p) {
	return textureLod(noise_tex, p, 0.0).g;
}

// Which of three tones a point on a round clump of leaves gets: 2 lit, 1 middle, 0 shade.
// `q` is the point within the clump (-1..1), `l2` the way to the sun on the wall.
vec3 clump(vec2 q, vec2 l2, float ragged, vec3 dark, vec3 mid, vec3 light) {
	float s = dot(q, l2) + ragged;
	return s > 0.3 ? light : (s > -0.4 ? mid : dark);
}

// 1. The wood and the giant trees. p.x runs along the coast, p.y is height above the tableland.
bool wood(vec2 p, vec2 l2, out vec3 col) {
	float y = p.y - (smooth_at(p.x / 9000.0, 0.13) - 0.5) * 160.0;
	float ragged = (leafy(p / 520.0) - 0.5) * 0.7;
	bool got = false;
	col = vec3(0.07, 0.2, 0.13);
	if (y < 45.0) {
		got = true;
	}
	// The wood: a row of crowns, each a disc.
	if (y < 420.0) {
		float order = -1.0;
		for (int i = -1; i <= 1; i++) {
			float id = floor(p.x / 250.0) + float(i);
			float r = 120.0 + 95.0 * hash11(id);
			float c = (id + 0.5 + (hash11(id + 31.7) - 0.5) * 0.6) * 250.0;
			float base = 20.0 + 120.0 * hash11(id + 77.3);
			vec2 q = vec2(p.x - c, y - base) / r;
			float front = hash11(id + 5.5);
			if (dot(q, q) < 1.0 + ragged * 0.35 && front > order) {
				order = front;
				got = true;
				col = clump(q, l2, ragged, vec3(0.07, 0.2, 0.13), vec3(0.14, 0.33, 0.14), vec3(0.3, 0.48, 0.17));
			}
		}
	}
	// The giants: a great flared trunk and a dome of clumps, a few to every wood.
	for (int i = 0; i <= 1; i++) {
		float id = floor(p.x / 2100.0 - 0.5) + float(i);
		if (hash11(id + 400.0) > 0.82) {
			continue;
		}
		float size = 0.7 + 0.75 * hash11(id + 2.2);
		float c = (id + 0.5 + (hash11(id + 9.1) - 0.5) * 0.45) * 2100.0;
		float trunk_h = 400.0 * size;
		float reach = 340.0 * size;
		vec2 t = vec2(p.x - c, y);
		if (abs(t.x) > reach * 1.5 || t.y > trunk_h + reach * 1.2) {
			continue;
		}
		float up = clamp(t.y / trunk_h, 0.0, 1.0);
		float girth = 30.0 * size * (1.0 + 1.7 * pow(1.0 - up, 3.0) + 1.3 * pow(up, 4.0));
		float lean = sin(up * 2.6 + id) * 14.0 * size;
		if (t.y < trunk_h + reach * 0.2 && abs(t.x - lean) < girth) {
			got = true;
			col = (t.x - lean) * l2.x > -girth * 0.25 ? vec3(0.46, 0.36, 0.26) : vec3(0.25, 0.2, 0.19);
		}
		// Two boughs reaching out under the crown.
		float bough = abs(t.y - (trunk_h * 0.82 + abs(t.x) * 0.42));
		if (abs(t.x) < reach * 0.62 && bough < 13.0 * size) {
			got = true;
			col = vec3(0.28, 0.22, 0.19);
		}
		for (int j = 0; j < 10; j++) {
			float fj = float(j);
			float rnd = hash11(id * 13.0 + fj);
			vec2 cc;
			float cr;
			if (j < 7) {
				// A ring of clumps round the edge of the dome.
				float a = 3.14159 * (fj + 0.5) / 7.0;
				cc = vec2(cos(a) * reach * (0.62 + 0.25 * rnd), trunk_h + sin(a) * reach * 0.42 + reach * 0.05);
				cr = reach * (0.34 + 0.16 * rnd);
			} else {
				// And the big ones heaped in the middle, last so they sit in front.
				cc = vec2((fj - 8.0) * reach * 0.36, trunk_h + reach * (0.36 + 0.16 * rnd));
				cr = reach * (0.46 + 0.12 * rnd);
			}
			vec2 q = (t - cc) / cr;
			if (dot(q, q) < 1.0 + ragged * 0.3) {
				got = true;
				col = clump(q, l2, ragged, vec3(0.09, 0.25, 0.12), vec3(0.2, 0.42, 0.14), vec3(0.47, 0.62, 0.2));
			}
		}
	}
	return got;
}

// 2. The hills: p.y is height above the sea.
float hill_top(float u) {
	return 1000.0 + 1000.0 * smooth_at(u / 17000.0, 0.31) + 340.0 * smooth_at(u / 4300.0, 0.57);
}

bool hills(vec2 p, vec2 l2, out vec3 col) {
	float top = hill_top(p.x);
	// Trees along the skyline make it lumpy.
	float fringe = 70.0 * leafy(vec2(p.x / 900.0, 0.8));
	if (p.y > top + fringe) {
		return false;
	}
	// Lit where the hill faces the sun's side.
	float rise = hill_top(p.x + 260.0) - top;
	bool sunny = rise * -l2.x > -25.0 + (top - p.y) * 0.12;
	col = sunny ? vec3(0.4, 0.57, 0.25) : vec3(0.25, 0.43, 0.25);
	// Woods: dark patches with lit tops.
	vec2 at = p / vec2(1900.0, 1100.0);
	float woods = leafy(at);
	if (woods > 0.5 || p.y > top) {
		float toward = leafy(at + l2 * vec2(0.03, 0.05));
		col = toward < woods - 0.04 ? vec3(0.2, 0.4, 0.17) : vec3(0.1, 0.26, 0.16);
	}
	return true;
}

// 3 and 4. Mountains: a jagged skyline, shaded where a peak on the sun's side stands in the light.
float skyline(float u, float row, float scale, float base, float amp) {
	float a = 1.0 - abs(2.0 * smooth_at(u / (scale * 3.5), row) - 1.0);
	float b = 1.0 - abs(2.0 * smooth_at(u / scale, row + 0.21) - 1.0);
	float c = smooth_at(u / (scale * 0.27), row + 0.47);
	return base + amp * (0.5 * a * a + 0.34 * b * (0.4 + 0.6 * a) + 0.16 * c);
}

bool mountains(vec2 p, vec2 l2, float row, float scale, float base, float amp, float snow_line, out vec3 col) {
	float top = skyline(p.x, row, scale, base, amp);
	if (p.y > top) {
		return false;
	}
	// Is a higher part of the range, toward the sun, in the way?
	float toward = -sign(l2.x);
	bool shade = false;
	for (int i = 1; i <= 3; i++) {
		float reach = scale * 0.11 * float(i);
		if (skyline(p.x + toward * reach, row, scale, base, amp) - reach * 0.55 > p.y) {
			shade = true;
		}
	}
	float ragged = (leafy(p / vec2(scale * 1.2, scale * 0.8)) - 0.5);
	float snow = p.y - snow_line - ragged * amp * 0.16 - (top - p.y) * 0.25;
	float trees = base + amp * 0.2 + ragged * amp * 0.1 - p.y;
	if (snow > 0.0) {
		col = shade ? vec3(0.66, 0.75, 0.92) : vec3(1.0, 0.99, 0.96);
	} else if (trees > 0.0) {
		col = shade ? vec3(0.17, 0.3, 0.27) : vec3(0.3, 0.45, 0.27);
	} else {
		col = shade ? vec3(0.36, 0.41, 0.56) : vec3(0.63, 0.6, 0.58);
	}
	return true;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(w_pos - cam);
	if (dir.x < 0.003) {
		discard;
	}
	// The way to the sun, flattened onto the walls (along the coast, up).
	vec2 l2 = normalize(vec2(sun_dir.z, sun_dir.y));
	vec3 col = vec3(0.0);
	float t = 0.0;
	bool got = false;

	t = (planes.x - cam.x) / dir.x;
	vec3 at = cam + dir * t;
	if (at.y - ground < 1300.0) {
		got = wood(vec2(at.z, at.y - ground), l2, col);
	}
	if (!got) {
		t = (planes.y - cam.x) / dir.x;
		at = cam + dir * t;
		if (at.y < 2500.0) {
			got = hills(at.zy, l2, col);
		}
	}
	if (!got) {
		t = (planes.z - cam.x) / dir.x;
		at = cam + dir * t;
		if (at.y < 5000.0) {
			got = mountains(at.zy, l2, 0.07, 6200.0, 900.0, 3700.0, 3350.0, col);
		}
	}
	if (!got) {
		t = (planes.w - cam.x) / dir.x;
		at = cam + dir * t;
		if (at.y < 9000.0) {
			got = mountains(at.zy, l2, 0.63, 9500.0, 1300.0, 6600.0, 3700.0, col);
		}
	}
	if (!got) {
		discard;
	}
	// (Far along the coast the flats melt away into the haze altogether.)
	float haze = max(1.0 - exp(-t / haze_distance), smoothstep(18000.0, 38000.0, t));
	ALBEDO = mix(col, haze_color, haze);
}
