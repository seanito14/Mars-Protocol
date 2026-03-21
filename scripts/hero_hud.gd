class_name HeroHUD
extends Control

## High-fidelity helmet visor HUD matching the sci-fi cockpit reference.
## All visual elements are built procedurally. Layout:
##   Top-left:  O2 readout + thin bar + coordinates
##   Top-right: Heading + distance + storm ETA + thin bar
##   Top-right corner: Compass rose
##   Center: Crosshair reticle dots
##   Bottom-left: AI link status label
##   Bottom-right: Mission context / AI message panel

# ── Colors ───────────────────────────────────────────────────────────────
const C_CYAN := Color(0.0, 0.83, 1.0, 1.0)
const C_CYAN_DIM := Color(0.0, 0.65, 0.85, 0.55)
const C_CYAN_BRIGHT := Color(0.4, 0.95, 1.0, 1.0)
const C_BAR_BG := Color(0.2, 0.22, 0.26, 0.5)
const C_BAR_FILL := Color(0.55, 0.6, 0.66, 0.8)
const C_BAR_FILL_WARN := Color(1.0, 0.35, 0.15, 0.9)
const C_PANEL_BG := Color(0.01, 0.02, 0.04, 0.35)
const C_BORDER := Color(0.0, 0.6, 0.8, 0.18)
const C_WHITE_DIM := Color(0.8, 0.82, 0.84, 0.5)
const C_RETICLE := Color(0.85, 0.88, 0.9, 0.55)

# ── Sizing ───────────────────────────────────────────────────────────────
const TOP_PANEL_W := 320.0
const TOP_PANEL_H := 72.0
const BAR_H := 5.0
const BOTTOM_MSG_W := 480.0
const BOTTOM_MSG_H := 64.0
const COMPASS_SIZE := 48.0
const MARGIN := 28.0
const FONT_PRIMARY := 14
const FONT_HEADER := 18
const FONT_BIG := 26
const FONT_SMALL := 11
const RETICLE_DOT_SIZE := 3.0
const RETICLE_GAP := 8.0

# ── Node references (procedural) ────────────────────────────────────────
var player: Node = null

# Top-left: Life Support
var tl_o2_value: Label
var tl_bar_bg: ColorRect
var tl_bar_fill: ColorRect
var tl_coords: Label
var tl_suit_label: Label

# Top-right: Navigation
var tr_heading_value: Label
var tr_bar_bg: ColorRect
var tr_bar_fill: ColorRect
var tr_nav_info: Label
var tr_storm_label: Label

# Compass rose
var compass_container: Control
var compass_needle_phase: float = 0.0

# Center reticle
var reticle_dots: Array[ColorRect] = []

# Bottom-left: AI status
var bl_ai_label: Label
var bl_ai_indicator: ColorRect

# Bottom-right: Mission message
var br_msg_panel: ColorRect
var br_msg_header: Label
var br_msg_body: Label

# Touch input (preserve existing functionality)
var look_touch_area: Control
var look_hint: Label
var active_touch_id: int = -1
var mouse_look_active: bool = false

# Pause
var pause_button: Button
var pause_overlay: Control
var resume_button: Button
var exit_button: Button

# Animation
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
	scan_line_phase = fposmod(scan_line_phase + delta * 0.8, 1.0)
	pulse_phase = fposmod(pulse_phase + delta * 2.4, TAU)

	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_status_snapshot"):
		return

	var snap: Dictionary = player.call("get_status_snapshot")
	_update_life_support(snap)
	_update_navigation(snap)
	_update_reticle()
	_update_ai_status(snap)
	_update_mission_message(snap)

## ── Build HUD ───────────────────────────────────────────────────────────

func _build_hud() -> void:
	_build_top_left()
	_build_top_right()
	_build_compass()
	_build_reticle()
	_build_bottom_left()
	_build_bottom_right()
	_build_touch_area()
	_build_pause_overlay()

func _build_top_left() -> void:
	var panel := _make_panel(TOP_PANEL_W, TOP_PANEL_H)
	panel.position = Vector2(MARGIN, MARGIN)
	add_child(panel)

	# O2 value — large cyan number
	tl_o2_value = _make_label("O2: 88%", FONT_BIG, C_CYAN)
	tl_o2_value.position = Vector2(12, 4)
	panel.add_child(tl_o2_value)

	# Suit power small label
	tl_suit_label = _make_label("PWR 100%", FONT_SMALL, C_CYAN_DIM)
	tl_suit_label.position = Vector2(200, 12)
	panel.add_child(tl_suit_label)

	# Thin bar background
	tl_bar_bg = _make_bar_bg(TOP_PANEL_W - 24.0, BAR_H)
	tl_bar_bg.position = Vector2(12, 38)
	panel.add_child(tl_bar_bg)

	# Thin bar fill
	tl_bar_fill = _make_bar_fill(TOP_PANEL_W - 24.0, BAR_H)
	tl_bar_fill.position = Vector2(12, 38)
	panel.add_child(tl_bar_fill)

	# Coordinates
	tl_coords = _make_label("LAT 0.00  LON 0.00", FONT_SMALL, C_CYAN_DIM)
	tl_coords.position = Vector2(12, 50)
	panel.add_child(tl_coords)

