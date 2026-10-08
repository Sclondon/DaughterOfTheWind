shader_type spatial;

// The plain cel-shaded watercolour material, for anything that is one colour: the glider, the
// riders, houses, towers, trees, fighters. scripts/toon.gd makes these.

#include "toon.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
// Metres of surface one tile of the watercolour texture covers.
uniform float wash_size = 2.0;
// True paints by world position (for things that stay put, so neighbours share one wash);
// false by the model's own space (for things that move).
uniform bool world_wash = false;
// True multiplies in the vertex colour (the per-copy colour of a MultiMesh).
uniform bool use_vertex_color = false;
uniform vec3 glow : source_color = vec3(0.0);

varying vec3 paint_pos;
varying vec3 paint_normal;

void vertex() {
	if (world_wash) {
		paint_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		paint_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	} else {
		paint_pos = VERTEX;
		paint_normal = NORMAL;
	}
}

void fragment() {
	vec3 base = albedo;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	ALBEDO = wash(base, paint_pos, normalize(paint_normal), wash_size);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = glow;
}
