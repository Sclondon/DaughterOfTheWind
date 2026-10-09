shader_type spatial;

// The walls of the cliff cities' houses: a MultiMesh of unit boxes, each stretched to its house
// and carrying its plaster colour. Rows of windows are drawn on the walls, dark panes with a
// share of them lit warm from inside. They are sized in metres, so a tall house gets more rows,
// and they fade out before they are too small to draw cleanly.

#include "toon.gdshaderinc"

varying vec3 m_pos;
varying vec3 m_norm;
varying vec3 size;
varying float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	m_pos = VERTEX * size;
	m_norm = NORMAL;
	seed = fract(dot(MODEL_MATRIX[3].xz, vec2(0.137, 0.731)));
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 glow = vec3(0.0);
	if (abs(m_norm.y) < 0.5 && size.y > 5.0) {
		bool side = abs(m_norm.x) > 0.5;
		float across = side ? m_pos.z : m_pos.x;
		float wide = side ? size.z : size.x;
		// Rows are counted down from the eaves, so the top storey is always whole.
		float down = size.y * 0.5 - m_pos.y;
		float cols = max(floor(wide / 3.6), 1.0);
		vec2 g = vec2((across / wide + 0.5) * cols, down / 3.8);
		vec2 id = floor(g);
		vec2 f = fract(g);
		float pane = step(0.3, f.x) * step(f.x, 0.7) * step(0.28, f.y) * step(f.y, 0.72);
		float pick = hash(id + seed * 91.0 + (side ? 17.0 : 0.0));
		float show = pane * step(0.22, pick);
		float clear = 1.0 - smoothstep(0.16, 0.45, fwidth(g.x) + fwidth(g.y));
		float lit = step(0.72, pick);
		base = mix(base, mix(vec3(0.15, 0.2, 0.3), vec3(1.0, 0.8, 0.46), lit), show * clear);
		glow = vec3(1.0, 0.66, 0.28) * lit * show * clear * 0.8;
		base *= mix(0.95, 1.0, clear);
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow;
}