func _build_top_right() -> void:
	var panel := _make_panel(TOP_PANEL_W, TOP_PANEL_H)
	add_child(panel)
	panel.name = "TopRightPanel"  # Positioned in _on_window_resized

	# Heading — large value
	tr_heading_value = _make_label("N  000°", FONT_BIG, C_CYAN)
	tr_heading_value.position = Vector2(12, 4)
	panel.add_child(tr_heading_value)

	# Distance / waypoint info
	tr_nav_info = _make_label("55m", FONT_SMALL, C_CYAN_DIM)
	tr_nav_info.position = Vector2(200, 12)
	panel.add_child(tr_nav_info)

	# Thin bar background
	tr_bar_bg = _make_bar_bg(TOP_PANEL_W - 24.0, BAR_H)
	tr_bar_bg.position = Vector2(12, 38)
	panel.add_child(tr_bar_bg)

	# Thin bar fill (storm progress)
	tr_bar_fill = _make_bar_fill(TOP_PANEL_W - 24.0, BAR_H)
	tr_bar_fill.position = Vector2(12, 38)
	panel.add_child(tr_bar_fill)

	# Storm ETA
	tr_storm_label = _make_label("STORM 4h 22m", FONT_SMALL, C_CYAN_DIM)
	tr_storm_label.position = Vector2(12, 50)
	panel.add_child(tr_storm_label)

func _build_compass() -> void:
	compass_container = Control.new()
	compass_container.custom_minimum_size = Vector2(COMPASS_SIZE, COMPASS_SIZE)
	compass_container.size = Vector2(COMPASS_SIZE, COMPASS_SIZE)
	compass_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(compass_container)

	# Compass outer ring
	var ring := ColorRect.new()
	ring.color = C_BORDER
	ring.size = Vector2(COMPASS_SIZE, COMPASS_SIZE)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_container.add_child(ring)

	# Compass inner (dark)
	var inner := ColorRect.new()
	inner.color = C_PANEL_BG
	inner.size = Vector2(COMPASS_SIZE - 4, COMPASS_SIZE - 4)
	inner.position = Vector2(2, 2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_container.add_child(inner)

	# Cross lines
	var h_line := ColorRect.new()
	h_line.color = C_CYAN_DIM
	h_line.size = Vector2(COMPASS_SIZE - 12, 1)
	h_line.position = Vector2(6, COMPASS_SIZE / 2.0)
	h_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_container.add_child(h_line)

	var v_line := ColorRect.new()
	v_line.color = C_CYAN_DIM
	v_line.size = Vector2(1, COMPASS_SIZE - 12)
	v_line.position = Vector2(COMPASS_SIZE / 2.0, 6)
	v_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_container.add_child(v_line)

	# Center dot (bright)
	var dot := ColorRect.new()
	dot.color = C_CYAN
	dot.size = Vector2(4, 4)
	dot.position = Vector2(COMPASS_SIZE / 2.0 - 2, COMPASS_SIZE / 2.0 - 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_container.add_child(dot)

func _build_reticle() -> void:
	# 4 small dots forming a minimal crosshair in screen center
	reticle_dots.clear()
	for i in range(4):
		var dot := ColorRect.new()
		dot.color = C_RETICLE
		dot.size = Vector2(RETICLE_DOT_SIZE, RETICLE_DOT_SIZE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		reticle_dots.append(dot)

func _build_bottom_left() -> void:
	# AI link status indicator
	bl_ai_indicator = ColorRect.new()
	bl_ai_indicator.color = C_CYAN
	bl_ai_indicator.size = Vector2(6, 6)
	bl_ai_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bl_ai_indicator)

	bl_ai_label = _make_label("MARVIN", FONT_PRIMARY, C_CYAN)
	add_child(bl_ai_label)

func _build_bottom_right() -> void:
	br_msg_panel = ColorRect.new()
	br_msg_panel.color = C_PANEL_BG
	br_msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(br_msg_panel)

	br_msg_header = _make_label("CHANNEL", FONT_SMALL, C_CYAN_DIM)
	br_msg_panel.add_child(br_msg_header)

	br_msg_body = _make_label("O2 resources critical assessment", FONT_PRIMARY, C_CYAN)
	br_msg_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	br_msg_panel.add_child(br_msg_body)

func _build_touch_area() -> void:
	look_touch_area = Control.new()
	look_touch_area.name = "LookTouchArea"
	look_touch_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_touch_area.anchor_left = 0.46
	look_touch_area.offset_top = 88.0
	look_touch_area.offset_right = -16.0
	look_touch_area.offset_bottom = -16.0
	look_touch_area.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(look_touch_area)
	look_touch_area.gui_input.connect(_on_look_touch_input)

	look_hint = Label.new()
	look_hint.text = "DRAG RIGHT SIDE TO LOOK"
	look_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	look_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	look_hint.offset_left = -240.0
	look_hint.offset_top = -64.0
	look_hint.offset_right = -16.0
	look_hint.offset_bottom = -20.0
	look_hint.modulate = Color(1, 1, 1, 0.3)
	look_hint.add_theme_font_size_override("font_size", FONT_SMALL)
	look_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look_touch_area.add_child(look_hint)

func _build_pause_overlay() -> void:
	# Minimal pause button (transparent, top-right area)
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = "II"
	pause_button.flat = true
	pause_button.add_theme_font_size_override("font_size", 18)
	pause_button.add_theme_color_override("font_color", C_CYAN_DIM)
	pause_button.add_theme_color_override("font_hover_color", C_CYAN)
	add_child(pause_button)
	pause_button.pressed.connect(_on_pause_pressed)

	# Pause overlay
	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	add_child(pause_overlay)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.64)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(dimmer)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.03, 0.05, 0.92)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = C_CYAN_DIM
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.corner_radius_bottom_left = 12

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -180.0
	panel.offset_top = -120.0
	panel.offset_right = 180.0
	panel.offset_bottom = 120.0
	panel.add_theme_stylebox_override("panel", panel_style)
	pause_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C_CYAN)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Resume the mission or exit."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	subtitle.add_theme_font_size_override("font_size", 14)
	vbox.add_child(subtitle)

	resume_button = Button.new()
	resume_button.text = "RESUME"
	resume_button.name = "ResumeButton"
	vbox.add_child(resume_button)
	resume_button.pressed.connect(_on_resume_pressed)

	exit_button = Button.new()
	exit_button.text = "EXIT GAME"
	exit_button.name = "ExitButton"
	vbox.add_child(exit_button)
	exit_button.pressed.connect(_on_exit_pressed)

