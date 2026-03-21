class_name HeroHUD
extends Control

## Helmet visor HUD inspired by the supplied sci-fi cockpit reference.
## The frame and reticle are drawn procedurally, while the telemetry
## remains bound to the live hero/player state.

const C_FRAME_DARK := Color(0.09, 0.035, 0.02, 0.96)
const C_FRAME_MID := Color(0.21, 0.09, 0.05, 0.94)
const C_FRAME_GLOW := Color(0.44, 0.21, 0.12, 0.32)
const C_GLASS := Color(0.72, 0.86, 0.95, 0.08)
const C_PANEL := Color(0.06, 0.09, 0.12, 0.18)
const C_PANEL_EDGE := Color(0.69, 0.82, 0.93, 0.18)
const C_PANEL_ACCENT := Color(0.78, 0.89, 1.0, 0.34)
const C_TEXT := Color(0.9, 0.95, 0.99, 0.9)
const C_TEXT_DIM := Color(0.72, 0.81, 0.9, 0.48)
const C_TEXT_SOFT := Color(0.62, 0.75, 0.88, 0.28)
const C_ACCENT := Color(0.72, 0.92, 1.0, 0.95)
const C_RETICLE := Color(0.72, 0.93, 1.0, 0.42)
const C_WARNING := Color(1.0, 0.46, 0.22, 0.95)
const C_OK_BAR := Color(0.84, 0.91, 0.98, 0.84)

const TOP_MARGIN := 46.0
const SIDE_MARGIN := 82.0
const BOTTOM_MARGIN := 42.0
const TOP_RAIL_ROTATION := 0.055

var player: Node = null

var left_rail: Control
var left_panel: Panel
var left_code_label: Label
var left_title_label: Label
var left_primary_label: Label
var left_detail_label: Label
var left_bar_bg: ColorRect
var left_bar_fill: ColorRect

var right_rail: Control
var right_panel: Panel
var right_small_label: Label
var right_primary_label: Label
var right_detail_label: Label
var right_bar_bg: ColorRect
var right_bar_fill: ColorRect

var ai_panel: Panel
var ai_indicator: ColorRect
var ai_channel_label: Label
var ai_state_label: Label

var comms_panel: Panel
var comms_header_label: Label
var comms_body_label: Label

var focus_panel: Panel
var focus_prompt_label: Label

var look_touch_area: Control
var look_hint: Label
var active_touch_id: int = -1
var mouse_look_active: bool = false

var pause_button: Button
var pause_overlay: Control
var resume_button: Button
var exit_button: Button

var hud_scale: float = 1.0
var current_heading_degrees: float = 0.0
var current_storm_ratio: float = 0.0
var current_o2_ratio: float = 1.0
var current_ai_hot: bool = false
var current_focus_name: String = ""
var scan_line_phase: float = 0.0
var pulse_phase: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	player = get_tree().get_first_node_in_group("player")
	_build_hud()
	get_viewport().size_changed.connect(_on_window_resized)
	_on_window_resized()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	scan_line_phase = fposmod(scan_line_phase + (delta * 0.22), 1.0)
	pulse_phase = fposmod(pulse_phase + (delta * 2.1), TAU)

	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_status_snapshot"):
		queue_redraw()
		return

	var snap: Dictionary = player.call("get_status_snapshot")
	_update_life_support(snap)
	_update_navigation(snap)
	_update_ai_status(snap)
	_update_mission_message(snap)
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_edge_shading(vp)
	_draw_visor_frame(vp)
	_draw_top_module(vp)
	_draw_compass_badge(vp)
	_draw_reticle(vp)
	_draw_focus_marks(vp)
	_draw_scan_line(vp)

func _build_hud() -> void:
	_build_top_left()
	_build_top_right()
	_build_ai_panel()
	_build_comms_panel()
	_build_focus_panel()
	_build_touch_area()
	_build_pause_overlay()

