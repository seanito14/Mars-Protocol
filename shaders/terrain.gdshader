shader_type spatial;

// ── Texture inputs ────────────────────────────────────────────────────────────
uniform sampler2D height_map;
uniform sampler2D terrain_data;

// ── Height / scale ────────────────────────────────────────────────────────────
uniform float height_scale = 90.0;

// ── Base terrain colours ──────────────────────────────────────────────────────
uniform vec3 sand_color         : source_color = vec3(0.76, 0.42, 0.20);   // fine aeolian silt
uniform vec3 sand_shadow_color  : source_color = vec3(0.44, 0.22, 0.10);   // shadow hollows
uniform vec3 duricrust_color    : source_color = vec3(0.52, 0.26, 0.11);   // hardened surface crust
uniform vec3 strata_dark_color  : source_color = vec3(0.26, 0.11, 0.06);   // deep basalt
uniform vec3 strata_mid_color   : source_color = vec3(0.46, 0.21, 0.10);   // iron-oxide sienna
uniform vec3 strata_bright_color: source_color = vec3(0.68, 0.29, 0.09);   // ochre caprock
uniform vec3 cliff_tint         : source_color = vec3(0.38, 0.17, 0.08);   // cliff face wash
uniform vec3 haze_tint          : source_color = vec3(0.88, 0.61, 0.44);   // atmospheric haze

// ── Slope blending ────────────────────────────────────────────────────────────
uniform float slope_threshold_degrees    : hint_range(10.0, 80.0)  = 40.0;
uniform float slope_transition_degrees   : hint_range(1.0,  20.0)  = 8.0;

// ── World-space tonal variation ───────────────────────────────────────────────
uniform float world_variation_scale  : hint_range(0.001, 0.1)   = 0.013;
uniform float detail_variation_scale : hint_range(0.001, 0.2)   = 0.065;

// ── Aeolian ripple ────────────────────────────────────────────────────────────
uniform float ripple_scale    : hint_range(0.001, 0.2)  = 0.052;
uniform float ripple_strength : hint_range(0.0, 1.0)    = 0.40;
uniform vec2  wind_direction                             = vec2(0.72, 0.38); // normalised XZ

// ── Sedimentary strata ────────────────────────────────────────────────────────
uniform float strata_frequency   : hint_range(1.0,  64.0) = 22.0;
uniform float strata_contrast    : hint_range(0.0,  1.0)  = 0.82;
uniform float strata_warp        : hint_range(0.0,  4.0)  = 1.4;   // adds horizontal bend
uniform float strata_band_count  : hint_range(2.0,  8.0)  = 4.0;   // colour bands per cycle

// ── Surface micro-texture ─────────────────────────────────────────────────────
uniform float grit_strength : hint_range(0.0, 1.0)   = 0.42;
uniform float grit_scale    : hint_range(0.001, 0.4)  = 0.19;
uniform float crack_scale   : hint_range(0.001, 0.1)  = 0.028;  // duricrust cracking
uniform float crack_depth   : hint_range(0.0, 1.0)    = 0.38;   // how dark cracks go

// ── Wind scour ────────────────────────────────────────────────────────────────
uniform float scour_strength : hint_range(0.0, 1.0)  = 0.28;
uniform float scour_scale    : hint_range(0.001, 0.1) = 0.031;

// ── Specular / roughness ──────────────────────────────────────────────────────
uniform float roughness_sand : hint_range(0.0, 1.0) = 0.97;
uniform float roughness_rock : hint_range(0.0, 1.0) = 0.84;
uniform float specular_rock  : hint_range(0.0, 1.0) = 0.06;    // slight feldspar glint

// ── Atmospheric distance fade ─────────────────────────────────────────────────
uniform float distance_fade_start : hint_range(100.0, 2000.0) = 600.0;
uniform float distance_fade_end   : hint_range(100.0, 4000.0) = 1400.0;
uniform float distance_fog_max    : hint_range(0.0, 1.0)      = 0.48;

// ── Varyings ──────────────────────────────────────────────────────────────────
varying float v_height;
varying vec3  v_world_pos;
varying vec3  v_world_normal;

// ─────────────────────────────────────────────────────────────────────────────
//  Helper functions
// ─────────────────────────────────────────────────────────────────────────────

vec3 get_triplanar_weights(vec3 normal) {
	vec3 b = abs(normal);
	b = max(b, vec3(0.0001));
	b = pow(b, vec3(8.0));   // sharper triplanar seam
	return b / (b.x + b.y + b.z);
}

// Analytic sine-based field — no texture sampler needed
float world_field(vec3 p, float scale) {
	float v = sin(p.y * scale * 0.52 + p.z * scale * 1.13 + 0.9)
	        + sin(p.x * scale * 0.88 - p.z * scale * 0.72 - 0.7)
	        + sin(p.x * scale * 1.06 + p.y * scale * 0.34 + 1.7);
	return v * (1.0 / 6.0) + 0.5;
}

// Two-frequency version for richer detail
float world_field2(vec3 p, float scale) {
	return mix(world_field(p, scale), world_field(p + vec3(17.3, -9.1, 22.7), scale * 1.9), 0.45);
}

