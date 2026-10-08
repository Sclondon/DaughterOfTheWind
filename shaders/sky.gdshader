shader_type sky;

// A painted afternoon sky: deep blue overhead, pale at the horizon, with a soft sun.
// Below the horizon it is the haze colour, the same one the sea of clouds fades to.

uniform vec3 zenith : source_color = vec3(0.16, 0.38, 0.74);
uniform vec3 horizon : source_color = vec3(0.8, 0.88, 0.95);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

void sky() {
	float h = EYEDIR.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.42));
	float toward = max(dot(EYEDIR, sun_dir), 0.0);
	col += sun_color * (smoothstep(0.9993, 0.9997, toward) * 3.0 + pow(toward, 60.0) * 0.25 + pow(toward, 6.0) * 0.05);
	COLOR = col;
}