func _build_top_left() -> void:
	left_rail = Control.new()
	left_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_rail)

	left_panel = Panel.new()
	left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_panel.add_theme_stylebox_override("panel", _make_glass_style())
	left_rail.add_child(left_panel)

	left_code_label = _make_label("OSE", 34, C_TEXT)
	left_panel.add_child(left_code_label)

	left_title_label = _make_label("GENERAL 001", 13, C_TEXT_SOFT)
	left_panel.add_child(left_title_label)

	left_primary_label = _make_label("O2 100%", 28, C_TEXT)
	left_panel.add_child(left_primary_label)

	left_bar_bg = ColorRect.new()
	left_bar_bg.color = Color(0.7, 0.82, 0.93, 0.09)
	left_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_panel.add_child(left_bar_bg)

	left_bar_fill = ColorRect.new()
	left_bar_fill.color = C_OK_BAR
	left_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_panel.add_child(left_bar_fill)

	left_detail_label = _make_label("GRID +0.0 / +0.0", 14, C_TEXT_DIM)
	left_panel.add_child(left_detail_label)

func _build_top_right() -> void:
	right_rail = Control.new()
	right_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_rail)

	right_panel = Panel.new()
	right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_panel.add_theme_stylebox_override("panel", _make_glass_style())
	right_rail.add_child(right_panel)

	right_small_label = _make_label("070.EC", 13, C_TEXT_SOFT)
	right_small_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_panel.add_child(right_small_label)

	right_primary_label = _make_label("WPT 055M", 28, C_TEXT)
	right_primary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right_panel.add_child(right_primary_label)

	right_bar_bg = ColorRect.new()
	right_bar_bg.color = Color(0.7, 0.82, 0.93, 0.09)
	right_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_panel.add_child(right_bar_bg)

	right_bar_fill = ColorRect.new()
	right_bar_fill.color = C_OK_BAR
	right_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_panel.add_child(right_bar_fill)

	right_detail_label = _make_label("STORM 0h 00m", 14, C_TEXT_DIM)
	right_panel.add_child(right_detail_label)

func _build_ai_panel() -> void:
	ai_panel = Panel.new()
	ai_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ai_panel.add_theme_stylebox_override("panel", _make_glass_style(10))
	add_child(ai_panel)

	ai_indicator = ColorRect.new()
	ai_indicator.color = C_ACCENT
	ai_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ai_panel.add_child(ai_indicator)

	ai_channel_label = _make_label("LINK // CH 01", 12, C_TEXT_SOFT)
	ai_panel.add_child(ai_channel_label)

	ai_state_label = _make_label("MARVIN STANDBY", 18, C_TEXT)
	ai_panel.add_child(ai_state_label)

func _build_comms_panel() -> void:
	comms_panel = Panel.new()
	comms_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	comms_panel.add_theme_stylebox_override("panel", _make_glass_style(14))
	add_child(comms_panel)

	comms_header_label = _make_label("CHANNEL // 00:00:00", 12, C_TEXT_SOFT)
	comms_panel.add_child(comms_header_label)

	comms_body_label = _make_label("Marvin online. Move toward the wreckage and request a scan.", 16, C_TEXT_DIM)
	comms_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comms_panel.add_child(comms_body_label)

func _build_focus_panel() -> void:
	focus_panel = Panel.new()
	focus_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_panel.add_theme_stylebox_override("panel", _make_glass_style(12))
	add_child(focus_panel)

	focus_prompt_label = _make_label("Walk the crater, inspect the wreckage, and talk to Marvin.", 13, C_TEXT_DIM)
	focus_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	focus_panel.add_child(focus_prompt_label)

func _build_touch_area() -> void:
	look_touch_area = Control.new()
	look_touch_area.name = "LookTouchArea"
	look_touch_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_touch_area.anchor_left = 0.48
	look_touch_area.offset_top = 72.0
	look_touch_area.offset_right = -18.0
	look_touch_area.offset_bottom = -18.0
	look_touch_area.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(look_touch_area)
	look_touch_area.gui_input.connect(_on_look_touch_input)

	look_hint = Label.new()
	look_hint.text = "DRAG RIGHT SIDE TO LOOK"
	look_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	look_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	look_hint.offset_left = -280.0
	look_hint.offset_top = -60.0
	look_hint.offset_right = -12.0
	look_hint.offset_bottom = -18.0
	look_hint.modulate = Color(1.0, 1.0, 1.0, 0.22)
	look_hint.add_theme_font_size_override("font_size", 12)
	look_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look_touch_area.add_child(look_hint)