## ── Update HUD Data ─────────────────────────────────────────────────────

func _update_life_support(snap: Dictionary) -> void:
	var o2 := float(snap.get("oxygen", 88.0))
	var o2_max := float(snap.get("oxygen_max", 100.0))
	var ratio := clampf(o2 / max(o2_max, 1.0), 0.0, 1.0)

	tl_o2_value.text = "O2: %d%%" % int(round(o2))

	# Suit power from GameState
	var suit_drain := GameState.get_suit_drain_multiplier()
	var suit_pct := int(round(clampf(suit_drain, 0.0, 1.0) * 100.0))
	tl_suit_label.text = "PWR %d%%" % suit_pct

	# Bar fill
	tl_bar_fill.size.x = (TOP_PANEL_W - 24.0) * ratio

	# Warning color
	if ratio < 0.25:
		tl_bar_fill.color = C_BAR_FILL_WARN
		tl_o2_value.add_theme_color_override("font_color", C_BAR_FILL_WARN.lerp(C_CYAN, 0.5 + 0.5 * sin(pulse_phase)))
	else:
		tl_bar_fill.color = C_BAR_FILL
		tl_o2_value.add_theme_color_override("font_color", C_CYAN)

	# Coordinates
	var coords: Vector2 = snap.get("coords", Vector2.ZERO)
	tl_coords.text = "LAT %.1f  LON %.1f" % [coords.x, coords.y]

func _update_navigation(snap: Dictionary) -> void:
	var heading_label: String = str(snap.get("heading_label", "N"))
	var heading_deg := float(snap.get("heading_degrees", 0.0))
	tr_heading_value.text = "%s  %03d°" % [heading_label, int(heading_deg)]

	# Waypoint distance
	var wp_dist := float(snap.get("waypoint_distance", -1.0))
	var wp_name: String = str(snap.get("active_waypoint", ""))
	if wp_dist >= 0.0:
		tr_nav_info.text = "%dm" % int(round(wp_dist))
	elif not wp_name.is_empty():
		tr_nav_info.text = wp_name.left(12)
	else:
		tr_nav_info.text = ""

	# Storm ETA
	var storm_eta: String = str(snap.get("storm_eta_label", "0h 00m"))
	tr_storm_label.text = "STORM %s" % storm_eta

	# Storm bar fill (inversely proportional to remaining time)
	var storm_intensity := float(snap.get("storm_intensity", 0.0))
	tr_bar_fill.size.x = (TOP_PANEL_W - 24.0) * clampf(storm_intensity, 0.05, 1.0)
	if storm_intensity > 0.6:
		tr_bar_fill.color = C_BAR_FILL_WARN
	else:
		tr_bar_fill.color = C_BAR_FILL

