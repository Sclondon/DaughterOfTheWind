shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// The ocean: one huge flat sheet that follows the glider. A clear, bright blue: deep out at sea,
// azure nearer in, turquoise over the shallows, white with foam along the foot of the cliffs, and
// rolling in in lines of surf on the beach. It is painted in flat tones like everything else, and
// it sparkles: thousands of small glints that wink on and off, crowded together into a dazzling
// path under the sun and scattered thinly everywhere else. It fades into the same haze as the
// sky at the horizon.
//
// shore_x(), the valley, the trenches and the sea bed's slope repeat what scripts/coast.gd does,
// so the water knows where the land is without being told. Keep the two in step.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float valley_z = 0.0;
uniform float valley_half = 640.0;
// The trenches (coast.gd: TRENCH_SPACING, TRENCH_HALF, TRENCH_WATER).
uniform float trench_spacing = 2200.0;
uniform float trench_half = 190.0;
uniform float trench_water = 380.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 deep_color : source_color = vec3(0.03, 0.27, 0.64);
uniform vec3 mid_color : source_color = vec3(0.05, 0.43, 0.8);
uniform vec3 shallow_color : source_color = vec3(0.22, 0.76, 0.8);
uniform vec3 sky_color : source_color = vec3(0.3, 0.5, 0.85);
uniform vec3 haze_color : source_color = vec3(0.73, 0.85, 0.96);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.88);
uniform float haze_distance = 8500.0;
// How thick the glints are: 1 is the look, 0 turns them off.
uniform float sparkle = 1.0;

varying vec3 w_pos;

float shore_x(float z) {
	return 260.0 * sin(z / 1900.0 + 1.3) + 140.0 * sin(z / 830.0 + 4.1) + 60.0 * sin(z / 310.0 + 0.7);
}

// Metres of open water between a point and the nearest wall (or the head) of the trench it is
// in. Negative when it is not in one. `d` is how far inland of the shoreline the point is.
float trench_room(vec2 p, float d) {
	float k = floor(p.y / trench_spacing + 0.5);
	if (k == 0.0) {
		return -1000.0;
	}
	float zc = (k + 0.3 * sin(k * 2.4 + 1.0)) * trench_spacing;
	float mid = zc + 110.0 * sin(p.x / 330.0 + k * 1.7);
	float half = trench_half * (0.75 + 0.25 * sin(k * 5.1)) * (1.0 - 0.45 * smoothstep(400.0, 2600.0, d));
	float wall = (0.61 - abs(p.y - mid) / half) * half;
	return min(wall, trench_water + 50.0 - d);
}

float swell(vec2 p) {
	return texture(noise_tex, p / 310.0 + vec2(TIME * 0.011, TIME * 0.006)).r * 0.6
		+ texture(noise_tex, p / 83.0 - vec2(TIME * 0.02, -TIME * 0.013)).r * 0.4;
}

