shader_type canvas_item;

uniform sampler2D source_texture : source_color;
uniform vec2 source_texel_size = vec2(0.0005208333, 0.0009259259);
uniform vec4 sample_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool mirror_x = false;
uniform bool mirror_y = false;

vec2 map_uv(vec2 uv) {
	if (mirror_x) {
		uv.x = 1.0 - uv.x;
	}
	if (mirror_y) {
		uv.y = 1.0 - uv.y;
	}
	return mix(sample_rect.xy, sample_rect.zw, clamp(uv, vec2(0.0), vec2(1.0)));
}

vec4 sample_blur(vec2 uv) {
	vec2 mapped_uv = map_uv(uv);
	vec2 blur_offset = source_texel_size * 10.0;
	vec4 color = texture(source_texture, mapped_uv) * 0.36;
	color += texture(source_texture, map_uv(uv + vec2(blur_offset.x, 0.0))) * 0.16;
	color += texture(source_texture, map_uv(uv - vec2(blur_offset.x, 0.0))) * 0.16;
	color += texture(source_texture, map_uv(uv + vec2(0.0, blur_offset.y))) * 0.12;
	color += texture(source_texture, map_uv(uv - vec2(0.0, blur_offset.y))) * 0.12;
	color += texture(source_texture, map_uv(uv + blur_offset)) * 0.04;
	color += texture(source_texture, map_uv(uv - blur_offset)) * 0.04;
	return color;
}

void fragment() {
	vec4 color = sample_blur(UV);
	color.rgb = mix(color.rgb, vec3(0.84, 0.53, 0.39), 0.18);
	color.rgb *= 0.84;
	float vignette = smoothstep(0.0, 0.95, max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 1.85);
	color.rgb *= 1.0 - (vignette * 0.12);
	color.a = 0.94;
	COLOR = color;
}