func _update_reticle() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var cx := vp_size.x * 0.5
	var cy := vp_size.y * 0.5
	var half := RETICLE_DOT_SIZE * 0.5

	# 4 dots: up, down, left, right
	if reticle_dots.size() >= 4:
		reticle_dots[0].position = Vector2(cx - half, cy - RETICLE_GAP - half)
		reticle_dots[1].position = Vector2(cx - half, cy + RETICLE_GAP - half)
		reticle_dots[2].position = Vector2(cx - RETICLE_GAP - half, cy - half)
		reticle_dots[3].position = Vector2(cx + RETICLE_GAP - half, cy - half)

func _update_ai_status(snap: Dictionary) -> void:
	var marvin_state: String = str(snap.get("marvin_conversation_state", "STANDBY"))
	var sudo_state: String = ""
	if player and "sudo_ai_state" in player:
		sudo_state = str(player.get("sudo_ai_state"))

	if not sudo_state.is_empty() and sudo_state != "OFFLINE":
		bl_ai_label.text = sudo_state
		bl_ai_indicator.color = C_CYAN_BRIGHT
	else:
		bl_ai_label.text = marvin_state
		bl_ai_indicator.color = C_CYAN

	# Pulse the indicator
	bl_ai_indicator.modulate.a = 0.6 + 0.4 * sin(pulse_phase * 0.5)

func _update_mission_message(snap: Dictionary) -> void:
	var msg: String = str(snap.get("marvin_message", ""))
	var focus: String = str(snap.get("focus_name", ""))
	var time_label: String = str(snap.get("time_label", "00:00:00"))

	br_msg_header.text = "CHANNEL  %s" % time_label
	if not msg.is_empty():
		br_msg_body.text = msg
	else:
		br_msg_body.text = focus

## ── Layout ──────────────────────────────────────────────────────────────

func _on_window_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	var is_portrait: bool = vp.y > vp.x

	# Top-right panel
	var tr_panel := get_node_or_null("TopRightPanel")
	if tr_panel:
		tr_panel.position = Vector2(vp.x - TOP_PANEL_W - MARGIN, MARGIN)

	# Compass
	if compass_container:
		compass_container.position = Vector2(vp.x - MARGIN - COMPASS_SIZE, MARGIN + TOP_PANEL_H + 8)

	# Bottom-left AI status
	if bl_ai_indicator:
		bl_ai_indicator.position = Vector2(MARGIN, vp.y - MARGIN - 20)
	if bl_ai_label:
		bl_ai_label.position = Vector2(MARGIN + 12, vp.y - MARGIN - 24)

	# Bottom-right message panel
	if br_msg_panel:
		br_msg_panel.position = Vector2(vp.x - BOTTOM_MSG_W - MARGIN, vp.y - BOTTOM_MSG_H - MARGIN)
		br_msg_panel.size = Vector2(BOTTOM_MSG_W, BOTTOM_MSG_H)
	if br_msg_header:
		br_msg_header.position = Vector2(10, 4)
		br_msg_header.size = Vector2(BOTTOM_MSG_W - 20, 16)
	if br_msg_body:
		br_msg_body.position = Vector2(10, 22)
		br_msg_body.size = Vector2(BOTTOM_MSG_W - 20, 38)

	# Pause button
	if pause_button:
		pause_button.position = Vector2(vp.x - 60, MARGIN + TOP_PANEL_H + COMPASS_SIZE + 16)
		pause_button.size = Vector2(32, 32)

	# Touch hint
	if look_hint:
		if is_portrait:
			look_hint.text = "DRAG TO LOOK"
		else:
			look_hint.text = "DRAG RIGHT SIDE TO LOOK"

## ── Factory Helpers ─────────────────────────────────────────────────────

func _make_panel(w: float, h: float) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = C_PANEL_BG
	panel.size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_bar_bg(w: float, h: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = C_BAR_BG
	bar.size = Vector2(w, h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

func _make_bar_fill(w: float, h: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = C_BAR_FILL
	bar.size = Vector2(w, h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

## ── Pause ───────────────────────────────────────────────────────────────

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

## ── Touch Input ─────────────────────────────────────────────────────────

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
