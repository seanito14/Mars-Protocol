extends Control

const C_WARNING_RED := Color(1.0, 0.2, 0.15, 1.0)
const C_DARK_BG := Color(0.05, 0.01, 0.01, 0.98)
const C_TEXT := Color(0.9, 0.92, 0.95, 1.0)
const C_TEXT_DIM := Color(0.6, 0.65, 0.7, 0.8)
const COUNTDOWN_DURATION := 3.0
const FLICKER_INTERVAL := 0.12

var countdown_timer: float = COUNTDOWN_DURATION
var countdown_active: bool = true
var flicker_timer: float = 0.0
var flicker_visible: bool = true
var noise_offset: float = 0.0

var clone_label: Label
var warning_label: Label
var stats_container: VBoxContainer
var deploy_button: Button
var menu_button: Button
var noise_rect: ColorRect
var countdown_label: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_populate_stats()

func _process(delta: float) -> void:
	# Flickering warning text
	flicker_timer += delta
	if flicker_timer >= FLICKER_INTERVAL:
		flicker_timer = 0.0
		flicker_visible = not flicker_visible
		if warning_label:
			warning_label.modulate.a = 1.0 if flicker_visible else 0.3

	# Static noise animation
	noise_offset += delta * 15.0
	if noise_rect and noise_rect.material:
		noise_rect.material.set_shader_parameter("time_offset", noise_offset)

	# Countdown timer
	if countdown_active:
		countdown_timer -= delta
		if countdown_timer <= 0.0:
			countdown_active = false
			countdown_timer = 0.0
			deploy_button.disabled = false
			deploy_button.modulate = Color(1, 1, 1, 1)
			countdown_label.visible = false
		else:
			countdown_label.text = "CLONE DEPLOYMENT IN %d..." % ceili(countdown_timer)

func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = C_DARK_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Static noise overlay
	noise_rect = ColorRect.new()
	noise_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	noise_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise_shader := _create_noise_shader()
	var noise_mat := ShaderMaterial.new()
	noise_mat.shader = noise_shader
	noise_rect.material = noise_mat
	add_child(noise_rect)

	# Main container
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_CENTER)
	main_vbox.offset_left = -320
	main_vbox.offset_right = 320
	main_vbox.offset_top = -280
	main_vbox.offset_bottom = 280
	main_vbox.add_theme_constant_override("separation", 16)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(main_vbox)

	# Warning label (flickering)
	warning_label = Label.new()
	warning_label.text = "⚠ CRITICAL FAILURE ⚠"
	warning_label.add_theme_font_size_override("font_size", 22)
	warning_label.add_theme_color_override("font_color", C_WARNING_RED)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(warning_label)

	# Large clone iteration number
	clone_label = Label.new()
	var clone_num := (GameState.clone_iteration - 1) if GameState else 13
	clone_label.text = "CLONE #%d\nTERMINATED" % clone_num
	clone_label.add_theme_font_size_override("font_size", 56)
	clone_label.add_theme_color_override("font_color", C_WARNING_RED)
	clone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(clone_label)

	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer1)

	# Stats summary panel
	var stats_panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.05, 0.9)
	panel_style.border_color = Color(0.4, 0.15, 0.1, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(20)
	stats_panel.add_theme_stylebox_override("panel", panel_style)
	main_vbox.add_child(stats_panel)

	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 8)
	stats_panel.add_child(stats_container)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 16)
	main_vbox.add_child(spacer2)

	# Countdown label
	countdown_label = Label.new()
	countdown_label.text = "CLONE DEPLOYMENT IN 3..."
	countdown_label.add_theme_font_size_override("font_size", 18)
	countdown_label.add_theme_color_override("font_color", C_TEXT_DIM)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(countdown_label)

	# Buttons container
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 24)
	main_vbox.add_child(btn_container)

	# Deploy button (disabled during countdown)
	deploy_button = _create_styled_button("DEPLOY NEXT CLONE", true)
	deploy_button.disabled = true
	deploy_button.modulate = Color(0.5, 0.5, 0.5, 0.7)
	deploy_button.pressed.connect(_on_deploy_pressed)
	btn_container.add_child(deploy_button)

	# Menu button
	menu_button = _create_styled_button("MAIN MENU", false)
	menu_button.pressed.connect(_on_menu_pressed)
	btn_container.add_child(menu_button)

func _populate_stats() -> void:
	var sols := GameState.sol_day if GameState else 247
	var cubes := GameState.salvage_cubes if GameState else 0
	var rocks := GameState.rocks_surveyed if GameState else 0
	var drones := GameState.drones_deployed if GameState else 0
	var dist := GameState.distance_walked if GameState else 0.0

	_add_stat_row("SOLS SURVIVED", str(sols))
	_add_stat_row("CUBES COLLECTED", str(cubes))
	_add_stat_row("ROCKS SURVEYED", str(rocks))
	_add_stat_row("DRONES DEPLOYED", str(drones))
	_add_stat_row("DISTANCE WALKED", "%.1f m" % dist)

func _add_stat_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", C_TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)

	stats_container.add_child(row)

func _create_styled_button(text: String, is_primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 48)

	var style := StyleBoxFlat.new()
	if is_primary:
		style.bg_color = Color(0.7, 0.2, 0.15, 0.9)
		style.border_color = Color(1.0, 0.3, 0.2, 1.0)
	else:
		style.bg_color = Color(0.15, 0.12, 0.1, 0.9)
		style.border_color = Color(0.4, 0.35, 0.3, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.bg_color = style.bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = style.bg_color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_TEXT)

	return btn

func _create_noise_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float time_offset : hint_range(0.0, 1000.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.08;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float noise = rand(UV + vec2(time_offset, time_offset * 0.7));
	float scanline = sin(UV.y * 400.0 + time_offset * 2.0) * 0.02;
	COLOR = vec4(vec3(noise * intensity + scanline), intensity * 0.6);
}
"""
	return shader

func _on_deploy_pressed() -> void:
	if GameState:
		if GameState.has_method("reset_session_stats"):
			GameState.reset_session_stats()
		if GameState.has_method("save_game"):
			GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/jezero_landing.tscn")

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
