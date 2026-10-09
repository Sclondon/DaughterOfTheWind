shader_type spatial;

// Airship plating, after the big ships in the film: matte painted metal built up in sections.
// There is no grid (the user asked for that look to go): mostly it is plain paint. A joint runs
// round the hull every so often, at uneven spacings, as a narrow darker collar with a row of fat
// rivets; each section between two joints has only a line or two along it, in different places
// from the sections either side, and is a shade lighter or darker than they are. UVs are in
// metres (see MeshKit.loft): UV.y runs along the part and UV.x around it. The fine detail fades
// with distance so a far-off ship does not sparkle.

#include "toon.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.33, 0.35, 0.37);
// Roughly how long a section is and how wide a panel, in metres.
uniform vec2 plate = vec2(26.0, 22.0);
// The hull also gets paintwork: a dark belly, a stripe at the waterline, and a row of lit portholes.
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

	// Sections along the part: every boundary is pushed a different way off the even spacing.
	float y = UV.y / plate.y;
	float row = floor(y);
	float cut = 0.15 + 0.7 * hash(vec2(row, 1.7));
	float lo = cut;
	float hi = 1.0 + 0.15 + 0.7 * hash(vec2(row + 1.0, 1.7));
	if (fract(y) < cut) {
		lo = -1.0 + 0.15 + 0.7 * hash(vec2(row - 1.0, 1.7));
		hi = cut;
		row -= 1.0;
	}
	float into = (fract(y) - lo) * plate.y;
	float along_edge = min(into, (hi - fract(y)) * plate.y);
	// Panels round the section, the same way, with a different set of cuts in every section.
	float size = plate.x * mix(0.7, 1.6, hash(vec2(row, 4.3)));
	float x = UV.x / size + hash(vec2(row, 9.1));
	float col_id = floor(x);
	float xcut = 0.2 + 0.6 * hash(vec2(col_id, row));
	float xlo = xcut;
	float xhi = 1.0 + 0.2 + 0.6 * hash(vec2(col_id + 1.0, row));
	if (fract(x) < xcut) {
		xlo = -1.0 + 0.2 + 0.6 * hash(vec2(col_id - 1.0, row));
		xhi = xcut;
		col_id -= 1.0;
	}
	float around_edge = min(fract(x) - xlo, xhi - fract(x)) * size;
	vec2 id = vec2(col_id, row);
	vec2 edge = vec2(around_edge, along_edge);

	// The lines, kept about as wide as a pixel so they stay crisp without crawling.
	vec2 px = fwidth(UV) + 0.02;
	float seam = min(smoothstep(0.0, 0.05 + px.x, edge.x), smoothstep(0.0, 0.05 + px.y, edge.y));
	// The collar either side of a joint, and the rivets along it.
	float collar = 1.0 - smoothstep(0.75, 0.75 + px.y, edge.y);
	float bolt = 1.0 - smoothstep(0.17, 0.25, length(vec2(edge.y - 0.4, (fract(UV.x / 2.4) - 0.5) * 2.4)));

	vec3 paint = base_color;
	float glow = 0.0;
	if (is_hull) {
		// Height on the hull, -1 at the keel to 1 at the top, following the keel as it sweeps up.
		float t = l_pos.z / hull_length + 0.5;
		float rel = (l_pos.y - half_height * 0.55 * t * t) / half_height;
		float line = fwidth(rel) + 0.004;
		paint = mix(paint, stripe_color, smoothstep(-0.2 - line, -0.2, rel) * (1.0 - smoothstep(-0.15, -0.15 + line, rel)));
		paint = mix(belly_color, paint, smoothstep(-0.26 - line, -0.26, rel));
		// One row of round portholes along each side.
		if (abs(l_normal.x) > 0.55 && t > 0.12 && t < 0.78) {
			float gap = 12.0;
			vec2 q = vec2((fract(l_pos.z / gap) - 0.5) * gap, (l_pos.y - half_height * 0.55 * t * t) - 0.1 * half_height);
			float d = length(q);
			float lit = step(0.4, hash(vec2(floor(l_pos.z / gap), sign(l_normal.x))));
			float hole = 1.0 - smoothstep(0.8, 1.0 + fwidth(d), d);
			paint = mix(paint, vec3(0.05), hole * mid);
			glow += hole * lit * mid;
			paint = mix(paint, paint * 0.55, smoothstep(1.5, 1.2, d) * (1.0 - hole) * near);
		}
	}

	// Each section is a shade lighter or darker than the next.
	vec3 col = paint * mix(0.9, 1.06, hash(vec2(row, 2.2))) * mix(0.985, 1.015, hash(id));
	col *= mix(1.0, 0.88, collar * mid);
	col *= mix(1.0, mix(0.6, 1.0, seam), mid);
	col = mix(col, col * 0.55, bolt * near * seam);

	ALBEDO = col;
	EMISSION = window_glow * glow * 1.4;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
