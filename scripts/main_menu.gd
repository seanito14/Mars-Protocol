extends Control

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MASTER_VOLUME: float = 1.0
const DEFAULT_MOUSE_SENSITIVITY: float = 0.0021
const DEFAULT_FOV: float = 76.0

const MIN_MOUSE_SENSITIVITY: float = 0.0008
const MAX_MOUSE_SENSITIVITY: float = 0.0055
const MIN_FOV: float = 60.0
const MAX_FOV: float = 100.0

@onready var overlay_tint: ColorRect = $OverlayTint
@onready var chrome_frame: Panel = $ChromeFrame
@onready var subtitle_label: Label = $ChromeFrame/ContentMargin/ContentVBox/SubtitleLabel
@onready var new_game_button: Button = $ChromeFrame/ContentMargin/ContentVBox/ButtonColumn/NewGameButton
@onready var continue_button: Button = $ChromeFrame/ContentMargin/ContentVBox/ButtonColumn/ContinueButton
@onready var settings_button: Button = $ChromeFrame/ContentMargin/ContentVBox/ButtonColumn/SettingsButton
@onready var quit_button: Button = $ChromeFrame/ContentMargin/ContentVBox/ButtonColumn/QuitButton
@onready var settings_panel: Panel = $ChromeFrame/SettingsPanel
@onready var close_settings_button: Button = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/CloseSettingsButton
@onready var volume_slider: HSlider = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/VolumeRow/VolumeSlider
@onready var volume_value: Label = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/VolumeRow/VolumeHeader/VolumeValue
@onready var sensitivity_slider: HSlider = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/SensitivityRow/SensitivitySlider
@onready var sensitivity_value: Label = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/SensitivityRow/SensitivityHeader/SensitivityValue
@onready var fov_slider: HSlider = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/FovRow/FovSlider
@onready var fov_value: Label = $ChromeFrame/SettingsPanel/SettingsMargin/SettingsVBox/FovRow/FovHeader/FovValue

var menu_background_viewport: SubViewport
var menu_background_camera: Camera3D
var background_focus: Vector3 = Vector3(0.0, 26.0, -52.0)
var flyover_time: float = 0.0

var master_volume: float = DEFAULT_MASTER_VOLUME
var mouse_sensitivity_setting: float = DEFAULT_MOUSE_SENSITIVITY
var fov_setting: float = DEFAULT_FOV

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_menu_background()
	_style_menu()
	_load_settings()
	_refresh_subtitle()
	_sync_settings_ui()
	_apply_audio_volume()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()

	if not FileAccess.file_exists("user://savegame.json"):
		continue_button.disabled = true

func _process(delta: float) -> void:
	if menu_background_camera == null:
		return
	flyover_time += delta
	var orbit_radius_x := 186.0
	var orbit_radius_z := 148.0
	var x := sin(flyover_time * 0.11) * orbit_radius_x
	var z := cos(flyover_time * 0.09) * orbit_radius_z - 146.0
	var y := 56.0 + (sin(flyover_time * 0.21) * 6.5)
	menu_background_camera.global_position = Vector3(x, y, z)
	var drift_focus := background_focus + Vector3(sin(flyover_time * 0.16) * 18.0, sin(flyover_time * 0.12) * 3.2, cos(flyover_time * 0.13) * 14.0)
	menu_background_camera.look_at(drift_focus, Vector3.UP)

func _on_new_game_pressed() -> void:
	_save_settings()
	if GameState.has_method("reset_game"):
		GameState.call("reset_game")
	if GameState.has_method("save_game"):
		GameState.call("save_game")
	get_tree().change_scene_to_file("res://scenes/opening_intro.tscn")

func _on_continue_pressed() -> void:
	_save_settings()
	if GameState.has_method("load_game"):
		if GameState.call("load_game"):
			get_tree().change_scene_to_file("res://scenes/landing_valley.tscn")
			return
	get_tree().change_scene_to_file("res://scenes/landing_valley.tscn")

func _on_settings_pressed() -> void:
	settings_panel.visible = true
	settings_button.disabled = true

func _on_close_settings_pressed() -> void:
	settings_panel.visible = false
	settings_button.disabled = false

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_volume_slider_changed(value: float) -> void:
	master_volume = clampf(value / 100.0, 0.0, 1.0)
	volume_value.text = "%d%%" % int(round(value))
	_apply_audio_volume()
	_save_settings()

func _on_sensitivity_slider_changed(value: float) -> void:
	mouse_sensitivity_setting = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	sensitivity_value.text = "%.2f" % (mouse_sensitivity_setting * 1000.0)
	_save_settings()

