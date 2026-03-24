## Shared visual profile for Mars exteriors and diegetic UI.
## This pass targets a more NASA-real Jezero look: lower saturation,
## thinner haze, darker basalt shadows, and restrained interface glow.
class_name MarsExteriorProfile
extends RefCounted

const SKY_RAYLEIGH_COLOR := Color(0.66, 0.55, 0.47, 1.0)
const SKY_MIE_COLOR := Color(0.79, 0.67, 0.58, 1.0)
const SKY_TURBIDITY: float = 6.6
const SKY_GROUND_COLOR := Color(0.12, 0.09, 0.07, 1.0)

const FOG_LIGHT_COLOR := Color(0.63, 0.54, 0.48, 1.0)
const FOG_DENSITY: float = 0.00016
const FOG_AERIAL_PERSPECTIVE: float = 0.11
const FOG_SUN_SCATTER: float = 0.09
const FOG_HEIGHT: float = 0.0
const FOG_HEIGHT_DENSITY: float = 0.022

const AMBIENT_LIGHT_COLOR := Color(0.16, 0.14, 0.12, 1.0)
const AMBIENT_LIGHT_ENERGY: float = 0.46

const KEY_LIGHT_COLOR := Color(1.0, 0.92, 0.85, 1.0)
const KEY_LIGHT_ENERGY: float = 2.5
const KEY_LIGHT_ROTATION := Vector3(-38.0, 50.0, 0.0)
const KEY_SHADOW_MAX_DISTANCE: float = 2200.0

const FILL_LIGHT_COLOR := Color(0.54, 0.50, 0.47, 1.0)
const FILL_LIGHT_ENERGY: float = 0.04
const FILL_LIGHT_ROTATION := Vector3(-18.0, -112.0, 0.0)

const TERRAIN_SAND_COLOR       := Color(0.54, 0.35, 0.24, 1.0)
const TERRAIN_SAND_SHADOW      := Color(0.25, 0.16, 0.12, 1.0)
const TERRAIN_DURICRUST_COLOR  := Color(0.42, 0.26, 0.18, 1.0)
const TERRAIN_STRATA_DARK      := Color(0.15, 0.10, 0.08, 1.0)
const TERRAIN_STRATA_MID       := Color(0.32, 0.21, 0.16, 1.0)
const TERRAIN_STRATA_BRIGHT    := Color(0.49, 0.31, 0.22, 1.0)
const TERRAIN_CLIFF_TINT       := Color(0.36, 0.24, 0.18, 1.0)
const TERRAIN_HAZE_TINT        := Color(0.62, 0.54, 0.49, 1.0)

const TERRAIN_RIPPLE_STRENGTH: float = 0.24
const TERRAIN_WIND_DIRECTION := Vector2(0.72, 0.38)
const TERRAIN_SCOUR_STRENGTH: float = 0.16
const TERRAIN_CRACK_DEPTH: float = 0.30
const TERRAIN_GRIT_STRENGTH: float = 0.32
const TERRAIN_WORLD_VARIATION_SCALE: float = 0.011
const TERRAIN_DETAIL_VARIATION_SCALE: float = 0.052

const TERRAIN_STRATA_FREQUENCY: float = 18.0
const TERRAIN_STRATA_CONTRAST: float = 0.74
const TERRAIN_STRATA_WARP: float = 1.1
const TERRAIN_STRATA_BAND_COUNT: float = 4.0

const TERRAIN_SLOPE_THRESHOLD: float = 37.0
const TERRAIN_SLOPE_TRANSITION: float = 7.0

const TERRAIN_DISTANCE_FADE_START: float = 960.0
const TERRAIN_DISTANCE_FADE_END: float = 2100.0
const TERRAIN_DISTANCE_FOG_MAX: float = 0.22

const SEAL_COLOR := Color(0.16, 0.11, 0.09, 1.0)

const HUD_FRAME_DARK := Color(0.06, 0.06, 0.06, 0.56)
const HUD_FRAME_MID := Color(0.44, 0.41, 0.37, 0.84)
const HUD_FRAME_GLOW := Color(0.74, 0.70, 0.64, 0.12)
const HUD_SLOT_GLOW := Color(0.86, 0.80, 0.72, 0.24)
const HUD_ALERT := Color(0.93, 0.70, 0.39, 0.92)
const HUD_TEXT := Color(0.91, 0.90, 0.86, 0.98)
const HUD_TEXT_DIM := Color(0.72, 0.70, 0.66, 0.76)
const HUD_PANEL_BG := Color(0.06, 0.06, 0.06, 0.18)
const HUD_LINE := Color(0.72, 0.68, 0.62, 0.24)
const HUD_RETICLE := Color(0.86, 0.82, 0.76, 0.34)
const HUD_GRID_FAINT := Color(0.82, 0.79, 0.73, 0.06)
const HUD_COMPASS := Color(0.94, 0.92, 0.88, 0.88)
const HUD_GLASS_EDGE := Color(0.68, 0.65, 0.60, 0.30)
const HUD_GLASS_SHEEN := Color(0.96, 0.95, 0.93, 0.05)
const HUD_JOYSTICK_RING := Color(0.72, 0.68, 0.61, 0.18)
const HUD_JOYSTICK_KNOB := Color(0.74, 0.71, 0.65, 0.22)
const HUD_LOG_TEXT := Color(0.84, 0.88, 0.90, 1.0)

