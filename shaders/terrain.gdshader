shader_type spatial;

uniform sampler2D height_map;
uniform sampler2D terrain_data;
uniform float height_scale = 90.0;
uniform vec3 sand_color : source_color = vec3(0.86, 0.49, 0.24);
uniform vec3 sand_shadow_color : source_color = vec3(0.56, 0.28, 0.13);
uniform vec3 strata_dark_color : source_color = vec3(0.31, 0.13, 0.07);
uniform vec3 strata_bright_color : source_color = vec3(0.72, 0.31, 0.1);
uniform vec3 haze_tint : source_color = vec3(0.92, 0.63, 0.46);
uniform float slope_threshold_degrees : hint_range(10.0, 80.0) = 45.0;
uniform float slope_transition_degrees : hint_range(1.0, 20.0) = 7.0;
uniform float world_variation_scale : hint_range(0.001, 0.1) = 0.014;
uniform float detail_variation_scale : hint_range(0.001, 0.2) = 0.075;
uniform float ripple_scale : hint_range(0.001, 0.2) = 0.06;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.3;
uniform float strata_frequency : hint_range(1.0, 48.0) = 18.0;
uniform float strata_contrast : hint_range(0.0, 1.0) = 0.86;
uniform float grit_strength : hint_range(0.0, 1.0) = 0.38;
uniform float grit_scale : hint_range(0.001, 0.4) = 0.18;
uniform float distance_fade_end : hint_range(100.0, 4000.0) = 1400.0;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

vec3 get_triplanar_weights(vec3 normal) {
	vec3 blend = abs(normal);
	blend = max(blend, vec3(0.0001));
	blend = pow(blend, vec3(6.0));
	return blend / (blend.x + blend.y + blend.z);
}

float sample_world_field(vec3 world_pos, vec3 world_normal, float scale) {
	vec3 weights = get_triplanar_weights(world_normal);
	float yz = sin((world_pos.y * scale * 0.52) + (world_pos.z * scale * 1.13) + 0.9) * 0.5 + 0.5;
	float xz = sin((world_pos.x * scale * 0.88) - (world_pos.z * scale * 0.72) - 0.7) * 0.5 + 0.5;
	float xy = sin((world_pos.x * scale * 1.06) + (world_pos.y * scale * 0.34) + 1.7) * 0.5 + 0.5;
	return yz * weights.x + xz * weights.y + xy * weights.z;
}

vec3 sample_triplanar_noise(vec3 world_pos, vec3 world_normal, float scale) {
	vec3 weights = get_triplanar_weights(world_normal);
	vec3 yz = vec3(
		sin(world_pos.y * scale * 1.7 + world_pos.z * scale * 2.9),
		sin(world_pos.y * scale * 2.3 - world_pos.z * scale * 1.6 + 1.7),
		sin(world_pos.y * scale * 1.1 + world_pos.z * scale * 2.1 + 2.4)
	);
	vec3 xz = vec3(
		sin(world_pos.x * scale * 2.4 + world_pos.z * scale * 1.8 + 0.7),
		sin(world_pos.x * scale * 1.3 - world_pos.z * scale * 2.7 + 2.1),
		sin(world_pos.x * scale * 2.0 + world_pos.z * scale * 1.2 + 1.2)
	);
	vec3 xy = vec3(
		sin(world_pos.x * scale * 2.8 + world_pos.y * scale * 1.5 + 1.4),
		sin(world_pos.x * scale * 1.6 - world_pos.y * scale * 2.2 + 0.5),
		sin(world_pos.x * scale * 2.1 + world_pos.y * scale * 1.9 + 2.8)
	);
	return (yz * weights.x + xz * weights.y + xy * weights.z) * 0.5 + 0.5;
}