func _on_fov_slider_changed(value: float) -> void:
	fov_setting = clampf(value, MIN_FOV, MAX_FOV)
	fov_value.text = "%d°" % int(round(fov_setting))
	_save_settings()

func _on_viewport_size_changed() -> void:
	if menu_background_viewport == null:
		return
	var vp_size := get_viewport_rect().size
	menu_background_viewport.size = Vector2i(maxi(int(vp_size.x), 1), maxi(int(vp_size.y), 1))

func _build_menu_background() -> void:
	var background_container := SubViewportContainer.new()
	background_container.name = "MenuBackground"
	background_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_container.stretch = false
	add_child(background_container)
	move_child(background_container, 0)

	menu_background_viewport = SubViewport.new()
	menu_background_viewport.name = "BackdropViewport"
	menu_background_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	menu_background_viewport.msaa_3d = Viewport.MSAA_2X
	menu_background_viewport.size = Vector2i(2360, 1640)
	background_container.add_child(menu_background_viewport)

	var backdrop_root := Node3D.new()
	backdrop_root.name = "BackdropRoot"
	menu_background_viewport.add_child(backdrop_root)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_material := PhysicalSkyMaterial.new()
	sky_material.rayleigh_color = Color(0.95, 0.55, 0.31, 1.0)
	sky_material.mie_color = Color(0.96, 0.76, 0.58, 1.0)
	sky_material.turbidity = 12.4
	sky_material.ground_color = Color(0.2, 0.09, 0.05, 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.31, 0.16, 0.09, 1.0)
	environment.ambient_light_energy = 1.2
	environment.fog_enabled = true
	environment.fog_density = 0.0019
	environment.fog_light_color = Color(0.95, 0.58, 0.31, 1.0)
	environment.fog_aerial_perspective = 0.34
	environment.fog_sun_scatter = 0.39
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	backdrop_root.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 3.1
	sun.light_color = Color(1.0, 0.89, 0.74, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 820.0
	sun.rotation_degrees = Vector3(-56.0, 42.0, 0.0)
	backdrop_root.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.36
	fill.light_color = Color(0.84, 0.62, 0.45, 1.0)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-22.0, -95.0, 0.0)
	backdrop_root.add_child(fill)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(980.0, 980.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.72, 0.31, 0.12, 1.0)
	ground_material.roughness = 0.98
	ground_material.metallic = 0.02
	ground.material_override = ground_material
	backdrop_root.add_child(ground)

	var mesa_specs := [
		{ "x": -190.0, "z": -18.0, "radius": 46.0, "height": 146.0, "tint": Color(0.58, 0.22, 0.11, 1.0) },
		{ "x": 128.0, "z": -74.0, "radius": 34.0, "height": 98.0, "tint": Color(0.64, 0.27, 0.12, 1.0) },
		{ "x": 26.0, "z": -182.0, "radius": 22.0, "height": 72.0, "tint": Color(0.55, 0.2, 0.1, 1.0) },
		{ "x": -56.0, "z": -120.0, "radius": 30.0, "height": 84.0, "tint": Color(0.6, 0.24, 0.11, 1.0) },
		{ "x": 196.0, "z": -12.0, "radius": 38.0, "height": 116.0, "tint": Color(0.52, 0.2, 0.1, 1.0) },
		{ "x": -108.0, "z": 46.0, "radius": 16.0, "height": 94.0, "tint": Color(0.48, 0.18, 0.09, 1.0) },
		{ "x": 156.0, "z": -128.0, "radius": 14.0, "height": 83.0, "tint": Color(0.47, 0.16, 0.09, 1.0) }
	]
	for spec in mesa_specs:
		_add_mesa(backdrop_root, float(spec["x"]), float(spec["z"]), float(spec["radius"]), float(spec["height"]), spec["tint"])

	for dune_index in range(18):
		var dune := MeshInstance3D.new()
		var dune_mesh := SphereMesh.new()
		dune_mesh.radius = 1.0
		dune_mesh.height = 2.0
		dune.mesh = dune_mesh
		var dune_material := StandardMaterial3D.new()
		dune_material.albedo_color = Color(0.78, 0.35, 0.14, 1.0)
		dune_material.roughness = 0.99
		dune.material_override = dune_material
		dune.scale = Vector3(26.0 + float(dune_index % 5) * 9.0, 1.0 + float(dune_index % 3) * 0.24, 15.0 + float(dune_index % 4) * 7.0)
		dune.position = Vector3(-220.0 + float(dune_index) * 28.0, 0.6, -30.0 - float((dune_index * 17) % 210))
		backdrop_root.add_child(dune)

	menu_background_camera = Camera3D.new()
	menu_background_camera.current = true
	menu_background_camera.fov = 58.0
	menu_background_camera.position = Vector3(138.0, 58.0, 78.0)
	backdrop_root.add_child(menu_background_camera)
	menu_background_camera.look_at(background_focus, Vector3.UP)

