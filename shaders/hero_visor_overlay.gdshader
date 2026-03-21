shader_type canvas_item;

uniform float storm_intensity: hint_range(0.0, 1.0) = 0.0;
uniform float breathing_phase: hint_range(0.0, 1.0) = 0.0;
uniform float helmet_vignette: hint_range(0.0, 1.0) = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = (uv - vec2(0.5)) * 2.0;
	float rim = pow(abs(centered.x), 3.0) + pow(abs(centered.y), 4.4);
	float vignette = smoothstep(0.38, 1.05, rim) * helmet_vignette;
	float top_shadow = smoothstep(0.08, 0.0, uv.y) * 0.09;
	float bottom_glow = smoothstep(0.68, 1.0, uv.y) * 0.06;

	float pulse = 0.5 + (0.5 * sin((breathing_phase * 6.28318) + (TIME * 0.25)));
	vec2 speck_uv = floor(uv * vec2(520.0, 280.0));
	float specks = step(0.9985 - (storm_intensity * 0.01), hash(speck_uv + floor(TIME * 1.4)));
	float streak_wave = sin((uv.y * 42.0) + (uv.x * 7.0) + (TIME * 2.1));
	float streaks = smoothstep(0.9 - (storm_intensity * 0.18), 1.0, streak_wave) * storm_intensity * (1.0 - uv.y);

	vec3 tint = mix(vec3(0.01, 0.03, 0.05), vec3(0.08, 0.22, 0.26), 0.4 + (pulse * 0.15));
	float alpha = vignette + top_shadow + bottom_glow + (specks * 0.12) + (streaks * 0.08);
	COLOR = vec4(tint, alpha);
}