func _build_pause_overlay() -> void:
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = "II"
	pause_button.flat = true
	pause_button.add_theme_font_size_override("font_size", 18)
	pause_button.add_theme_color_override("font_color", C_TEXT_SOFT)
	pause_button.add_theme_color_override("font_hover_color", C_ACCENT)
	add_child(pause_button)
	pause_button.pressed.connect(_on_pause_pressed)

	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	add_child(pause_overlay)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0.01, 0.015, 0.02, 0.72)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200.0
	panel.offset_top = -126.0
	panel.offset_right = 200.0
	panel.offset_bottom = 126.0
	panel.add_theme_stylebox_override("panel", _make_glass_style(18, Color(0.08, 0.11, 0.16, 0.92)))
	pause_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := _make_label("PAUSED", 30, C_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := _make_label("Resume the mission or exit.", 14, C_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	resume_button = Button.new()
	resume_button.text = "RESUME"
	vbox.add_child(resume_button)
	resume_button.pressed.connect(_on_resume_pressed)

	exit_button = Button.new()
	exit_button.text = "EXIT GAME"
	vbox.add_child(exit_button)
	exit_button.pressed.connect(_on_exit_pressed)

func _update_life_support(snap: Dictionary) -> void:
	var o2 := float(snap.get("oxygen", 100.0))
	var o2_max := float(snap.get("oxygen_max", 100.0))
	current_o2_ratio = clampf(o2 / maxf(o2_max, 1.0), 0.0, 1.0)

	left_primary_label.text = "O2 %03d%%" % int(round(o2))
	var coords: Vector2 = snap.get("coords", Vector2.ZERO)
	left_detail_label.text = "GRID %+.1f  /  %+.1f" % [coords.x, coords.y]
	left_bar_fill.size.x = left_bar_bg.size.x * current_o2_ratio
	if current_o2_ratio < 0.28:
		left_bar_fill.color = C_WARNING
		left_primary_label.add_theme_color_override("font_color", C_WARNING.lerp(C_TEXT, 0.35 + (0.35 * (sin(pulse_phase) + 1.0))))
	else:
		left_bar_fill.color = C_OK_BAR
		left_primary_label.add_theme_color_override("font_color", C_TEXT)

func _update_navigation(snap: Dictionary) -> void:
	var heading_label: String = str(snap.get("heading_label", "N"))
	current_heading_degrees = float(snap.get("heading_degrees", 0.0))
	right_small_label.text = "%03d.%s" % [int(round(current_heading_degrees)), heading_label]

	var waypoint_distance := float(snap.get("waypoint_distance", -1.0))
	var waypoint_name := str(snap.get("active_waypoint", ""))
	if waypoint_distance >= 0.0:
		right_primary_label.text = "WPT %03dM" % int(round(waypoint_distance))
	else:
		right_primary_label.text = waypoint_name if not waypoint_name.is_empty() else "WPT ---"

	var storm_eta := str(snap.get("storm_eta_label", "0h 00m"))
	right_detail_label.text = "STORM %s" % storm_eta
	current_storm_ratio = clampf(float(snap.get("storm_intensity", 0.0)), 0.03, 1.0)
	right_bar_fill.size.x = right_bar_bg.size.x * current_storm_ratio
	right_bar_fill.color = C_WARNING if current_storm_ratio > 0.62 else C_OK_BAR

func _update_ai_status(snap: Dictionary) -> void:
	var marvin_state := str(snap.get("marvin_conversation_state", "STANDBY"))
	var sudo_state := ""
	if player != null:
		sudo_state = str(player.get("sudo_ai_state"))

	if not sudo_state.is_empty() and sudo_state != "OFFLINE":
		ai_state_label.text = sudo_state
		ai_indicator.color = C_ACCENT
		current_ai_hot = true
	else:
		ai_state_label.text = "MARVIN %s" % marvin_state
		ai_indicator.color = Color(0.82, 0.9, 1.0, 0.82)
		current_ai_hot = marvin_state.contains("SCAN") or marvin_state.contains("VOICE")

	ai_indicator.modulate.a = 0.54 + (0.38 * ((sin(pulse_phase * 0.7) + 1.0) * 0.5))

func _update_mission_message(snap: Dictionary) -> void:
	var time_label := str(snap.get("time_label", "00:00:00"))
	comms_header_label.text = "CHANNEL // %s" % time_label

	var msg := str(snap.get("marvin_message", ""))
	current_focus_name = str(snap.get("focus_name", "Open Terrain"))
	if msg.is_empty():
		comms_body_label.text = current_focus_name
	else:
		comms_body_label.text = msg

	var prompt := str(snap.get("focus_prompt", ""))
	if prompt.is_empty():
		focus_prompt_label.text = current_focus_name
	else:
		focus_prompt_label.text = prompt

func _on_window_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	hud_scale = clampf(vp.x / 2048.0, 0.72, 1.0)
	var small_mode := vp.x < 1400.0
	var rail_width := minf(540.0, vp.x * (0.34 if not small_mode else 0.39))
	var rail_height := 88.0 * hud_scale
	var bar_width := rail_width - (190.0 * hud_scale)
	var bar_height := maxf(3.0, 4.0 * hud_scale)

	left_rail.position = Vector2(SIDE_MARGIN * hud_scale, TOP_MARGIN * hud_scale)
	left_rail.rotation = -TOP_RAIL_ROTATION
	left_rail.size = Vector2(rail_width, rail_height)
	left_rail.pivot_offset = Vector2.ZERO
	left_panel.size = left_rail.size

	left_code_label.position = Vector2(12.0 * hud_scale, -2.0 * hud_scale)
	left_title_label.position = Vector2(118.0 * hud_scale, 8.0 * hud_scale)
	left_primary_label.position = Vector2(18.0 * hud_scale, 26.0 * hud_scale)
	left_bar_bg.position = Vector2(146.0 * hud_scale, 34.0 * hud_scale)
	left_bar_bg.size = Vector2(bar_width, bar_height)
	left_bar_fill.position = left_bar_bg.position
	left_detail_label.position = Vector2(18.0 * hud_scale, 56.0 * hud_scale)
	left_detail_label.size = Vector2(rail_width - (36.0 * hud_scale), 18.0 * hud_scale)

	right_rail.position = Vector2(vp.x - (SIDE_MARGIN * hud_scale) - rail_width, TOP_MARGIN * hud_scale)
	right_rail.rotation = TOP_RAIL_ROTATION
	right_rail.size = Vector2(rail_width, rail_height)
	right_rail.pivot_offset = Vector2(rail_width, 0.0)
	right_panel.size = right_rail.size

	right_small_label.position = Vector2(rail_width - (150.0 * hud_scale), 8.0 * hud_scale)
	right_small_label.size = Vector2(132.0 * hud_scale, 16.0 * hud_scale)
	right_primary_label.position = Vector2(18.0 * hud_scale, 26.0 * hud_scale)
	right_primary_label.size = Vector2(rail_width - (36.0 * hud_scale), 28.0 * hud_scale)
	right_bar_bg.position = Vector2(120.0 * hud_scale, 34.0 * hud_scale)
	right_bar_bg.size = Vector2(bar_width + (26.0 * hud_scale), bar_height)
	right_bar_fill.position = right_bar_bg.position
	right_detail_label.position = Vector2(18.0 * hud_scale, 56.0 * hud_scale)
	right_detail_label.size = Vector2(rail_width - (36.0 * hud_scale), 18.0 * hud_scale)

	ai_panel.position = Vector2((SIDE_MARGIN - 6.0) * hud_scale, vp.y - (BOTTOM_MARGIN * hud_scale) - (42.0 * hud_scale))
	ai_panel.size = Vector2(maxf(220.0 * hud_scale, vp.x * 0.17), 38.0 * hud_scale)
	ai_indicator.position = Vector2(10.0 * hud_scale, 14.0 * hud_scale)
	ai_indicator.size = Vector2(10.0 * hud_scale, 10.0 * hud_scale)
	ai_channel_label.position = Vector2(28.0 * hud_scale, 3.0 * hud_scale)
	ai_channel_label.size = Vector2(ai_panel.size.x - (38.0 * hud_scale), 14.0 * hud_scale)
	ai_state_label.position = Vector2(28.0 * hud_scale, 16.0 * hud_scale)
	ai_state_label.size = Vector2(ai_panel.size.x - (36.0 * hud_scale), 18.0 * hud_scale)

	var comms_width := minf(520.0, vp.x * (0.34 if not small_mode else 0.44))
	comms_panel.size = Vector2(comms_width, 86.0 * hud_scale)
	comms_panel.position = Vector2(vp.x - comms_width - (SIDE_MARGIN * hud_scale), vp.y - (BOTTOM_MARGIN * hud_scale) - comms_panel.size.y)
	comms_header_label.position = Vector2(14.0 * hud_scale, 8.0 * hud_scale)
	comms_header_label.size = Vector2(comms_width - (28.0 * hud_scale), 14.0 * hud_scale)
	comms_body_label.position = Vector2(14.0 * hud_scale, 28.0 * hud_scale)
	comms_body_label.size = Vector2(comms_width - (28.0 * hud_scale), 44.0 * hud_scale)

	var focus_width := minf(420.0, vp.x * 0.28)
	focus_panel.size = Vector2(focus_width, 42.0 * hud_scale)
	focus_panel.position = Vector2((vp.x - focus_width) * 0.5, vp.y - (BOTTOM_MARGIN * hud_scale) - focus_panel.size.y)
	focus_prompt_label.position = Vector2(12.0 * hud_scale, 8.0 * hud_scale)
	focus_prompt_label.size = Vector2(focus_width - (24.0 * hud_scale), 24.0 * hud_scale)

	pause_button.position = Vector2(vp.x - (58.0 * hud_scale), (TOP_MARGIN + 86.0) * hud_scale)
	pause_button.size = Vector2(32.0 * hud_scale, 28.0 * hud_scale)

	if small_mode:
		look_hint.text = "DRAG TO LOOK"
	else:
		look_hint.text = "DRAG RIGHT SIDE TO LOOK"

	_apply_font_scale(small_mode)
	queue_redraw()

func _apply_font_scale(small_mode: bool) -> void:
	var label_scale := hud_scale * (0.92 if small_mode else 1.0)
	_set_font_size(left_code_label, 30 * label_scale)
	_set_font_size(left_title_label, 12 * label_scale)
	_set_font_size(left_primary_label, 25 * label_scale)
	_set_font_size(left_detail_label, 13 * label_scale)
	_set_font_size(right_small_label, 12 * label_scale)
	_set_font_size(right_primary_label, 25 * label_scale)
	_set_font_size(right_detail_label, 13 * label_scale)
	_set_font_size(ai_channel_label, 11 * label_scale)
	_set_font_size(ai_state_label, 16 * label_scale)
	_set_font_size(comms_header_label, 11 * label_scale)
	_set_font_size(comms_body_label, 15 * label_scale)
	_set_font_size(focus_prompt_label, 12 * label_scale)
	look_hint.add_theme_font_size_override("font_size", maxi(int(round(12 * label_scale)), 10))

func _draw_edge_shading(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, vp.y * 0.08)), Color(0.0, 0.0, 0.0, 0.08), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x * 0.04, vp.y)), Color(0.0, 0.0, 0.0, 0.05), true)
	draw_rect(Rect2(Vector2(vp.x * 0.96, 0.0), Vector2(vp.x * 0.04, vp.y)), Color(0.0, 0.0, 0.0, 0.05), true)
	draw_rect(Rect2(Vector2(0.0, vp.y * 0.92), Vector2(vp.x, vp.y * 0.08)), Color(0.0, 0.0, 0.0, 0.035), true)