void vertex() {
	v_height = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 runtime_sample = texture(terrain_data, UV);
	float runtime_mix = step(0.5, runtime_sample.a);
	float fallback_height = texture(height_map, UV).r;
	float height01 = mix(fallback_height, runtime_sample.r, runtime_mix);
	float slope01 = max(mix(clamp(1.0 - NORMAL.y, 0.0, 1.0), runtime_sample.g, runtime_mix), clamp(1.0 - v_world_normal.y, 0.0, 1.0));
	float dust_accumulation = mix(clamp(1.0 - height01, 0.0, 1.0), runtime_sample.b, runtime_mix);

	float slope_threshold = sin(radians(slope_threshold_degrees));
	float slope_transition = sin(radians(slope_transition_degrees));
	float rock_mask = smoothstep(slope_threshold - slope_transition, slope_threshold + slope_transition, slope01);
	float sand_mask = 1.0 - rock_mask;

	float broad_variation = sample_world_field(v_world_pos, v_world_normal, world_variation_scale);
	float detail_variation = sample_world_field(v_world_pos + vec3(37.0, 11.0, -23.0), v_world_normal, detail_variation_scale);
	float ripple_field = sample_world_field(v_world_pos + vec3(-18.0, 3.0, 24.0), vec3(0.0, 1.0, 0.0), ripple_scale);
	vec3 grit_noise = sample_triplanar_noise(v_world_pos + vec3(11.0, -7.0, 19.0), v_world_normal, grit_scale);

	float ripple_bands = sin((v_world_pos.x + v_world_pos.z * 1.25) * ripple_scale * 6.0 + broad_variation * 6.28318) * 0.5 + 0.5;
	float ripple_mix = clamp((ripple_bands * 0.65) + (ripple_field * 0.35), 0.0, 1.0);
	vec3 sand_base = mix(sand_shadow_color, sand_color, clamp(0.45 + dust_accumulation * 0.25 + broad_variation * 0.3, 0.0, 1.0));
	vec3 sand_albedo = mix(sand_base * 0.82, sand_base * 1.08, ripple_mix * ripple_strength);

	float strata_axis = v_world_pos.y * 0.06 + detail_variation * 1.6 + grit_noise.r * 0.9;
	float strata_wave = sin(strata_axis * strata_frequency) * 0.5 + 0.5;
	float strata_mask = smoothstep(0.5 - strata_contrast * 0.35, 0.5 + strata_contrast * 0.35, strata_wave);
	vec3 rock_base = mix(strata_dark_color, strata_bright_color, strata_mask);
	rock_base = mix(rock_base * 0.78, rock_base * 1.12, clamp(detail_variation * 0.72 + grit_noise.g * 0.28, 0.0, 1.0));
	float sediment_edge = smoothstep(0.38, 0.88, abs(fract(strata_axis * (strata_frequency * 0.5)) - 0.5) * 2.0);
	vec3 rock_albedo = mix(rock_base, mix(strata_bright_color, haze_tint, 0.2), sediment_edge * 0.22);

	vec3 base_color = mix(sand_albedo, rock_albedo, rock_mask);
	float cavity = (1.0 - grit_noise.b) * grit_strength;
	base_color *= 1.0 - cavity * mix(0.08, 0.2, rock_mask);

	float cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float dist_fade = clamp(cam_dist / max(distance_fade_end, 1.0), 0.0, 0.42);
	base_color = mix(base_color, haze_tint, dist_fade * 0.55);

	vec3 grit_normal = normalize(mix(vec3(0.0, 0.0, 1.0), grit_noise * 2.0 - 1.0, grit_strength));
	vec3 macro_normal = normalize(vec3((detail_variation - 0.5) * 0.6, 1.0, (ripple_field - 0.5) * 0.6));
	NORMAL_MAP = mix(macro_normal, grit_normal, 0.72);
	NORMAL_MAP_DEPTH = mix(0.12, 0.38, grit_strength);

	ALBEDO = base_color;
	ROUGHNESS = mix(0.96, 0.82, rock_mask * 0.85 + grit_noise.r * 0.08);
	SPECULAR = 0.03;
}
