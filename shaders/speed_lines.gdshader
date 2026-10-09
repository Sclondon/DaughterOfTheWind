shader_type canvas_item;

// Speed lines (see speed_lines.gd): the screen is cut into thin wedges round its middle, and a
// changing handful of them are drawn as white streaks, from the edge inward. More of them, and
// reaching further in, as `strength` goes up.

uniform float strength = 0.0;
uniform float aspect = 1.78;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float wedges = 240.0;
	float turn = atan(p.y, p.x) / 6.2832 * wedges;
	float wedge = floor(turn);
	// Which wedges are lit changes many times a second, so the lines flicker and rush.
	float beat = floor(TIME * 16.0);
	float lit = step(1.0 - 0.14 * strength, hash(wedge + beat * 17.0));
	// A streak is thin across its wedge and tapers to nothing at its inner end.
	float inner = mix(0.74, 0.44, strength * hash(wedge * 3.1 + beat));
	float reach = smoothstep(inner, inner + 0.35, r);
	float thin = 1.0 - smoothstep(0.0, 0.5 * reach + 0.001, abs(fract(turn) - 0.5));
	COLOR = vec4(1.0, 1.0, 1.0, lit * thin * reach * strength * 0.55);
}
