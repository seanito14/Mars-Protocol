shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;
uniform vec4 glass_tint : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform float edge_highlight : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // Basic screen blur
    vec4 bg_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, blur_amount);
    
    // Calculate distance from center for a soft circular shape
    vec2 center = vec2(0.5, 0.5);
    float d = distance(UV, center);
    
    // Soft circular mask (0.0 at center, 1.0 at edge, cut off at 0.5)
    if (d > 0.5) {
        discard;
    }
    
    // Inner rim light for the "glass" edge
    float rim = smoothstep(0.4, 0.5, d) * edge_highlight;
    
    // Combine blur, tint, and rim light
    vec4 final_color = mix(bg_color, glass_tint, glass_tint.a);
    final_color.rgb += vec3(rim);
    
    COLOR = final_color;
}
