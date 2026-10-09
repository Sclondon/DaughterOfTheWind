shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, blend_mix, depth_draw_never, shadows_disabled;

// The high wispy clouds: one big flat sheet far above everything, following the glider, with
// mares' tails painted on it. The streaks are slow noise stretched out along the wind and bent
// into hooks; where there is none the sheet is clear. It is the one cloud that is blended
// rather than solid, which is safe because nothing else see-through is ever up there with it.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 haze_color : source_color = vec3(0.8, 0.88, 0.95);
// How far the clouds have drifted on the wind (world XZ), and which way the wind blows.
uniform vec2 drift = vec2(0.0);
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float reach = 13000.0;
// How much of the sheet is streaked: about 0.3 in clear weather to 0.8 in heavy.
uniform float cover = 0.5;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz - drift;
	// x runs along the wind, y across it.
	vec2 q = vec2(dot(p, wind_dir), dot(p, vec2(-wind_dir.y, wind_dir.x)));
	// Where the banks of streaks are (decided before any bending, so the banks keep their shape).
	float bank = texture(noise_tex, q / vec2(41000.0, 26000.0) + 0.37).r;
	// Sway the streaks gently, like long brush strokes that are not quite straight.
	float bend = texture(noise_tex, q / vec2(47000.0, 31000.0)).r - 0.5;
	q.y += bend * 2600.0 + sin(q.x / 6100.0 + bend * 5.0) * 240.0;
	float streak = texture(noise_tex, q / vec2(21000.0, 1900.0)).r;
	float fibre = texture(noise_tex, q / vec2(9000.0, 520.0) + 0.61).r;
	float d = streak * 0.6 + fibre * 0.4 + (bank - 0.5) * 0.7;
	float edge = mix(0.68, 0.52, cover);
	// Two flat strengths, like two passes of a dry brush.
	float a = smoothstep(edge, edge + 0.035, d) * 0.3 + smoothstep(edge + 0.07, edge + 0.11, d) * 0.4;

	vec3 to_eye = CAMERA_POSITION_WORLD - w_pos;
	float dist = length(to_eye);
	a *= 1.0 - smoothstep(reach * 0.45, reach, length(to_eye.xz));
	// Flying up through it, it thins away round the camera.
	a *= smoothstep(40.0, 400.0, dist);
	// Brightest toward the sun.
	float toward = pow(max(dot(-to_eye / dist, sun_dir), 0.0), 3.0);
	ALBEDO = mix(mix(lit_color, haze_color, 0.25), vec3(1.0), toward * 0.6);
	ALPHA = a;
}
