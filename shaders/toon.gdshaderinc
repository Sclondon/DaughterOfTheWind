// The look everything solid shares: flat cel shading in steps of light, with no outlines, and
// colour laid on like watercolour.

// art/watercolor.png (see tools/make_watercolor.gd): red is wide blotches, green is where
// pigment pooled, blue is paper grain. Set once for every shader in Project Settings.
global uniform sampler2D watercolor : repeat_enable, filter_linear_mipmap;

// Paint a colour as a watercolour wash. `pos` and `n` say where on the surface (use the model's
// own space for things that move, so the paint does not swim over them), and `size` is how many
// metres one tile of the texture covers.
vec3 wash(vec3 base, vec3 pos, vec3 n, float size) {
	// Look the texture up from the three sides and blend, so it wraps round any shape.
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 t = texture(watercolor, pos.zy / size).rgb * w.x + texture(watercolor, pos.xz / size).rgb * w.y
		+ texture(watercolor, pos.xy / size).rgb * w.z;
	// The wash dries unevenly: lighter here, darker there.
	vec3 col = base * mix(0.88, 1.1, t.r);
	// Where pigment pooled the colour is a little deeper; where it ran thin the paper shows.
	col = mix(mix(col, vec3(1.0, 0.98, 0.94), 0.1), col * mix(vec3(0.84), col, 0.25), t.g * 0.7);
	return col * mix(0.96, 1.04, t.b);
}

// Cel shading: full light, a half tone, or shade, with soft-but-narrow steps between.
void light() {
	float facing = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.03, 0.03, facing) * 0.7 + smoothstep(0.48, 0.54, facing) * 0.3;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lit / PI;
}
