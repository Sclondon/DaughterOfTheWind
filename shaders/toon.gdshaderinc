// The look everything solid shares: cel shading after Breath of the Wild, with no outlines.
//   - two flat tones, light and shade, with a narrow soft edge between them
//   - the shade is never black: the sky fills it, so shadows come out cool and coloured
//   - a thin bright rim where a lit surface turns away from the eye
//   - shiny things get one hard-edged highlight

// How bright the rim is, and how strong the highlight (0 for matte things).
uniform float rim = 0.45;
uniform float shine = 0.0;

void light() {
	float facing = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, facing);
	// The rim: only on the side the light reaches.
	float edge = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float glint = smoothstep(0.64, 0.72, edge) * smoothstep(-0.15, 0.25, facing) * rim;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (lit + glint) / PI;
	float highlight = smoothstep(0.972, 0.98, dot(NORMAL, normalize(LIGHT + VIEW)));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * highlight * lit * shine;
}
