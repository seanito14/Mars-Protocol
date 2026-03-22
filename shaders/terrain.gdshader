shader_type spatial;

uniform sampler2D height_map;
uniform sampler2D terrain_data;
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
uniform float world_variation_scale : hint_range(0.001, 0.1) = 0.014;
uniform float detail_variation_scale : hint_range(0.001, 0.2) = 0.05;
uniform float distance_fade_end : hint_range(100.0, 4000.0) = 1400.0;
uniform float cliff_blend_start : hint_range(0.0, 1.0) = 0.18;
uniform float cliff_blend_end : hint_range(0.0, 1.0) = 0.52;
uniform float cap_blend_start : hint_range(0.0, 1.0) = 0.58;
uniform float cap_blend_end : hint_range(0.0, 1.0) = 0.92;
uniform float strata_count = 12.0;
uniform float strata_intensity : hint_range(0.0, 1.0) = 0.14;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

vec3 get_triplanar_weights(vec3 normal) {
	vec3 blend = abs(normal);
	blend = max(blend, vec3(0.0001));
	blend = pow(blend, vec3(4.0));
	return blend / (blend.x + blend.y + blend.z);
}

float sample_world_field(vec3 world_pos, vec3 world_normal, float scale) {
	vec3 weights = get_triplanar_weights(world_normal);
	float yz = sin((world_pos.y * scale * 0.52) + (world_pos.z * scale * 1.13) + 0.9) * 0.5 + 0.5;
	float xz = sin((world_pos.x * scale * 0.88) - (world_pos.z * scale * 0.72) - 0.7) * 0.5 + 0.5;
	float xy = sin((world_pos.x * scale * 1.06) + (world_pos.y * scale * 0.34) + 1.7) * 0.5 + 0.5;
	return yz * weights.x + xz * weights.y + xy * weights.z;
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

	float broad_variation = sample_world_field(v_world_pos, v_world_normal, world_variation_scale);
	float detail_variation = sample_world_field(v_world_pos + vec3(37.0, 11.0, -23.0), v_world_normal, detail_variation_scale);
	float cliff_mask = smoothstep(cliff_blend_start, cliff_blend_end, slope01);
	float cap_mask = smoothstep(cap_blend_start, cap_blend_end, height01) * (1.0 - cliff_mask * 0.55);
	float floor_mask = (1.0 - smoothstep(cliff_blend_start * 0.5, cliff_blend_end, slope01)) * (1.0 - smoothstep(0.7, 0.98, height01));
	floor_mask = clamp(floor_mask + (dust_accumulation * 0.32), 0.0, 1.0);

	vec3 compact_floor_color = mix(rock_color, cliff_color, 0.28);
	vec3 floor_color = mix(compact_floor_color, dust_color, clamp(0.24 + (dust_accumulation * 0.24) + ((broad_variation - 0.5) * 0.16), 0.0, 1.0));
	vec3 cliff_base = mix(rock_color, cliff_color, clamp(0.72 + ((detail_variation - 0.5) * 0.22), 0.0, 1.0));
	vec3 cap_color = mix(cliff_color, dust_color, clamp(0.38 + (broad_variation * 0.22), 0.0, 1.0));

	vec3 base_color = floor_color;
	base_color = mix(base_color, cap_color, cap_mask);
	base_color = mix(base_color, cliff_base, cliff_mask * clamp(0.7 + ridge_strength, 0.0, 1.0));

	float strata_raw = height01 * strata_count + ((detail_variation - 0.5) * 0.4);
	float strata_line = abs(fract(strata_raw + 0.5) - 0.5) * 2.0;
	float strata_accent = smoothstep(0.78, 1.0, 1.0 - strata_line) * strata_intensity;
	base_color = mix(base_color, base_color * 1.08, strata_accent * max(cliff_mask, cap_mask * 0.7));

	float floor_breakup = ((detail_variation - 0.5) * 0.12) + ((broad_variation - 0.5) * 0.08);
	base_color = mix(base_color, base_color * (0.88 + (floor_breakup * ripple_strength * 3.2)), floor_mask);
	float lowland_occlusion = floor_mask * (1.0 - height01) * 0.16;
	base_color *= 1.0 - lowland_occlusion;

	float steep_shadow = clamp(slope01 * 1.32, 0.0, 1.0);
	float dust_shadow = clamp((floor_mask * 0.06) + ((1.0 - dust_accumulation) * dust_shadow_strength * 0.08), 0.0, dust_shadow_strength);
	base_color = mix(base_color, shadow_tint, steep_shadow * steep_shadow_strength);
	base_color -= dust_shadow;

	base_color *= mix(brightness_floor, brightness_peak, clamp((height01 * 0.74) + (dust_accumulation * 0.1) + (broad_variation * 0.12), 0.0, 1.0));

	float cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float dist_fade = clamp(cam_dist / max(distance_fade_end, 1.0), 0.0, 0.35);
	vec3 haze_color = mix(dust_color, vec3(0.72, 0.58, 0.48), 0.5);
	base_color = mix(base_color, haze_color * brightness_peak * 0.78, dist_fade);

	ALBEDO = base_color;
	ROUGHNESS = mix(0.98, 0.82, clamp((cliff_mask * 0.78) + (cap_mask * 0.22) + (detail_variation * 0.08), 0.0, 1.0));
	SPECULAR = 0.03;
}