func _draw_visor_frame(vp: Vector2) -> void:
	var left_frame := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(vp.x * 0.185, 0.0),
		Vector2(vp.x * 0.168, vp.y * 0.036),
		Vector2(vp.x * 0.132, vp.y * 0.09),
		Vector2(vp.x * 0.088, vp.y * 0.2),
		Vector2(vp.x * 0.05, vp.y * 0.37),
		Vector2(vp.x * 0.022, vp.y * 0.56),
		Vector2(0.0, vp.y * 0.69),
	])
	var right_frame := PackedVector2Array([
		Vector2(vp.x, 0.0),
		Vector2(vp.x * 0.815, 0.0),
		Vector2(vp.x * 0.832, vp.y * 0.036),
		Vector2(vp.x * 0.868, vp.y * 0.09),
		Vector2(vp.x * 0.912, vp.y * 0.2),
		Vector2(vp.x * 0.95, vp.y * 0.37),
		Vector2(vp.x * 0.978, vp.y * 0.56),
		Vector2(vp.x, vp.y * 0.69),
	])
	var left_lower := PackedVector2Array([
		Vector2(0.0, vp.y),
		Vector2(0.0, vp.y - (vp.y * 0.19)),
		Vector2(vp.x * 0.008, vp.y - (vp.y * 0.19)),
		Vector2(vp.x * 0.008, vp.y - (vp.y * 0.12)),
		Vector2(vp.x * 0.03, vp.y - (vp.y * 0.12)),
		Vector2(vp.x * 0.058, vp.y),
	])
	var right_lower := PackedVector2Array([
		Vector2(vp.x, vp.y),
		Vector2(vp.x, vp.y - (vp.y * 0.19)),
		Vector2(vp.x * 0.992, vp.y - (vp.y * 0.19)),
		Vector2(vp.x * 0.992, vp.y - (vp.y * 0.12)),
		Vector2(vp.x * 0.97, vp.y - (vp.y * 0.12)),
		Vector2(vp.x * 0.942, vp.y),
	])

	_draw_frame_piece(left_frame)
	_draw_frame_piece(right_frame)
	_draw_frame_piece(left_lower)
	_draw_frame_piece(right_lower)