const MENU_OVERLAY_TINT := Color(0.03, 0.03, 0.03, 0.34)
const MENU_FRAME_BG := Color(0.07, 0.06, 0.06, 0.80)
const MENU_FRAME_BORDER := Color(0.66, 0.61, 0.56, 0.34)
const MENU_SETTINGS_BG := Color(0.08, 0.07, 0.07, 0.92)
const MENU_SETTINGS_BORDER := Color(0.72, 0.66, 0.60, 0.38)
const MENU_TITLE_COLOR := Color(0.92, 0.90, 0.85, 1.0)
const MENU_SUBTITLE_COLOR := Color(0.72, 0.69, 0.65, 1.0)
const MENU_BUTTON_TEXT := Color(0.91, 0.89, 0.84, 1.0)
const MENU_BUTTON_TEXT_HOVER := Color(0.98, 0.96, 0.93, 1.0)
const MENU_BUTTON_TEXT_DISABLED := Color(0.44, 0.41, 0.39, 1.0)
const MENU_BUTTON_BG := Color(0.10, 0.09, 0.09, 0.88)
const MENU_BUTTON_BG_HOVER := Color(0.15, 0.13, 0.12, 0.92)
const MENU_BUTTON_BG_PRESSED := Color(0.08, 0.07, 0.07, 0.96)
const MENU_BUTTON_BG_DISABLED := Color(0.05, 0.05, 0.05, 0.72)
const MENU_BUTTON_BORDER := Color(0.62, 0.58, 0.52, 0.40)
const MENU_BUTTON_BORDER_HOVER := Color(0.80, 0.74, 0.67, 0.62)
const MENU_BUTTON_BORDER_PRESSED := Color(0.92, 0.80, 0.62, 0.74)
const MENU_GROUND_COLOR := Color(0.42, 0.28, 0.20, 1.0)
const MENU_DUNE_COLOR := Color(0.48, 0.33, 0.24, 1.0)
const MENU_MESA_COLORS := [
	Color(0.36, 0.25, 0.19, 1.0),
	Color(0.43, 0.30, 0.22, 1.0),
	Color(0.31, 0.22, 0.17, 1.0),
	Color(0.49, 0.34, 0.24, 1.0),
]

const INTRO_BACKGROUND_COLOR := Color(0.02, 0.02, 0.02, 1.0)
const INTRO_HINT_COLOR := Color(0.88, 0.86, 0.82, 0.74)
const INTRO_EDGE_TINT := Color(0.58, 0.50, 0.46, 1.0)

static func apply_environment(env: Environment) -> void:
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
	env.tonemap_mode = 3
	env.fog_enabled = true
	env.fog_light_color = FOG_LIGHT_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	env.fog_sun_scatter = FOG_SUN_SCATTER
	env.fog_height = FOG_HEIGHT
	env.fog_height_density = FOG_HEIGHT_DENSITY
	env.volumetric_fog_enabled = false

static func apply_sky_and_fog(env: Environment) -> void:
	apply_environment(env)

static func apply_menu_environment(env: Environment) -> void:
	apply_environment(env)
	env.fog_density = FOG_DENSITY * 0.72
	env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE * 0.78

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
	material.set_shader_parameter("sand_color", TERRAIN_SAND_COLOR)
	material.set_shader_parameter("sand_shadow_color", TERRAIN_SAND_SHADOW)
	material.set_shader_parameter("duricrust_color", TERRAIN_DURICRUST_COLOR)
	material.set_shader_parameter("strata_dark_color", TERRAIN_STRATA_DARK)
	material.set_shader_parameter("strata_mid_color", TERRAIN_STRATA_MID)
	material.set_shader_parameter("strata_bright_color", TERRAIN_STRATA_BRIGHT)
	material.set_shader_parameter("cliff_tint", TERRAIN_CLIFF_TINT)
	material.set_shader_parameter("haze_tint", TERRAIN_HAZE_TINT)
	material.set_shader_parameter("ripple_strength", TERRAIN_RIPPLE_STRENGTH)
	material.set_shader_parameter("wind_direction", TERRAIN_WIND_DIRECTION)
	material.set_shader_parameter("scour_strength", TERRAIN_SCOUR_STRENGTH)
	material.set_shader_parameter("crack_depth", TERRAIN_CRACK_DEPTH)
	material.set_shader_parameter("grit_strength", TERRAIN_GRIT_STRENGTH)
	material.set_shader_parameter("world_variation_scale", TERRAIN_WORLD_VARIATION_SCALE)
	material.set_shader_parameter("detail_variation_scale", TERRAIN_DETAIL_VARIATION_SCALE)
	material.set_shader_parameter("strata_frequency", TERRAIN_STRATA_FREQUENCY)
	material.set_shader_parameter("strata_contrast", TERRAIN_STRATA_CONTRAST)
	material.set_shader_parameter("strata_warp", TERRAIN_STRATA_WARP)
	material.set_shader_parameter("strata_band_count", TERRAIN_STRATA_BAND_COUNT)
	material.set_shader_parameter("slope_threshold_degrees", TERRAIN_SLOPE_THRESHOLD)
	material.set_shader_parameter("slope_transition_degrees", TERRAIN_SLOPE_TRANSITION)
	material.set_shader_parameter("distance_fade_start", TERRAIN_DISTANCE_FADE_START)
	material.set_shader_parameter("distance_fade_end", TERRAIN_DISTANCE_FADE_END)
	material.set_shader_parameter("distance_fog_max", TERRAIN_DISTANCE_FOG_MAX)

static func make_ui_glass_style(bg_color: Color, border_color: Color, corner_radius: int = 14, shadow_alpha: float = 0.14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	style.shadow_size = 10
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.4
	return style

static func make_menu_button_style(bg_color: Color, border_color: Color, corner_radius: int = 12) -> StyleBoxFlat:
	var style := make_ui_glass_style(bg_color, border_color, corner_radius, 0.0)
	style.shadow_size = 0
	return style

static func make_seal_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SEAL_COLOR
	mat.roughness = 0.99
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
