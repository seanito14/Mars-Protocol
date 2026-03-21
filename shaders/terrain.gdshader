shader_type spatial;

uniform sampler2D height_map;
uniform float height_scale = 90.0;
uniform vec3 dust_color : source_color = vec3(0.76, 0.38, 0.22);
uniform vec3 cliff_color : source_color = vec3(0.52, 0.24, 0.12);
uniform vec3 rock_color : source_color = vec3(0.25, 0.18, 0.15);
uniform vec3 shadow_tint : source_color = vec3(0.18, 0.06, 0.04);
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.18;
uniform float ridge_strength : hint_range(0.0, 1.0) = 0.28;
uniform float steep_shadow_strength : hint_range(0.0, 1.0) = 0.48;
uniform float dust_shadow_strength : hint_range(0.0, 1.0) = 0.18;
uniform float brightness_floor : hint_range(0.0, 2.0) = 0.62;
uniform float brightness_peak : hint_range(0.0, 2.0) = 1.06;
uniform float strata_count = 12.0;
uniform float strata_intensity : hint_range(0.0, 1.0) = 0.14;

varying float v_height;
varying vec3 v_world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	v_height = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float slope = 1.0 - NORMAL.y;
	float detail = texture(height_map, UV).r;

	// Wind-directional floor tonal variation (broad, organic field)
	float wind_a = sin((v_world_pos.x * 0.014) - (v_world_pos.z * 0.008) + 0.6) * 0.5 + 0.5;
	float wind_b = sin((v_world_pos.x * 0.009) + (v_world_pos.z * 0.012) - 1.1) * 0.5 + 0.5;
	float wind_field = mix(wind_a, wind_b, 0.45);

	// Subtle surface ripple (aeolian micro-dunes)
	float ripple_a = sin((v_world_pos.x * 0.42) + (v_world_pos.z * 0.08));
	float ripple_b = sin((v_world_pos.x * 0.19) - (v_world_pos.z * 0.24) + 1.7);
	float ripple_c = sin((v_world_pos.x * 0.31) + (v_world_pos.z * 0.37) + 2.2);
	float ripple = (ripple_a * 0.42 + ripple_b * 0.33 + ripple_c * 0.25) * ripple_strength;

	// Sedimentary height bands — broad, gradual, geologic
	float band_low = smoothstep(0.08, 0.38, v_height);
	float band_mid = smoothstep(0.32, 0.62, v_height);
	float band_high = smoothstep(0.55, 0.88, v_height);
	vec3 base_color = mix(rock_color, cliff_color, band_low);
	base_color = mix(base_color, mix(cliff_color, dust_color, 0.5), band_mid);
	base_color = mix(base_color, dust_color, band_high);

	// Slope-driven cliff darkening (curvature-aware)
	float cliff_factor = clamp(slope * 1.35, 0.0, 1.0);
	base_color = mix(base_color, cliff_color * 0.82, cliff_factor * ridge_strength);

	// Wind-shaped floor tonal modulation (not uniform ripple)
	float floor_mask = 1.0 - clamp(v_height * 2.8, 0.0, 1.0);
	base_color = mix(base_color, base_color * (0.92 + wind_field * 0.16), floor_mask);

	// Surface detail: ripples on flat ground only
	float ridge_mask = clamp(smoothstep(0.08, 0.7, detail + ripple + (v_height * 0.14)), 0.0, 1.0);
	base_color = mix(base_color * 0.93, base_color * 1.05, ridge_mask * (1.0 - cliff_factor * 0.6));

	// Grit, pebble fields, micro detail
	float grit = hash(v_world_pos.xz * 10.0) * 0.08;
	float pebble_field = step(0.86, hash(floor(v_world_pos.xz * 1.8)));
	float micro_pebbles = step(0.93, hash(floor(v_world_pos.xz * 4.8) + 19.0));
	float dark_streak = smoothstep(0.58, 0.92, sin((v_world_pos.x * 0.065) - (v_world_pos.z * 0.028) + 0.9));

	// Steep self-shadow (deep maroon in cliff recesses)
	float steep_shadow = clamp(slope * 1.42, 0.0, 1.0);
	float dust_shadow = clamp((1.0 - v_height) * 0.12 + (slope * 0.1), 0.0, dust_shadow_strength);

	// Strata Highlighting (emphasize the authored height steps)
	float strata_raw = v_height * strata_count;
	float strata_line = abs(fract(strata_raw + 0.5) - 0.5) * 2.0;
	float strata_grad = smoothstep(0.0, 0.15, strata_line);
	float strata_accent = (1.0 - strata_grad) * strata_intensity;
	
	base_color += grit - 0.04;
	base_color = mix(base_color, rock_color * 0.88, pebble_field * 0.14);
	base_color = mix(base_color, rock_color * 0.82, micro_pebbles * 0.1);
	base_color = mix(base_color, base_color * 0.88, dark_streak * 0.08);
	base_color = mix(base_color, shadow_tint, steep_shadow * steep_shadow_strength);
	base_color -= dust_shadow;
	base_color = mix(base_color, base_color * 1.12, strata_accent * (1.0 - floor_mask));

	// Brightness: ground stays DARKER than sky, never washes out
	base_color *= mix(brightness_floor, brightness_peak, clamp(mix(v_height, detail, 0.22) * 1.3, 0.0, 1.0));

	// Depth-distance desaturation (distant formations lose contrast)
	float cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float dist_fade = clamp(cam_dist / 1200.0, 0.0, 0.35);
	vec3 haze_color = mix(dust_color, vec3(0.72, 0.58, 0.48), 0.5);
	base_color = mix(base_color, haze_color * brightness_peak * 0.78, dist_fade);

	ALBEDO = base_color;
	ROUGHNESS = mix(0.97, 0.82, clamp(slope + (pebble_field * 0.18) + (micro_pebbles * 0.14), 0.0, 1.0));
	SPECULAR = 0.03;
}
