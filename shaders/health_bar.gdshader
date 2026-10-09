shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// An airship's health bar (see airship.gd): a strip floating over the ship that always faces
// the camera. The part it still has is in its side's colour; the part it has lost is dark.

uniform float fill = 1.0;
uniform vec3 tint : source_color = vec3(0.9, 0.8, 0.3);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// A dark rim all round (the strip is about nineteen times as wide as it is tall).
	vec2 rim = min(UV, 1.0 - UV) * vec2(19.0, 1.0);
	vec3 col = UV.x < fill ? tint : vec3(0.1, 0.09, 0.11);
	ALBEDO = min(rim.x, rim.y) < 0.16 ? vec3(0.05, 0.05, 0.06) : col;
}
