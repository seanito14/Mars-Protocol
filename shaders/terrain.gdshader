shader_type spatial;

uniform sampler2D height_map;
uniform float height_scale = 90.0;
uniform vec3 dust_color : source_color = vec3(0.76, 0.38, 0.22);
uniform vec3 rock_color : source_color = vec3(0.25, 0.18, 0.15);

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
	float ripple_a = sin((v_world_pos.x * 0.42) + (v_world_pos.z * 0.08));
	float ripple_b = sin((v_world_pos.x * 0.19) - (v_world_pos.z * 0.24) + 1.7);
	float ripple = (ripple_a * 0.55 + ripple_b * 0.45) * 0.08;
	float ridge_mask = clamp(smoothstep(0.08, 0.7, detail + ripple + (v_height * 0.18)), 0.0, 1.0);
	vec3 base_color = mix(dust_color * 0.88, dust_color * 1.08, ridge_mask);
	base_color = mix(base_color, rock_color, clamp(slope * 2.8, 0.0, 1.0));

	float grit = hash(v_world_pos.xz * 10.0) * 0.1;
	float pebble_field = step(0.84, hash(floor(v_world_pos.xz * 1.8)));
	float micro_pebbles = step(0.92, hash(floor(v_world_pos.xz * 4.8) + 19.0));
	float dark_streak = smoothstep(0.58, 0.92, sin((v_world_pos.x * 0.065) - (v_world_pos.z * 0.028) + 0.9));
	float dust_shadow = clamp((1.0 - v_height) * 0.14 + (slope * 0.12), 0.0, 0.18);
	base_color += grit - 0.05;
	base_color = mix(base_color, rock_color * 0.92, pebble_field * 0.18);
	base_color = mix(base_color, rock_color * 0.84, micro_pebbles * 0.12);
	base_color = mix(base_color, base_color * 0.86, dark_streak * 0.1);
	base_color -= dust_shadow;
	base_color *= mix(0.62, 1.06, clamp(mix(v_height, detail, 0.28) * 1.4, 0.0, 1.0));
	
	ALBEDO = base_color;
	ROUGHNESS = mix(0.97, 0.8, clamp(slope + (pebble_field * 0.2) + (micro_pebbles * 0.16), 0.0, 1.0));
	SPECULAR = 0.035;
}
