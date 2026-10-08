shader_type canvas_item;
render_mode blend_add;

// The sun's glare, drawn over the whole screen and added to the picture (see sun_glare.gd).

// Where the sun is on screen (0..1 each way; may be off the edge), how strong the glare is, and
// the screen's width over its height.
uniform vec2 sun = vec2(0.5);
uniform float strength = 0.0;
uniform float aspect = 1.78;

// A soft-edged ring or disc centred `along` the way from the sun through the middle of the screen.
float ghost(vec2 uv, float along, float radius, float hollow) {
	vec2 at = sun + (vec2(0.5) - sun) * along;
	float r = length((uv - at) * vec2(aspect, 1.0));
	return smoothstep(radius, radius * 0.86, r) * mix(1.0, smoothstep(radius * 0.45, radius * 0.9, r), hollow);
}

void fragment() {
	vec2 p = (UV - sun) * vec2(aspect, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	// A wide warm veil, a tight hot core, six rays, and a long thin streak.
	float bloom = exp(-r * 4.5) * 0.4 + exp(-r * 22.0) * 0.95;
	float rays = pow(abs(cos(a * 3.0 + 0.3)), 30.0) * exp(-r * 4.5) * 0.4
		+ pow(abs(cos(a * 3.0 + 1.35)), 60.0) * exp(-r * 7.0) * 0.3;
	float streak = exp(-abs(p.y) * 110.0) * exp(-abs(p.x) * 1.8) * 0.45;
	vec3 col = vec3(1.0, 0.93, 0.76) * (bloom + rays + streak);
	col += vec3(0.5, 0.8, 1.0) * ghost(UV, 0.55, 0.035, 1.0) * 0.16;
	col += vec3(1.0, 0.7, 0.5) * ghost(UV, 0.85, 0.02, 0.0) * 0.14;
	col += vec3(0.6, 1.0, 0.7) * ghost(UV, 1.35, 0.07, 1.0) * 0.1;
	col += vec3(1.0, 0.85, 0.6) * ghost(UV, 1.8, 0.11, 1.0) * 0.07;
	COLOR = vec4(col * strength, 1.0);
}
