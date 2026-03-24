extends Control

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MASTER_VOLUME: float = 1.0
const DEFAULT_MOUSE_SENSITIVITY: float = 0.0021
const DEFAULT_FOV: float = 76.0

const MIN_MOUSE_SENSITIVITY: float = 0.0008
const MAX_MOUSE_SENSITIVITY: float = 0.0055
const MIN_FOV: float = 60.0
const MAX_FOV: float = 100.0
const MENU_BACKGROUND_VIDEO_PATH := "res://assets/video/opening_scene.ogv"

@onready var overlay_tint: ColorRect = $OverlayTint
@onready var chrome_frame: Panel = $ChromeFrame
@onready var title_label: Label = $ChromeFrame/ContentMargin/ContentVBox/TitleLabel
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

var menu_background_video: VideoStreamPlayer

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

	if not FileAccess.file_exists("user://savegame.json"):
		continue_button.disabled = true

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
			get_tree().change_scene_to_file("res://scenes/jezero_landing.tscn")
			return
	get_tree().change_scene_to_file("res://scenes/jezero_landing.tscn")

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
	pass

func _build_menu_background() -> void:
	menu_background_video = VideoStreamPlayer.new()
	menu_background_video.name = "MenuBackgroundVideo"
	menu_background_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_background_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_background_video.expand = true
	menu_background_video.volume = -80.0
	menu_background_video.loop = true
	var stream := load(MENU_BACKGROUND_VIDEO_PATH) as VideoStream
	if stream == null:
		push_warning("Main menu background video is unavailable at %s." % MENU_BACKGROUND_VIDEO_PATH)
	else:
		menu_background_video.stream = stream
		menu_background_video.finished.connect(_on_menu_background_finished)
	add_child(menu_background_video)
	move_child(menu_background_video, 0)
	call_deferred("_start_menu_background_video")

func _start_menu_background_video() -> void:
	if menu_background_video == null or menu_background_video.stream == null:
		return
	menu_background_video.play()
	menu_background_video.stream_position = 1.8

func _on_menu_background_finished() -> void:
	_start_menu_background_video()

func _style_menu() -> void:
	overlay_tint.color = MarsExteriorProfile.MENU_OVERLAY_TINT

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = MarsExteriorProfile.MENU_FRAME_BG
	frame_style.border_width_left = 2
	frame_style.border_width_top = 2
	frame_style.border_width_right = 2
	frame_style.border_width_bottom = 2
	frame_style.border_color = MarsExteriorProfile.MENU_FRAME_BORDER
	frame_style.corner_radius_top_left = 20
	frame_style.corner_radius_top_right = 20
	frame_style.corner_radius_bottom_right = 20
	frame_style.corner_radius_bottom_left = 20
	frame_style.shadow_color = Color(0.01, 0.0, 0.0, 0.58)
	frame_style.shadow_size = 24
	chrome_frame.add_theme_stylebox_override("panel", frame_style)

	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = MarsExteriorProfile.MENU_SETTINGS_BG
	settings_style.border_width_left = 1
	settings_style.border_width_top = 1
	settings_style.border_width_right = 1
	settings_style.border_width_bottom = 1
	settings_style.border_color = MarsExteriorProfile.MENU_SETTINGS_BORDER
	settings_style.corner_radius_top_left = 14
	settings_style.corner_radius_top_right = 14
	settings_style.corner_radius_bottom_right = 14
	settings_style.corner_radius_bottom_left = 14
	settings_panel.add_theme_stylebox_override("panel", settings_style)
	title_label.add_theme_color_override("font_color", MarsExteriorProfile.MENU_TITLE_COLOR)
	subtitle_label.add_theme_color_override("font_color", MarsExteriorProfile.MENU_SUBTITLE_COLOR)
	for label_node in settings_panel.find_children("*", "Label", true, false):
		var label := label_node as Label
		if label == null:
			continue
		if label.name == "SettingsTitle":
			label.add_theme_color_override("font_color", MarsExteriorProfile.MENU_TITLE_COLOR)
		elif label.name.ends_with("Value"):
			label.add_theme_color_override("font_color", MarsExteriorProfile.HUD_TEXT)
		else:
			label.add_theme_color_override("font_color", MarsExteriorProfile.MENU_SUBTITLE_COLOR)

	var menu_buttons := [new_game_button, continue_button, settings_button, quit_button, close_settings_button]
	for button_variant in menu_buttons:
		_apply_button_style(button_variant as Button)

func _apply_button_style(button: Button) -> void:
	if button == null:
		return
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", MarsExteriorProfile.MENU_BUTTON_TEXT)
	button.add_theme_color_override("font_hover_color", MarsExteriorProfile.MENU_BUTTON_TEXT_HOVER)
	button.add_theme_color_override("font_pressed_color", MarsExteriorProfile.MENU_BUTTON_TEXT_HOVER)
	button.add_theme_color_override("font_disabled_color", MarsExteriorProfile.MENU_BUTTON_TEXT_DISABLED)

	var normal := MarsExteriorProfile.make_menu_button_style(MarsExteriorProfile.MENU_BUTTON_BG, MarsExteriorProfile.MENU_BUTTON_BORDER, 10)
	var hover := MarsExteriorProfile.make_menu_button_style(MarsExteriorProfile.MENU_BUTTON_BG_HOVER, MarsExteriorProfile.MENU_BUTTON_BORDER_HOVER, 10)
	var pressed := MarsExteriorProfile.make_menu_button_style(MarsExteriorProfile.MENU_BUTTON_BG_PRESSED, MarsExteriorProfile.MENU_BUTTON_BORDER_PRESSED, 10)
	var disabled := MarsExteriorProfile.make_menu_button_style(MarsExteriorProfile.MENU_BUTTON_BG_DISABLED, MarsExteriorProfile.MENU_BUTTON_BORDER, 10)

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