// Anisotropic field oriented along wind_direction
float aniso_field(vec3 p, float scale) {
	vec2 wd = normalize(wind_direction);
	float along  = p.x * wd.x + p.z * wd.y;
	float across = -p.x * wd.y + p.z * wd.x;
	return sin(along * scale * 7.1 + 0.4) * 0.5 + 0.5
	     + sin(along * scale * 13.7 - 0.9) * 0.25 + 0.25
	     + sin(across * scale * 2.3 + along * scale * 0.4 + 1.1) * 0.125 + 0.125;
}

// Pseudo-Worley crack pattern (analytic)
float crack_pattern(vec3 p, float scale) {
	vec3 q = p * scale;
	// Use repeating trig as a cheap Worley-like estimator
	float cx = abs(fract(q.x * 1.618 + q.z * 0.832) - 0.5);
	float cz = abs(fract(q.z * 1.732 - q.x * 0.577) - 0.5);
	return 1.0 - smoothstep(0.0, 0.12, min(cx, cz));
}

// Three-component grit
vec3 triplanar_noise(vec3 p, vec3 n, float scale) {
	vec3 w = get_triplanar_weights(n);
	vec3 yz = vec3(sin(p.y*scale*1.7 + p.z*scale*2.9),
	               sin(p.y*scale*2.3 - p.z*scale*1.6 + 1.7),
	               sin(p.y*scale*1.1 + p.z*scale*2.1 + 2.4));
	vec3 xz = vec3(sin(p.x*scale*2.4 + p.z*scale*1.8 + 0.7),
	               sin(p.x*scale*1.3 - p.z*scale*2.7 + 2.1),
	               sin(p.x*scale*2.0 + p.z*scale*1.2 + 1.2));
	vec3 xy = vec3(sin(p.x*scale*2.8 + p.y*scale*1.5 + 1.4),
	               sin(p.x*scale*1.6 - p.y*scale*2.2 + 0.5),
	               sin(p.x*scale*2.1 + p.y*scale*1.9 + 2.8));
	return (yz * w.x + xz * w.y + xy * w.z) * 0.5 + 0.5;
}

// ─────────────────────────────────────────────────────────────────────────────

