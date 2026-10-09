shader_type spatial;

// The plain cel-shaded material, for anything that is one flat colour: the glider, the riders,
// houses, towers, trees, fighters. scripts/toon.gd makes these.

#include "toon.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
// True multiplies in the vertex colour (the per-copy colour of a MultiMesh).
uniform bool use_vertex_color = false;
uniform vec3 glow : source_color = vec3(0.0);
// Above 0 gives the surface the faint, even speckle of an eggshell.
uniform float eggshell = 0.0;
// Above 0 gives woven cloth a faint weave, wherever the vertex colour's alpha says it is cloth.
uniform float weave = 0.0;

varying vec3 model_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	vec3 base = albedo;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	if (eggshell > 0.0) {
		// Tiny pits, a few millimetres across, only just darker than the shell.
		vec3 cell = floor(model_pos * 420.0);
		base *= 1.0 - eggshell * 0.03 * step(0.85, hash(cell));
	}
	if (weave > 0.0) {
		// Fine crossed threads. They fade out before they are too small to draw cleanly.
		vec3 thread = model_pos * 520.0;
		float fine = 1.0 - smoothstep(0.5, 1.4, fwidth(thread.x) + fwidth(thread.y) + fwidth(thread.z));
		float cross = sin(thread.x + thread.z) * sin(thread.y);
		base *= 1.0 - weave * COLOR.a * 0.1 * fine * smoothstep(-0.2, 0.6, cross);
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow;
}