func _draw_frame_piece(points: PackedVector2Array) -> void:
	draw_colored_polygon(points, C_FRAME_DARK)
	draw_polyline(points, C_FRAME_GLOW, 3.0, true)
	var inset := PackedVector2Array()
	for point in points:
		inset.append(point.lerp(get_viewport_rect().size * 0.5, 0.045))
	draw_colored_polygon(inset, Color(C_FRAME_MID.r, C_FRAME_MID.g, C_FRAME_MID.b, 0.18))

func _draw_top_module(vp: Vector2) -> void:
	var top_module := PackedVector2Array([
		Vector2(vp.x * 0.37, 0.0),
		Vector2(vp.x * 0.63, 0.0),
		Vector2(vp.x * 0.612, vp.y * 0.034),
		Vector2(vp.x * 0.556, vp.y * 0.047),
		Vector2(vp.x * 0.544, vp.y * 0.075),
		Vector2(vp.x * 0.456, vp.y * 0.075),
		Vector2(vp.x * 0.444, vp.y * 0.047),
		Vector2(vp.x * 0.388, vp.y * 0.034),
	])
	draw_colored_polygon(top_module, C_FRAME_DARK)
	draw_polyline(top_module, C_FRAME_GLOW, 3.0, true)

	var light_rect := Rect2(vp.x * 0.457, vp.y * 0.012, vp.x * 0.086, vp.y * 0.02)
	draw_rect(light_rect, Color(0.62, 0.89, 1.0, 0.75), true)
	draw_rect(light_rect.grow(4.0), Color(0.62, 0.89, 1.0, 0.08), true)