void vertex() {
	v_height      = clamp(VERTEX.y / max(height_scale, 0.001), 0.0, 1.0);
	v_world_pos   = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// ── Runtime terrain data ─────────────────────────────────────────────────
	vec4  rt_sample      = texture(terrain_data, UV);
	float rt_mix         = step(0.5, rt_sample.a);
	float fallback_h     = texture(height_map, UV).r;
	float height01       = mix(fallback_h, rt_sample.r, rt_mix);
	float slope01        = max(mix(clamp(1.0 - NORMAL.y,   0.0, 1.0), rt_sample.g, rt_mix),
	                           clamp(1.0 - v_world_normal.y, 0.0, 1.0));
	float dust01         = mix(clamp(1.0 - height01, 0.0, 1.0), rt_sample.b, rt_mix);

	// ── Slope ramp ───────────────────────────────────────────────────────────
	float slope_thr  = sin(radians(slope_threshold_degrees));
	float slope_tr   = sin(radians(slope_transition_degrees));
	float rock_mask  = smoothstep(slope_thr - slope_tr, slope_thr + slope_tr, slope01);
	float sand_mask  = 1.0 - rock_mask;

	// ── Tonal field samples ──────────────────────────────────────────────────
	vec3  wp  = v_world_pos;
	vec3  wn  = v_world_normal;
	float broad  = world_field2(wp,                        world_variation_scale);
	float detail = world_field2(wp + vec3(37.0, 11.0, -23.0), detail_variation_scale);
	float detail2 = world_field(wp + vec3(-14.0, 5.0, 31.0),  detail_variation_scale * 2.1);
	vec3  grit   = triplanar_noise(wp + vec3(11.0, -7.0, 19.0), wn, grit_scale);

	// ─── SAND / silt layer ───────────────────────────────────────────────────

	// Aeolian ripples oriented to wind
	float ripple_along   = aniso_field(wp, ripple_scale);
	float ripple_cross   = world_field(wp + vec3(-8.0, 2.0, 15.0), ripple_scale * 0.4);
	float ripple_mix     = clamp(ripple_along * 0.7 + ripple_cross * 0.3, 0.0, 1.0);

	// Brightness modulation: crest = lighter, trough = darker
	float ripple_bright  = mix(0.84, 1.12, ripple_mix * ripple_strength);
	vec3  sand_base      = mix(sand_shadow_color, sand_color,
	                           clamp(0.42 + dust01 * 0.28 + broad * 0.30, 0.0, 1.0));
	vec3  sand_albedo    = sand_base * ripple_bright;

	// Duricrust on flat areas: cracked dark crust with bright break
	float flat_mask = clamp((v_world_normal.y - 0.72) * 5.0, 0.0, 1.0);
	float crust_age = clamp(1.0 - height01 * 1.6, 0.0, 1.0);   // low areas more crusted
	float crack_amt = crack_pattern(wp, crack_scale) * flat_mask * crust_age;
	vec3  crust_color = mix(duricrust_color, sand_color * 1.18, detail2 * 0.4);
	sand_albedo = mix(sand_albedo, crust_color, flat_mask * crust_age * 0.52);
	sand_albedo = mix(sand_albedo, sand_albedo * (1.0 - crack_depth), crack_amt);

	// ─── ROCK / cliff layer ──────────────────────────────────────────────────

	// Multi-band strata with domain warp
	float warp_offset = (detail - 0.5) * strata_warp + grit.r * (strata_warp * 0.5);
	float strata_axis  = wp.y * 0.055 + warp_offset;
	float strata_phase = strata_axis * strata_frequency;

	// Primary band
	float sw1     = sin(strata_phase) * 0.5 + 0.5;
	float sm1     = smoothstep(0.5 - strata_contrast * 0.38, 0.5 + strata_contrast * 0.38, sw1);

	// Secondary sub-band (half frequency = thicker layers)
	float sw2     = sin(strata_phase * 0.48 + 0.6) * 0.5 + 0.5;
	float sm2     = smoothstep(0.42, 0.78, sw2);

	// Tertiary very-thin dark seam
	float sw3     = abs(fract(strata_phase * 0.24 + 0.1) - 0.5) * 2.0;
	float seam    = 1.0 - smoothstep(0.0, 0.18, sw3);

	// Colour assembly: 3 strata tones blended
	vec3 rock_base = mix(strata_dark_color, strata_mid_color, sm2);
	rock_base      = mix(rock_base, strata_bright_color, sm1 * 0.7);
	rock_base      = mix(rock_base, strata_dark_color * 0.6, seam * 0.55);   // dark seam
	// Surface variation
	rock_base      = mix(rock_base * 0.76, rock_base * 1.14,
	                     clamp(detail * 0.65 + grit.g * 0.35, 0.0, 1.0));
	// Cliff face wash (lightens face normals pointing away from vertical)
	float cliff_face = clamp(1.0 - v_world_normal.y * 2.0, 0.0, 1.0);
	vec3  rock_albedo = mix(rock_base, cliff_tint, cliff_face * 0.18);

	// Sediment ledges — bright rim at strata boundaries
	float ledge_factor = smoothstep(0.34, 0.86, abs(fract(strata_phase * 0.5) - 0.5) * 2.0);
	rock_albedo = mix(rock_albedo,
	                  mix(strata_bright_color, haze_tint, 0.18),
	                  ledge_factor * 0.20);

	// ─── Wind scour marks (anisotropic streaks on any surface) ──────────────
	float scour_field  = aniso_field(wp, scour_scale);
	float scour_streak = smoothstep(0.55, 0.72, scour_field);
	float scour_mask   = clamp(scour_strength * (1.0 - slope01 * 1.2), 0.0, 0.30);
	vec3  scour_dark   = mix(strata_dark_color, sand_shadow_color, 0.5);

	// ─── Composite ──────────────────────────────────────────────────────────
	vec3 base_color = mix(sand_albedo, rock_albedo, rock_mask);
	base_color = mix(base_color, scour_dark, scour_streak * scour_mask);

	// Ambient occlusion approximation via grit cavity
	float cavity = (1.0 - grit.b) * grit_strength;
	base_color *= 1.0 - cavity * mix(0.07, 0.22, rock_mask);

	// ─── Atmospheric distance fade ───────────────────────────────────────────
	float cam_dist  = length(wp - CAMERA_POSITION_WORLD);
	float dist_fade = clamp((cam_dist - distance_fade_start) /
	                        max(distance_fade_end - distance_fade_start, 1.0), 0.0, distance_fog_max);
	base_color = mix(base_color, haze_tint, dist_fade * 0.60);

	// ─── Normal map — two-octave layered relief ──────────────────────────────
	// Coarse macro bumps
	vec3 macro_n = normalize(vec3(
		(detail  - 0.5) * 0.55,
		1.0,
		(broad   - 0.5) * 0.55
	));
	// Fine grit perturbation
	vec3 grit_n = normalize(mix(vec3(0.0, 0.0, 1.0), grit * 2.0 - 1.0, grit_strength));
	// Ripple bump on flat sand
	float ripple_bump  = (ripple_mix - 0.5) * ripple_strength * sand_mask;
	vec3  ripple_n     = normalize(vec3(ripple_bump * 0.5, 1.0, ripple_bump * 0.3));

	vec3 combined_n    = normalize(macro_n * 0.55 + grit_n * 0.30 + ripple_n * 0.15);
	NORMAL_MAP         = combined_n;
	NORMAL_MAP_DEPTH   = mix(0.10, 0.42, grit_strength);

	// ─── PBR outputs ────────────────────────────────────────────────────────
	ALBEDO     = base_color;
	ROUGHNESS  = mix(roughness_sand,
	                 mix(roughness_rock, roughness_rock * 0.88, ledge_factor * 0.5),
	                 rock_mask) - grit.r * 0.06;
	SPECULAR   = mix(0.02, specular_rock, rock_mask * sm1 * 0.8);   // feldspar caps catch light
}
