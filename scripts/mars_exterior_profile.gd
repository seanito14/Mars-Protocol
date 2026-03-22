## Canonical visual profile for all exterior Mars scenes.
## Every exterior scene must reference these values so sky, fog, lighting,
## terrain palette, and camera framing stay locked to STRICT-COPY.jpg.
class_name MarsExteriorProfile
extends RefCounted

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SKY — pale dusty gradient, NOT saturated sci-fi orange
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const SKY_RAYLEIGH_COLOR := Color(0.88, 0.72, 0.58, 1.0)   # Desaturated warm peach
const SKY_MIE_COLOR := Color(0.96, 0.84, 0.68, 1.0)         # Pale golden horizon bloom
const SKY_TURBIDITY: float = 10.8                             # Lower = cleaner gradient
const SKY_GROUND_COLOR := Color(0.18, 0.1, 0.06, 1.0)       # Dark rust under-hemisphere

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FOG — atmospheric haze for depth separation only
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const FOG_LIGHT_COLOR := Color(0.82, 0.66, 0.52, 1.0)       # Warm, NOT vivid orange
const FOG_DENSITY: float = 0.00038                            # Subtle — readable ground
const FOG_AERIAL_PERSPECTIVE: float = 0.26                    # Soften distant mesas gently
const FOG_SUN_SCATTER: float = 0.22                           # Modest sun bloom in haze
const FOG_HEIGHT: float = 0.0                                 # Ground-level fog plane
const FOG_HEIGHT_DENSITY: float = 0.045                       # Slight density falloff upward

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AMBIENT — warm, LOW value so shadows read dark brown/maroon
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const AMBIENT_LIGHT_COLOR := Color(0.2, 0.13, 0.08, 1.0)
const AMBIENT_LIGHT_ENERGY: float = 0.75

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# KEY LIGHT — hard directional, upper-right, warm white
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const KEY_LIGHT_COLOR := Color(1.0, 0.88, 0.74, 1.0)
const KEY_LIGHT_ENERGY: float = 2.65
const KEY_LIGHT_ROTATION := Vector3(-35.0, 56.0, 0.0)        # degrees — casts diagonal shadow
const KEY_SHADOW_MAX_DISTANCE: float = 1800.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FILL LIGHT — silhouette readability only, NO shadow flattening
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const FILL_LIGHT_COLOR := Color(0.78, 0.58, 0.42, 1.0)
const FILL_LIGHT_ENERGY: float = 0.14
const FILL_LIGHT_ROTATION := Vector3(-22.0, -118.0, 0.0)     # degrees

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TERRAIN SHADER — ground DARKER than sky, realistic sedimentary tones
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const TERRAIN_DUST_COLOR := Color(0.68, 0.39, 0.2, 1.0)      # Sandy dune tops
const TERRAIN_CLIFF_COLOR := Color(0.48, 0.23, 0.13, 1.0)    # Mid-cliff sienna
const TERRAIN_ROCK_COLOR := Color(0.26, 0.14, 0.09, 1.0)     # Dark base rock
const TERRAIN_SHADOW_TINT := Color(0.14, 0.06, 0.04, 1.0)    # Deep shadow maroon
const TERRAIN_RIPPLE_STRENGTH: float = 0.03                   # Subtle, NOT flashy
const TERRAIN_RIDGE_STRENGTH: float = 0.08                    # Geologic, NOT decorative
const TERRAIN_STEEP_SHADOW_STRENGTH: float = 0.22             # Cliff self-shadow
const TERRAIN_DUST_SHADOW_STRENGTH: float = 0.05              # Low-area darkening
const TERRAIN_BRIGHTNESS_FLOOR: float = 0.74                  # Darker floor reads as ground
const TERRAIN_BRIGHTNESS_PEAK: float = 0.98                   # Never as bright as sky
const TERRAIN_WORLD_VARIATION_SCALE: float = 0.014            # Broad world-space tonal breakup
const TERRAIN_DETAIL_VARIATION_SCALE: float = 0.05            # Fine stable grain
const TERRAIN_DISTANCE_FADE_END: float = 1400.0               # Distant mesas soften, near ground stays stable
const TERRAIN_CLIFF_BLEND_START: float = 0.18
const TERRAIN_CLIFF_BLEND_END: float = 0.52
const TERRAIN_CAP_BLEND_START: float = 0.58
const TERRAIN_CAP_BLEND_END: float = 0.92

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SEAL MATERIAL — terrain underside / edge skirt
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const SEAL_COLOR := Color(0.26, 0.13, 0.08, 1.0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HELPERS — apply the profile to scene nodes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

static func apply_sky_and_fog(env: Environment) -> void:
	var sky_material := PhysicalSkyMaterial.new()
	sky_material.rayleigh_color = SKY_RAYLEIGH_COLOR
	sky_material.mie_color = SKY_MIE_COLOR
	sky_material.turbidity = SKY_TURBIDITY
	sky_material.ground_color = SKY_GROUND_COLOR
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_LIGHT_COLOR
	env.ambient_light_energy = AMBIENT_LIGHT_ENERGY
	env.tonemap_mode = 3  # ACES (matches .tscn files)
	env.fog_enabled = true
	env.fog_light_color = FOG_LIGHT_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	env.fog_sun_scatter = FOG_SUN_SCATTER
	env.fog_height = FOG_HEIGHT
	env.fog_height_density = FOG_HEIGHT_DENSITY

static func apply_key_light(light: DirectionalLight3D) -> void:
	light.rotation_degrees = KEY_LIGHT_ROTATION
	light.light_color = KEY_LIGHT_COLOR
	light.light_energy = KEY_LIGHT_ENERGY
	light.shadow_enabled = true
	light.directional_shadow_max_distance = KEY_SHADOW_MAX_DISTANCE

static func apply_fill_light(light: DirectionalLight3D) -> void:
	light.rotation_degrees = FILL_LIGHT_ROTATION
	light.light_color = FILL_LIGHT_COLOR
	light.light_energy = FILL_LIGHT_ENERGY
	light.shadow_enabled = false

static func apply_terrain_shader(material: ShaderMaterial) -> void:
	material.set_shader_parameter("dust_color", TERRAIN_DUST_COLOR)
	material.set_shader_parameter("cliff_color", TERRAIN_CLIFF_COLOR)
	material.set_shader_parameter("rock_color", TERRAIN_ROCK_COLOR)
	material.set_shader_parameter("shadow_tint", TERRAIN_SHADOW_TINT)
	material.set_shader_parameter("ripple_strength", TERRAIN_RIPPLE_STRENGTH)
	material.set_shader_parameter("ridge_strength", TERRAIN_RIDGE_STRENGTH)
	material.set_shader_parameter("steep_shadow_strength", TERRAIN_STEEP_SHADOW_STRENGTH)
	material.set_shader_parameter("dust_shadow_strength", TERRAIN_DUST_SHADOW_STRENGTH)
	material.set_shader_parameter("brightness_floor", TERRAIN_BRIGHTNESS_FLOOR)
	material.set_shader_parameter("brightness_peak", TERRAIN_BRIGHTNESS_PEAK)
	material.set_shader_parameter("world_variation_scale", TERRAIN_WORLD_VARIATION_SCALE)
	material.set_shader_parameter("detail_variation_scale", TERRAIN_DETAIL_VARIATION_SCALE)
	material.set_shader_parameter("distance_fade_end", TERRAIN_DISTANCE_FADE_END)
	material.set_shader_parameter("cliff_blend_start", TERRAIN_CLIFF_BLEND_START)
	material.set_shader_parameter("cliff_blend_end", TERRAIN_CLIFF_BLEND_END)
	material.set_shader_parameter("cap_blend_start", TERRAIN_CAP_BLEND_START)
	material.set_shader_parameter("cap_blend_end", TERRAIN_CAP_BLEND_END)

static func make_seal_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SEAL_COLOR
	mat.roughness = 0.99
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
