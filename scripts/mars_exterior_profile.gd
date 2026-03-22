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
# FOG — atmospheric haze for depth separation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const FOG_LIGHT_COLOR := Color(0.84, 0.67, 0.52, 1.0)       # Warm dust-haze
const FOG_DENSITY: float = 0.00042                            # Slightly denser for realism
const FOG_AERIAL_PERSPECTIVE: float = 0.32                    # More aerial depth on mesas
const FOG_SUN_SCATTER: float = 0.28                           # Stronger Mie scatter bloom
const FOG_HEIGHT: float = 0.0
const FOG_HEIGHT_DENSITY: float = 0.055                       # Haze thicker near ground

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AMBIENT — warm, low value so shadows read as dark brown/maroon
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const AMBIENT_LIGHT_COLOR := Color(0.22, 0.14, 0.09, 1.0)
const AMBIENT_LIGHT_ENERGY: float = 0.72

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# KEY LIGHT — hard directional, upper-right, warm white
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const KEY_LIGHT_COLOR := Color(1.0, 0.88, 0.74, 1.0)
const KEY_LIGHT_ENERGY: float = 2.65
const KEY_LIGHT_ROTATION := Vector3(-35.0, 56.0, 0.0)     # casts diagonal shadow
const KEY_SHADOW_MAX_DISTANCE: float = 1800.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FILL LIGHT — silhouette readability only, no shadow flattening
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const FILL_LIGHT_COLOR := Color(0.78, 0.58, 0.42, 1.0)
const FILL_LIGHT_ENERGY: float = 0.14
const FILL_LIGHT_ROTATION := Vector3(-22.0, -118.0, 0.0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TERRAIN SHADER — realistic Martian iron-oxide palette
#   Sand/silt:   aeolian fine grain (lighter, warm ochre)
#   Duricrust:   hardened surface layer (darker, breaking to bright)
#   Strata mid:  iron-oxide sienna
#   Strata dark: basaltic base layer
#   Strata bright: ochre caprock / desert varnish
#   Cliff tint: lighter face wash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const TERRAIN_SAND_COLOR       := Color(0.76, 0.42, 0.20, 1.0)   # warm ochre silt
const TERRAIN_SAND_SHADOW      := Color(0.44, 0.22, 0.10, 1.0)   # shadow hollows
const TERRAIN_DURICRUST_COLOR  := Color(0.52, 0.28, 0.12, 1.0)   # hardened crust
const TERRAIN_STRATA_DARK      := Color(0.26, 0.11, 0.06, 1.0)   # basalt base
const TERRAIN_STRATA_MID       := Color(0.46, 0.21, 0.10, 1.0)   # iron-oxide sienna
const TERRAIN_STRATA_BRIGHT    := Color(0.68, 0.29, 0.09, 1.0)   # ochre caprock
const TERRAIN_CLIFF_TINT       := Color(0.42, 0.20, 0.09, 1.0)   # cliff face wash
const TERRAIN_HAZE_TINT        := Color(0.88, 0.61, 0.44, 1.0)   # atmospheric haze

# ── Scale / surface ──────────────────────────────────────────────────────
const TERRAIN_RIPPLE_STRENGTH: float = 0.40
const TERRAIN_WIND_DIRECTION := Vector2(0.72, 0.38)               # XZ normalised
const TERRAIN_SCOUR_STRENGTH: float = 0.26
const TERRAIN_CRACK_DEPTH: float = 0.36
const TERRAIN_GRIT_STRENGTH: float = 0.42
const TERRAIN_WORLD_VARIATION_SCALE: float = 0.013
const TERRAIN_DETAIL_VARIATION_SCALE: float = 0.065

# ── Strata ───────────────────────────────────────────────────────────────
const TERRAIN_STRATA_FREQUENCY: float = 22.0
const TERRAIN_STRATA_CONTRAST: float = 0.82
const TERRAIN_STRATA_WARP: float = 1.4
const TERRAIN_STRATA_BAND_COUNT: float = 4.0

# ── Slope thresholds ──────────────────────────────────────────────────────
const TERRAIN_SLOPE_THRESHOLD: float = 40.0
const TERRAIN_SLOPE_TRANSITION: float = 8.0

# ── Distance fade ─────────────────────────────────────────────────────────
const TERRAIN_DISTANCE_FADE_START: float = 600.0
const TERRAIN_DISTANCE_FADE_END: float = 1400.0
const TERRAIN_DISTANCE_FOG_MAX: float = 0.48

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SEAL MATERIAL — terrain underside / edge skirt
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const SEAL_COLOR := Color(0.22, 0.10, 0.06, 1.0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# HELPERS
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
	env.tonemap_mode = 3  # ACES
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
	# Colour palette
	material.set_shader_parameter("sand_color",          TERRAIN_SAND_COLOR)
	material.set_shader_parameter("sand_shadow_color",   TERRAIN_SAND_SHADOW)
	material.set_shader_parameter("duricrust_color",     TERRAIN_DURICRUST_COLOR)
	material.set_shader_parameter("strata_dark_color",   TERRAIN_STRATA_DARK)
	material.set_shader_parameter("strata_mid_color",    TERRAIN_STRATA_MID)
	material.set_shader_parameter("strata_bright_color", TERRAIN_STRATA_BRIGHT)
	material.set_shader_parameter("cliff_tint",          TERRAIN_CLIFF_TINT)
	material.set_shader_parameter("haze_tint",           TERRAIN_HAZE_TINT)
	# Surface detail
	material.set_shader_parameter("ripple_strength",         TERRAIN_RIPPLE_STRENGTH)
	material.set_shader_parameter("wind_direction",          TERRAIN_WIND_DIRECTION)
	material.set_shader_parameter("scour_strength",          TERRAIN_SCOUR_STRENGTH)
	material.set_shader_parameter("crack_depth",             TERRAIN_CRACK_DEPTH)
	material.set_shader_parameter("grit_strength",           TERRAIN_GRIT_STRENGTH)
	material.set_shader_parameter("world_variation_scale",   TERRAIN_WORLD_VARIATION_SCALE)
	material.set_shader_parameter("detail_variation_scale",  TERRAIN_DETAIL_VARIATION_SCALE)
	# Strata
	material.set_shader_parameter("strata_frequency",   TERRAIN_STRATA_FREQUENCY)
	material.set_shader_parameter("strata_contrast",    TERRAIN_STRATA_CONTRAST)
	material.set_shader_parameter("strata_warp",        TERRAIN_STRATA_WARP)
	material.set_shader_parameter("strata_band_count",  TERRAIN_STRATA_BAND_COUNT)
	# Slope
	material.set_shader_parameter("slope_threshold_degrees",  TERRAIN_SLOPE_THRESHOLD)
	material.set_shader_parameter("slope_transition_degrees", TERRAIN_SLOPE_TRANSITION)
	# Distance fade
	material.set_shader_parameter("distance_fade_start", TERRAIN_DISTANCE_FADE_START)
	material.set_shader_parameter("distance_fade_end",   TERRAIN_DISTANCE_FADE_END)
	material.set_shader_parameter("distance_fog_max",    TERRAIN_DISTANCE_FOG_MAX)

static func make_seal_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SEAL_COLOR
	mat.roughness = 0.99
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