func _add_mesa(parent_node: Node3D, x: float, z: float, radius: float, height: float, tint: Color) -> void:
	var mesa := MeshInstance3D.new()
	var mesa_mesh := CylinderMesh.new()
	mesa_mesh.top_radius = radius * 0.68
	mesa_mesh.bottom_radius = radius
	mesa_mesh.height = height
	mesa.mesh = mesa_mesh
	var mesa_material := StandardMaterial3D.new()
	mesa_material.albedo_color = tint
	mesa_material.roughness = 0.95
	mesa_material.metallic = 0.01
	mesa.material_override = mesa_material
	mesa.position = Vector3(x, height * 0.5, z)
	parent_node.add_child(mesa)

func _style_menu() -> void:
	overlay_tint.color = Color(0.08, 0.04, 0.02, 0.37)

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.11, 0.055, 0.03, 0.8)
	frame_style.border_width_left = 2
	frame_style.border_width_top = 2
	frame_style.border_width_right = 2
	frame_style.border_width_bottom = 2
	frame_style.border_color = Color(0.94, 0.56, 0.32, 0.44)
	frame_style.corner_radius_top_left = 20
	frame_style.corner_radius_top_right = 20
	frame_style.corner_radius_bottom_right = 20
	frame_style.corner_radius_bottom_left = 20
	frame_style.shadow_color = Color(0.01, 0.0, 0.0, 0.58)
	frame_style.shadow_size = 24
	chrome_frame.add_theme_stylebox_override("panel", frame_style)

	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0.12, 0.06, 0.04, 0.95)
	settings_style.border_width_left = 1
	settings_style.border_width_top = 1
	settings_style.border_width_right = 1
	settings_style.border_width_bottom = 1
	settings_style.border_color = Color(0.96, 0.62, 0.36, 0.52)
	settings_style.corner_radius_top_left = 14
	settings_style.corner_radius_top_right = 14
	settings_style.corner_radius_bottom_right = 14
	settings_style.corner_radius_bottom_left = 14
	settings_panel.add_theme_stylebox_override("panel", settings_style)

	var menu_buttons := [new_game_button, continue_button, settings_button, quit_button, close_settings_button]
	for button_variant in menu_buttons:
		_apply_button_style(button_variant as Button)

func _apply_button_style(button: Button) -> void:
	if button == null:
		return
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.98, 0.86, 0.72, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.82, 0.64, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.34, 0.28, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.19, 0.09, 0.05, 0.9)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.94, 0.55, 0.3, 0.45)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_right = 10
	normal.corner_radius_bottom_left = 10

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.12, 0.06, 0.93)
	hover.border_color = Color(1.0, 0.7, 0.42, 0.72)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.14, 0.07, 0.04, 0.95)
	pressed.border_color = Color(1.0, 0.8, 0.52, 0.82)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.05, 0.03, 0.76)
	disabled.border_color = Color(0.32, 0.24, 0.2, 0.44)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)

func _refresh_subtitle() -> void:
	var sol := 247
	var clone_iteration := 14
	if GameState != null:
		if GameState.has_method("get_sol_day"):
			sol = int(GameState.call("get_sol_day"))
		if GameState.has_method("get_clone_iteration"):
			clone_iteration = int(GameState.call("get_clone_iteration"))
	subtitle_label.text = "Sol %d — Clone Iteration %d" % [sol, clone_iteration]

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)), 0.0, 1.0)
	mouse_sensitivity_setting = clampf(
		float(config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)),
		MIN_MOUSE_SENSITIVITY,
		MAX_MOUSE_SENSITIVITY
	)
	fov_setting = clampf(float(config.get_value("video", "fov", DEFAULT_FOV)), MIN_FOV, MAX_FOV)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity_setting)
	config.set_value("video", "fov", fov_setting)
	config.save(SETTINGS_PATH)

func _sync_settings_ui() -> void:
	volume_slider.value = master_volume * 100.0
	volume_value.text = "%d%%" % int(round(volume_slider.value))
	sensitivity_slider.value = mouse_sensitivity_setting
	sensitivity_value.text = "%.2f" % (mouse_sensitivity_setting * 1000.0)
	fov_slider.value = fov_setting
	fov_value.text = "%d°" % int(round(fov_setting))

func _apply_audio_volume() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index == -1:
		return
	if master_volume <= 0.0001:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	else:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(master_volume))