func _draw_compass_badge(vp: Vector2) -> void:
	var center := Vector2(vp.x - (74.0 * hud_scale), 56.0 * hud_scale)
	var radius := 20.0 * hud_scale
	draw_arc(center, radius, 0.0, TAU, 48, C_PANEL_ACCENT, 2.0, true)
	draw_arc(center, radius - (6.0 * hud_scale), 0.0, TAU, 48, Color(0.75, 0.88, 1.0, 0.18), 1.0, true)
	var needle_angle := deg_to_rad(current_heading_degrees - 90.0)
	var needle_tip := center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - (4.0 * hud_scale))
	var needle_tail := center - Vector2(cos(needle_angle), sin(needle_angle)) * (radius * 0.35)
	draw_line(needle_tail, needle_tip, C_ACCENT, 2.0)
	draw_circle(center, 2.5 * hud_scale, C_ACCENT)

func _draw_reticle(vp: Vector2) -> void:
	var center := vp * 0.5
	var arm := 18.0 * hud_scale
	var gap := 7.0 * hud_scale
	draw_line(center + Vector2(-arm, 0.0), center + Vector2(-gap, 0.0), C_RETICLE, 1.4)
	draw_line(center + Vector2(gap, 0.0), center + Vector2(arm, 0.0), C_RETICLE, 1.4)
	draw_line(center + Vector2(0.0, -arm), center + Vector2(0.0, -gap), C_RETICLE, 1.4)
	draw_line(center + Vector2(0.0, gap), center + Vector2(0.0, arm), C_RETICLE, 1.4)
	draw_circle(center, 1.6 * hud_scale, Color(C_RETICLE.r, C_RETICLE.g, C_RETICLE.b, 0.65))

