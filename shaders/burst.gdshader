shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// A cartoon explosion puff, after The Wind Waker: a flat cloud with a scalloped edge, a dark
// outline and a curl drawn inside it, turned to face the camera. It starts hot yellow, goes
// orange, then cools to lilac smoke that hollows out from the middle and is gone. Solid colour
// and cut-out edges only, no blending.
//
// Per puff, from flak.gd: INSTANCE_CUSTOM = (age 0..1, seed, kind (0 smoke, 1 the first flash), spin)

varying vec4 puff;
varying vec2 p;
varying float depth;

float dither(vec2 at) {
	return fract(52.9829189 * fract(dot(at, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	puff = INSTANCE_CUSTOM;
	p = UV * 2.0 - 1.0;
	// Face the camera, keeping the puff's size.
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	// A puff right in the lens would hide everything, so it thins out close to the camera.
	if (smoothstep(7.0, 22.0, depth) < dither(FRAGCOORD.xy) + 0.02) {
		discard;
	}
	float age = puff.x;
	float seed = puff.y;
	float turn = seed * 6.283 + puff.w * age;
	vec2 q = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * p;
	float r = length(q);
	float a = atan(q.y, q.x);

	if (puff.z > 0.5) {
		// The flash: an eight-pointed star that shrinks away at once.
		float star = (0.45 + 0.55 * pow(abs(cos(a * 4.0)), 3.0)) * (1.0 - age);
		if (r > star) {
			discard;
		}
		ALBEDO = mix(vec3(1.0, 1.0, 0.9), vec3(1.0, 0.85, 0.3), smoothstep(0.0, star, r));
	} else {
		// A lumpy cloud outline that shrinks a little at the very end.
		float edge = (0.8 + 0.11 * cos(a * 5.0 + seed * 9.0) + 0.06 * cos(a * 9.0 - seed * 5.0)) * (1.0 - smoothstep(0.8, 1.0, age) * 0.5);
		if (r > edge) {
			discard;
		}
		// It hollows out from the middle as it thins.
		float hole = (age - 0.5) * 1.9 + 0.1 * cos(a * 3.0 + seed * 4.0);
		if (r < hole) {
			discard;
		}
		vec3 hot = mix(vec3(1.0, 0.93, 0.55), vec3(1.0, 0.55, 0.16), smoothstep(0.05, 0.3, age));
		vec3 smoke = mix(vec3(0.46, 0.38, 0.55), vec3(0.8, 0.77, 0.86), smoothstep(0.45, 1.0, age));
		vec3 col = mix(hot, smoke, smoothstep(0.22, 0.5, age));
		// Two flat tones, lit from the upper right.
		col *= mix(0.74, 1.0, step(-0.15, dot(q, vec2(0.6, 0.8)) / max(r, 0.01) * r));
		// The curl: one arm of a spiral, drawn as a dark stroke.
		float curl = sin(a + log(r + 0.04) * 4.6 + seed * 6.283);
		float stroke = smoothstep(0.8, 0.88, curl) * smoothstep(0.08, 0.2, r) * (1.0 - smoothstep(edge - 0.22, edge - 0.12, r));
		col = mix(col, col * 0.5, stroke);
		// The outline.
		col = mix(col, col * 0.45, smoothstep(edge - 0.09, edge - 0.06, r));
		col = mix(col, col * 0.45, (1.0 - smoothstep(hole + 0.04, hole + 0.07, r)) * step(0.0, hole));
		ALBEDO = col;
	}
}
