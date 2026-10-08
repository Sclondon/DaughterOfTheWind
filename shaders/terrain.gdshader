shader_type spatial;

// The island's ground, and the rock spires. Flat ground is grass, or a patchwork of fields where
// the mesh says there are farms (vertex colour red, see coast.gd), or beach sand (green). Steep
// ground is banded cliff rock.

#include "toon.gdshaderinc"

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// The spires use this shader too, but have no farm data in their vertices.
uniform bool use_farms = true;
// Where the valley meets the sea (z). The stream below repeats coast.gd's river_z().
uniform float valley_z = 0.0;

varying vec3 w_pos;
varying vec3 w_normal;
varying float farm;
varying float sand;
varying float stream;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	farm = COLOR.r;
	sand = COLOR.g;
	stream = COLOR.b;
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	float near = 1.0 - smoothstep(300.0, 1400.0, dist);
	float wide = texture(noise_tex, w_pos.xz / 900.0).r;
	float fine = texture(noise_tex, w_pos.xz / 130.0).r;

	vec3 col = mix(vec3(0.27, 0.47, 0.17), vec3(0.47, 0.6, 0.22), wide) * mix(0.86, 1.1, fine);

	// Flower meadows: drifts of colour across the grass, and the flowers themselves close to.
	float drift = smoothstep(0.52, 0.66, texture(noise_tex, w_pos.xz / 310.0 + vec2(0.4, 0.1)).r);
	float which = texture(noise_tex, w_pos.xz / 700.0 + vec2(0.7, 0.3)).r;
	vec3 bloom = which < 0.42 ? vec3(0.95, 0.85, 0.3) : (which < 0.56 ? vec3(0.92, 0.55, 0.7) : vec3(0.93, 0.93, 0.85));
	col = mix(col, bloom, drift * 0.28);
	vec2 cell = floor(w_pos.xz / 2.2);
	float speck = step(0.72, hash(cell)) * (1.0 - smoothstep(0.1, 0.3, length(fract(w_pos.xz / 2.2) - 0.5)));
	col = mix(col, bloom * 1.1, speck * drift * near);

	if (use_farms) {
		// Fields: a slanted grid of plots, each its own crop, with hedges between them.
		// (The plots are pulled about a little, so they look hand-drawn, not ruled.)
		vec2 wobble = (texture(noise_tex, w_pos.xz / 330.0).rg - 0.5) * 34.0;
		vec2 p = mat2(vec2(0.92, 0.39), vec2(-0.39, 0.92)) * (w_pos.xz + wobble) / vec2(64.0, 40.0);
		p.x += floor(p.y) * 0.37;
		vec2 id = floor(p);
		vec2 f = fract(p);
		float kind = hash(id);
		vec3 crop = vec3(0.56, 0.68, 0.3);
		if (kind < 0.3) {
			crop = vec3(0.8, 0.69, 0.33);
		} else if (kind < 0.52) {
			crop = vec3(0.36, 0.56, 0.22);
		} else if (kind < 0.7) {
			crop = vec3(0.5, 0.37, 0.25);
		}
		// Furrows, each plot ploughed its own way.
		float turn = hash(id + 3.0) * 3.14;
		float rows = sin(dot(w_pos.xz, vec2(cos(turn), sin(turn))) * 1.1);
		crop *= 1.0 + rows * 0.06 * near;
		vec2 edge = min(f, 1.0 - f) * vec2(64.0, 40.0);
		float hedge = 1.0 - smoothstep(1.2, 2.6, min(edge.x, edge.y));
		crop = mix(crop, vec3(0.16, 0.3, 0.12), hedge);
		col = mix(col, crop * mix(0.92, 1.06, fine), smoothstep(0.35, 0.6, farm));
	}

	if (use_farms) {
		// The stream: a ribbon of water down the valley, with darker, greener banks.
		float river_z = valley_z + 260.0 * sin(w_pos.x / 1700.0 + 0.5) + 55.0 * sin(w_pos.x / 160.0 + 1.0);
		float from_stream = abs(w_pos.z - river_z) + (fine - 0.5) * 7.0;
		col = mix(col, vec3(0.2, 0.42, 0.16), (1.0 - smoothstep(10.0, 24.0, from_stream)) * stream * 0.7);
		float glint = step(0.62, texture(noise_tex, w_pos.xz / 23.0 + vec2(TIME * 0.05, 0.0)).r);
		vec3 water = mix(vec3(0.2, 0.5, 0.72), vec3(0.62, 0.84, 0.92), glint * 0.6);
		col = mix(col, water, (1.0 - smoothstep(6.0, 8.0, from_stream)) * stream);
		col = mix(col, vec3(0.9, 0.82, 0.62) * mix(0.93, 1.05, fine), smoothstep(0.3, 0.7, sand));
	}

	// Cliffs: rock wherever the ground is steep, laid down in bands.
	float steep = 1.0 - smoothstep(0.6, 0.8, w_normal.y + (fine - 0.5) * 0.2);
	float band = smoothstep(0.25, 0.75, sin(w_pos.y * 0.11 + wide * 4.0 + fine * 2.0) * 0.5 + 0.5);
	vec3 rock = mix(vec3(0.76, 0.66, 0.5), vec3(0.86, 0.78, 0.62), band) * mix(0.84, 1.05, fine);
	col = mix(col, rock, steep);
	// Wet and dark where the sea washes the foot of the cliffs.
	col = mix(col * 0.55, col, smoothstep(-2.0, 7.0, w_pos.y));

	// Two washes: a wide one over the whole country, and a closer one.
	col = wash(col, w_pos, w_normal, 520.0);
	ALBEDO = mix(col, wash(col, w_pos, w_normal, 90.0), near * 0.6);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
