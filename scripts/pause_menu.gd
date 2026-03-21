extends Control
## Pause Menu overlay with Resume, Settings, Main Menu, and Quit options.

const C_OVERLAY_BG := Color(0.02, 0.02, 0.03, 0.85)
const C_PANEL_BG := Color(0.08, 0.06, 0.05, 0.95)
const C_FRAME := Color(0.35, 0.18, 0.1, 0.9)
const C_TEXT := Color(0.92, 0.94, 0.96, 1.0)
const C_TEXT_DIM := Color(0.65, 0.7, 0.75, 0.85)
const C_ACCENT := Color(0.9, 0.5, 0.2, 1.0)

var settings_panel: Control
var main_panel: Control
var sensitivity_slider: HSlider
var volume_slider: HSlider
var fov_slider: HSlider
var sensitivity_value_label: Label
var volume_value_label: Label
var fov_value_label: Label

signal resumed
signal quit_to_menu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_show_main_panel()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if settings_panel.visible:
			_show_main_panel()
		else:
			_on_resume_pressed()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	# Darkened overlay background
	var overlay := ColorRect.new()
	overlay.color = C_OVERLAY_BG
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Main pause panel
	main_panel = _build_main_panel()
	add_child(main_panel)

	# Settings panel (hidden initially)
	settings_panel = _build_settings_panel()
	settings_panel.visible = false
	add_child(settings_panel)

func _build_main_panel() -> Control:
	var container := CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL_BG
	style.border_color = C_FRAME
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(320, 0)
	container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", C_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	# Menu buttons
	var resume_btn := _create_menu_button("RESUME")
	resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_btn)

	var settings_btn := _create_menu_button("SETTINGS")
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	var main_menu_btn := _create_menu_button("MAIN MENU")
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(main_menu_btn)

	var quit_btn := _create_menu_button("QUIT GAME")
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

	return container

func _build_settings_panel() -> Control:
	var container := CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL_BG
	style.border_color = C_FRAME
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(400, 0)
	container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Volume slider
	var vol_row := _create_slider_row("VOLUME", 0.0, 1.0, 0.8)
	volume_slider = vol_row.get_node("Slider")
	volume_value_label = vol_row.get_node("ValueLabel")
	volume_slider.value_changed.connect(_on_volume_changed)
	vbox.add_child(vol_row)

	# Sensitivity slider
	var sens_row := _create_slider_row("MOUSE SENSITIVITY", 0.1, 2.0, 1.0)
	sensitivity_slider = sens_row.get_node("Slider")
	sensitivity_value_label = sens_row.get_node("ValueLabel")
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	vbox.add_child(sens_row)

	# FOV slider
	var fov_row := _create_slider_row("FIELD OF VIEW", 60.0, 110.0, 76.0)
	fov_slider = fov_row.get_node("Slider")
	fov_value_label = fov_row.get_node("ValueLabel")
	fov_slider.value_changed.connect(_on_fov_changed)
	vbox.add_child(fov_row)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Back button
	var back_btn := _create_menu_button("BACK")
	back_btn.pressed.connect(_on_settings_back_pressed)
	vbox.add_child(back_btn)

	return container

func _create_slider_row(label_text: String, min_val: float, max_val: float, default_val: float) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", C_TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.text = "%.1f" % default_val if max_val > 10 else "%.0f%%" % (default_val * 100)
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", C_TEXT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = 0.01 if max_val <= 2.0 else 1.0
	slider.custom_minimum_size = Vector2(300, 24)

	# Style the slider
	var grabber_style := StyleBoxFlat.new()
	grabber_style.bg_color = C_ACCENT
	grabber_style.set_corner_radius_all(8)
	slider.add_theme_stylebox_override("grabber_area", grabber_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_style)

	vbox.add_child(slider)

	return vbox

func _create_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 44)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	style.border_color = Color(0.3, 0.25, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.2, 0.15, 0.1, 0.95)
	hover_style.border_color = C_ACCENT
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = Color(0.08, 0.06, 0.05, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", C_TEXT)

	return btn

func _show_main_panel() -> void:
	main_panel.visible = true
	settings_panel.visible = false

func _show_settings_panel() -> void:
	main_panel.visible = false
	settings_panel.visible = true

func _on_resume_pressed() -> void:
	resumed.emit()

func _on_settings_pressed() -> void:
	_show_settings_panel()

func _on_settings_back_pressed() -> void:
	_show_main_panel()

func _on_main_menu_pressed() -> void:
	quit_to_menu.emit()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(value: float) -> void:
	volume_value_label.text = "%.0f%%" % (value * 100)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))

func _on_sensitivity_changed(value: float) -> void:
	sensitivity_value_label.text = "%.2f" % value
	# Store in a global config if needed

func _on_fov_changed(value: float) -> void:
	fov_value_label.text = "%.0f°" % value
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_node("BreathPivot/TiltPivot/PitchPivot/Camera3D"):
		var cam := player.get_node("BreathPivot/TiltPivot/PitchPivot/Camera3D")
		if cam is Camera3D:
			cam.fov = value