func _draw_focus_marks(vp: Vector2) -> void:
	var center := vp * 0.5
	var width := 56.0 * hud_scale
	var height := 20.0 * hud_scale
	var y := center.y + (118.0 * hud_scale)
	draw_line(Vector2(center.x - width, y), Vector2(center.x - (width * 0.35), y), Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.18), 2.0)
	draw_line(Vector2(center.x + (width * 0.35), y), Vector2(center.x + width, y), Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.18), 2.0)
	draw_line(Vector2(center.x - (width * 0.08), y - height), Vector2(center.x - (width * 0.01), y - height), Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.14), 2.0)
	draw_line(Vector2(center.x + (width * 0.01), y - height), Vector2(center.x + (width * 0.08), y - height), Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.14), 2.0)

func _draw_scan_line(vp: Vector2) -> void:
	var start_y := vp.y * 0.18
	var end_y := vp.y * 0.84
	var y := lerpf(start_y, end_y, scan_line_phase)
	draw_rect(Rect2(Vector2(124.0 * hud_scale, y), Vector2(vp.x - (248.0 * hud_scale), 1.4)), Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.06), true)

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_glass_style(corner_radius: int = 12, bg_color: Color = C_PANEL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = C_PANEL_EDGE
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	style.shadow_size = 10
	return style

func _set_font_size(label: Label, value: float) -> void:
	label.add_theme_font_size_override("font_size", maxi(int(round(value)), 10))

func toggle_pause_menu() -> void:
	_set_paused(not get_tree().paused)

func _on_pause_pressed() -> void:
	_set_paused(true)

func _on_resume_pressed() -> void:
	_set_paused(false)

func _on_exit_pressed() -> void:
	get_tree().quit()

func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_overlay.visible = paused
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_reset_touch_look()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_look_touch_input(event: InputEvent) -> void:
	if get_tree().paused or player == null:
		return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and active_touch_id == -1:
			active_touch_id = touch_event.index
			get_viewport().set_input_as_handled()
			return
		if not touch_event.pressed and touch_event.index == active_touch_id:
			_reset_touch_look()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == active_touch_id and player.has_method("add_touch_look_delta"):
			player.call("add_touch_look_delta", drag_event.relative)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			mouse_look_active = mouse_button.pressed
			if not mouse_look_active:
				_reset_touch_look()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and mouse_look_active and player.has_method("add_touch_look_delta"):
		var mouse_motion := event as InputEventMouseMotion
		player.call("add_touch_look_delta", mouse_motion.relative)
		get_viewport().set_input_as_handled()

func _reset_touch_look() -> void:
	active_touch_id = -1
	mouse_look_active = false
