shader_type spatial;

// Airship plating: staggered riveted metal plates, each a slightly different tone, with dark seams
// and rain streaks. UVs are in metres (see MeshKit.loft), so the plates are the same size on every
// part. The fine detail fades with distance so a far-off ship does not sparkle.

#include "toon.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.33, 0.35, 0.37);
uniform vec3 streak_color : source_color = vec3(0.2, 0.17, 0.14);
uniform vec2 plate = vec2(6.5, 4.0);
// The hull also gets paintwork: a dark belly, a stripe at the waterline, and rows of lit portholes.
uniform bool is_hull = false;
uniform float hull_length = 240.0;
uniform float half_height = 17.0;
uniform vec3 belly_color : source_color = vec3(0.13, 0.13, 0.14);
uniform vec3 stripe_color : source_color = vec3(0.55, 0.16, 0.1);
uniform vec3 window_glow : source_color = vec3(1.0, 0.8, 0.45);

varying vec3 w_pos;
varying vec3 l_pos;
varying vec3 l_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	l_pos = VERTEX;
	l_normal = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - w_pos);
	float near = 1.0 - smoothstep(250.0, 900.0, dist);
	float mid = 1.0 - smoothstep(1200.0, 3200.0, dist);

	vec2 uv = UV / plate;
	uv.x += floor(uv.y) * 0.5;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	float tone = hash(id);

	// Seams, kept about as wide as a pixel so they stay crisp without crawling.
	vec2 edge = min(f, 1.0 - f) * plate;
	vec2 px = fwidth(UV) + 0.02;
	float seam = min(smoothstep(0.0, 0.07 + px.x, edge.x), smoothstep(0.0, 0.07 + px.y, edge.y));

	// A row of rivets just inside every seam.
	float inset = min(edge.x, edge.y);
	vec2 dot_uv = fract(UV / 0.55) - 0.5;
	float rivet = (1.0 - smoothstep(0.14, 0.24, length(dot_uv))) * smoothstep(0.12, 0.2, inset) * (1.0 - smoothstep(0.45, 0.6, inset));

	vec3 paint = base_color;
	float glow = 0.0;
	if (is_hull) {
		// Height on the hull, -1 at the keel to 1 at the top, following the keel as it sweeps up.
		float t = l_pos.z / hull_length + 0.5;
		float rel = (l_pos.y - half_height * 0.55 * t * t) / half_height;
		float line = fwidth(rel) + 0.004;
		paint = mix(paint, stripe_color, smoothstep(-0.2 - line, -0.2, rel) * (1.0 - smoothstep(-0.13, -0.13 + line, rel)));
		paint = mix(belly_color, paint, smoothstep(-0.26 - line, -0.26, rel));
		// Two rows of round portholes along each side.
		if (abs(l_normal.x) > 0.55 && t > 0.1 && t < 0.8) {
			for (int row = 0; row < 2; row++) {
				float row_y = (row == 0 ? 0.02 : 0.24) * half_height;
				vec2 q = vec2((fract(l_pos.z / 8.0 + float(row) * 0.5) - 0.5) * 8.0, (l_pos.y - half_height * 0.55 * t * t) - row_y);
				float d = length(q);
				float lit = step(0.35, hash(vec2(floor(l_pos.z / 8.0 + float(row) * 0.5), float(row) + sign(l_normal.x))));
				float hole = 1.0 - smoothstep(0.8, 1.0 + fwidth(d), d);
				paint = mix(paint, vec3(0.05), hole * mid);
				glow += hole * lit * mid;
				paint = mix(paint, paint * 0.55, smoothstep(1.5, 1.2, d) * (1.0 - hole) * near);
			}
		}
	}

	vec3 col = paint * mix(0.86, 1.07, tone);
	// Streaks run around the hull from the top, down the plates.
	float streak = hash(vec2(floor(UV.y / 1.3), 3.0));
	streak = smoothstep(0.72, 1.0, streak) * (0.5 + 0.5 * hash(id + 7.0));
	col = mix(col, streak_color, streak * 0.45 * mid);
	col *= mix(1.0, mix(0.62, 1.0, seam), mid);
	col = mix(col, col * 1.5 + 0.03, rivet * near * 0.6);

	ALBEDO = col;
	EMISSION = window_glow * glow * 1.4;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