float hash21(vec2 p) {
	p = fract(mod(p, 1024.0) * vec2(0.1031, 0.1167));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// One sheet of glints: the sea cut into squares `size` metres across, a share `thick` of which
// each hold one four-pointed glint that winks at its own pace.
float glints(vec2 p, float size, float thick) {
	vec2 g = p / size;
	vec2 id = floor(g);
	float pick = hash21(id);
	if (pick > thick) {
		return 0.0;
	}
	vec2 f = fract(g) - 0.5 - (vec2(hash21(id + 7.1), hash21(id + 3.7)) - 0.5) * 0.5;
	float wink = smoothstep(0.35, 1.0, sin(TIME * (1.5 + 4.0 * hash21(id + 1.3)) + pick * 700.0));
	float star = max(1.0 - (abs(f.x) + abs(f.y)) * 4.5, 0.0);
	star = max(star, max(1.0 - (abs(f.x) * 14.0 + abs(f.y) * 2.4), 1.0 - (abs(f.y) * 14.0 + abs(f.x) * 2.4)));
	return smoothstep(0.0, 0.35, star) * wink;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_eye);
	vec3 v = to_eye / dist;
	vec2 p = w_pos.xz;

	// Waves, flattening with distance so the far sea is calm, not noisy.
	float calm = 1.0 - smoothstep(800.0, 5000.0, dist);
	float h = swell(p);
	float hx = swell(p + vec2(6.0, 0.0));
	float hz = swell(p + vec2(0.0, 6.0));
	vec3 n = normalize(vec3((h - hx) * 5.0 * calm, 1.0, (h - hz) * 5.0 * calm));

	// How far off shore is this, and how deep? The sea bed drops fast under the cliffs and
	// shelves gently off the beach at the valley's mouth. Up a trench, "off shore" is the room
	// to its nearest wall.
	float off = shore_x(p.y) - p.x;
	off = max(off, trench_room(p, -off));
	float beach = 1.0 - smoothstep(0.3, 1.0, abs(p.y - (valley_z + 260.0 * sin(p.x / 1700.0 + 0.5))) / valley_half);
	// (Only close in: further out the bed falls away like anywhere else.)
	beach *= 1.0 - smoothstep(250.0, 1000.0, off);
	float depth = min(off * mix(0.9, 0.035, beach), 120.0);
	// Three flat blues, with the edge between them pushed about by the swell.
	float d2 = depth + (h - 0.5) * 16.0;
	vec3 col = mix(shallow_color, mid_color, smoothstep(9.0, 15.0, d2));
	col = mix(col, deep_color, smoothstep(52.0, 70.0, d2));
	// Cel shading: the swell in two flat tones, and a thin bright line along some of the crests.
	col *= mix(0.92, 1.06, smoothstep(0.47, 0.5, h));
	float crest = (1.0 - smoothstep(0.0, 0.012, abs(h - 0.6))) * calm;
	col = mix(col, mix(col, vec3(1.0), 0.35), crest);

	// The surface mirrors the sky more at a glancing angle.
	float glance = pow(1.0 - max(dot(n, v), 0.0), 4.0);
	col = mix(col, sky_color, glance * 0.45);

	// The sparkle. How near this bit of sea is to mirroring the sun into the eye decides how
	// crowded the glints are: packed along the sun's path, thin elsewhere. Two sheets of
	// squares, sized by distance so a glint is always a few pixels across.
	float mirror = max(dot(reflect(-v, n), sun_dir), 0.0);
	float flat_mirror = max(dot(reflect(-v, vec3(0.0, 1.0, 0.0)), sun_dir), 0.0);
	float path = pow(flat_mirror, 9.0);
	float thick = (0.05 + 0.75 * path + 0.25 * pow(flat_mirror, 60.0)) * sparkle;
	float lod = max(log2(max(dist, 1.0) / 110.0) * 0.5, 0.0);
	float lo = floor(lod);
	float blend = lod - lo;
	float glint = glints(p, 1.7 * pow(4.0, lo), thick) * (1.0 - blend)
			+ glints(p + 31.0, 1.7 * pow(4.0, lo + 1.0), thick) * blend;
	// (The swell hides some of them, so they come in drifting shoals rather than evenly.)
	glint *= smoothstep(0.38, 0.52, h + path * 0.3);
	glint *= 1.0 - smoothstep(9000.0, 14000.0, dist);
	col = mix(col, sun_color * 1.25, clamp(glint, 0.0, 1.0));
	// And the sun's own hard reflection, where the waves tilt just so.
	col += sun_color * pow(mirror, 240.0) * 1.2;

	// Foam: a ragged white line at the shore that breathes in and out, and a few whitecaps.
	float wash = 10.0 + 5.0 * sin(TIME * 0.7 + h * 12.0);
	float foam = (1.0 - smoothstep(wash * 0.5, wash, off)) * smoothstep(0.35, 0.6, h + 0.25);
	// Surf: lines of breakers rolling up the beach.
	float roller = smoothstep(0.8, 0.96, sin(off * 0.085 + TIME * 0.9 + h * 2.5));
	foam = max(foam, roller * beach * (1.0 - smoothstep(70.0, 190.0, off)) * smoothstep(0.3, 0.55, h + 0.2));
	foam = max(foam, smoothstep(0.76, 0.8, h) * 0.3 * calm);
	col = mix(col, vec3(0.97), foam);

	float haze = 1.0 - exp(-dist / haze_distance);
	haze = max(haze * 0.95, smoothstep(9000.0, 15000.0, dist));
	ALBEDO = mix(col, haze_color, haze);
}
