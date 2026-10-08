shader_type spatial;

// The island's ground, and the rock spires. Flat ground is grass, or a patchwork of fields where
// the mesh says there are farms (vertex colour red, see coast.gd). Steep ground is banded cliff rock.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// The spires use this shader too, but have no farm data in their vertices.
uniform bool use_farms = true;

varying vec3 w_pos;
varying vec3 w_normal;
varying float farm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	farm = COLOR.r;
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	float near = 1.0 - smoothstep(300.0, 1400.0, dist);
	float wide = texture(noise_tex, w_pos.xz / 900.0).r;
	float fine = texture(noise_tex, w_pos.xz / 130.0).r;

	vec3 col = mix(vec3(0.27, 0.47, 0.17), vec3(0.47, 0.6, 0.22), wide) * mix(0.86, 1.1, fine);

	if (use_farms) {
		// Fields: a slanted grid of plots, each its own crop, with hedges between them.
		vec2 p = mat2(vec2(0.92, 0.39), vec2(-0.39, 0.92)) * w_pos.xz / vec2(150.0, 95.0);
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
		vec2 edge = min(f, 1.0 - f) * vec2(150.0, 95.0);
		float hedge = 1.0 - smoothstep(2.5, 5.0, min(edge.x, edge.y));
		crop = mix(crop, vec3(0.16, 0.3, 0.12), hedge);
		col = mix(col, crop * mix(0.92, 1.06, fine), smoothstep(0.35, 0.6, farm));
	}

	// Cliffs: rock wherever the ground is steep, laid down in bands.
	float steep = 1.0 - smoothstep(0.6, 0.8, w_normal.y + (fine - 0.5) * 0.2);
	float band = smoothstep(0.25, 0.75, sin(w_pos.y * 0.33 + wide * 3.0 + fine * 1.5) * 0.5 + 0.5);
	vec3 rock = mix(vec3(0.74, 0.65, 0.5), vec3(0.88, 0.8, 0.64), band) * mix(0.84, 1.05, fine);
	col = mix(col, rock, steep);
	// Wet and dark where the sea washes the foot of the cliffs.
	col = mix(col * 0.55, col, smoothstep(-2.0, 7.0, w_pos.y));

	ALBEDO = col;
	ROUGHNESS = 0.95;
}
