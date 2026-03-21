class_name HeroHUD
extends Control

const C_FRAME_DARK := Color(0.1, 0.055, 0.03, 0.985)
const C_FRAME_MID := Color(0.3, 0.16, 0.08, 0.92)
const C_FRAME_GLOW := Color(0.58, 0.34, 0.18, 0.32)
const C_SLOT_GLOW := Color(0.4, 0.86, 1.0, 0.88)
const C_AMBER := Color(0.96, 0.62, 0.18, 0.82)

const C_TEXT := Color(0.92, 0.96, 1.0, 0.95)
const C_TEXT_DIM := Color(0.73, 0.82, 0.9, 0.62)
const C_PANEL_BG := Color(0.18, 0.2, 0.23, 0.2)
const C_LINE := Color(0.73, 0.79, 0.86, 0.36)
const C_RETICLE := Color(0.68, 0.88, 0.98, 0.36)
const C_GRID_FAINT := Color(0.58, 0.66, 0.74, 0.08)
const C_COMPASS := Color(0.82, 0.92, 0.98, 0.82)

var player: HeroPlayer = null

var top_left_rail: Control
var tl_05e_label: Label
var tl_line: ColorRect
var tl_general_label: Label

var top_right_rail: Control
var tr_max_label: Label
var tr_line: ColorRect
var tr_70ec_label: Label

var bottom_left_panel: Control
var bl_stat_line1: Label
var bl_stat_line2: Label
var bl_line: ColorRect
var bl_blur_rect: ColorRect

var bottom_right_panel: Control
var br_channel_label: Label
var br_fiction_label: Label
var br_id_label: Label
var br_line: ColorRect

var compass_root: Control
var compass_heading_label: Label
var compass_wp_label: Label

var interact_prompt_label: Label

var look_touch_area: Control
var hud_scale: float = 1.0
var vignette_rect: ColorRect
var vignette_material: ShaderMaterial

# Pause menu
var pause_menu: Control = null
var is_paused: bool = false

# Mission log
var mission_log_container: VBoxContainer
var mission_log_entries: Array[Dictionary] = []
const MISSION_LOG_FADE_DURATION := 6.0
const MISSION_LOG_MAX_ENTRIES := 5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	player = get_tree().get_first_node_in_group("player") as HeroPlayer
	_build_vignette()
	_build_hud()
	_build_mission_log()
	get_viewport().size_changed.connect(_on_window_resized)
	_on_window_resized()
	
	# Connect to mission log events
	if EventBus:
		EventBus.mission_log_entry.connect(_on_mission_log_entry)

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as HeroPlayer

	if player != null:
		var snap: Dictionary = player.get_status_snapshot()
		var oxygen_max: float = float(snap.get("oxygen_max", 100.0))
		var oxygen_pct: float = (float(snap.get("oxygen", 0.0)) / maxf(oxygen_max, 0.001)) * 100.0
		var s_max: float = float(snap.get("suit_power_max", 100.0))
		var s_pct: float = (float(snap.get("suit_power", 0.0)) / maxf(s_max, 0.001)) * 100.0
		var temp_max: float = float(snap.get("temperature_resistance_max", 100.0))
		var temp_pct: float = (float(snap.get("temperature_resistance", 0.0)) / maxf(temp_max, 0.001)) * 100.0
		var heading_degrees: int = int(round(float(snap.get("heading_degrees", 0.0))))
		var heading_label: String = str(snap.get("heading_label", "N"))
		var coords: Vector2 = snap.get("coords", Vector2.ZERO)
		var clone_iteration: int = GameState.get_clone_iteration() % 1000
		# Reference-style readout: NN.E0 tracks suit power % (clamped for display).
		tr_70ec_label.text = "%02d.E0" % clampi(int(round(s_pct)), 0, 99)
		tl_05e_label.text = "%03d" % clampi(int(round(float(snap.get("elevation_m", 0.0)))), 0, 999)
		tl_general_label.text = "%s   %s" % [str(snap.get("time_label", "00:00")), heading_label]
		tr_max_label.text = "MAX\n%02d PSI" % clampi(int(round(float(snap.get("heart_rate", 55.0)) * 0.76)), 10, 99)
		bl_stat_line1.text = "O2 %02d   PWR %02d   TMP %02d" % [
			clampi(int(round(oxygen_pct)), 0, 99),
			clampi(int(round(s_pct)), 0, 99),
			clampi(int(round(temp_pct)), 0, 99)
		]
		bl_stat_line2.text = "GRID %05.1f / %05.1f" % [coords.x, coords.y]

		br_channel_label.text = "Channel"
		br_fiction_label.text = "%s   %s" % [str(snap.get("storm_eta_label", "Calm")), str(snap.get("scan_target_label", "Valley"))]
		br_id_label.text = "%03d" % clone_iteration
		compass_heading_label.text = "%03d° %s" % [posmod(heading_degrees, 360), heading_label]
		compass_wp_label.text = "SOL 247   CLONE %03d" % clone_iteration

		var show_prompt := false
		var fi: Variant = player.get("focused_interactable")
		show_prompt = fi != null and is_instance_valid(fi) and not GameState.is_modal_open()
		if show_prompt:
			interact_prompt_label.visible = true
			var fname: String = str(snap.get("focus_name", ""))
			interact_prompt_label.text = "E  —  INTERACT\n%s" % fname
		else:
			interact_prompt_label.visible = false
	else:
		interact_prompt_label.visible = false

	if vignette_material != null and player != null:
		vignette_material.set_shader_parameter("storm_intensity", float(player.get("storm_intensity")))
		vignette_material.set_shader_parameter("breathing_phase", float(player.get("breathing_phase")))

	_update_mission_log(_delta)
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var layout := _safe_layout(vp)
	_draw_visor_frame(vp, layout)
	_draw_top_left_grid(vp, layout)
	_draw_top_right_icon(vp)
	if not _should_hide_reticle():
		_draw_reticle(vp)

func _should_hide_reticle() -> bool:
	if GameState.is_modal_open():
		return true
	return false

func _safe_layout(vp: Vector2) -> Dictionary:
	var ar := vp.x / maxf(vp.y, 1.0)
	var shrink_h := 1.0
	if ar > 2.2:
		shrink_h = lerpf(1.0, 0.86, clampf((ar - 2.2) / 1.2, 0.0, 1.0))
	elif ar < 0.55:
		shrink_h = lerpf(1.0, 0.9, clampf((0.55 - ar) / 0.35, 0.0, 1.0))
	var max_w := minf(vp.x, vp.y * 2.35 * shrink_h)
	var x0 := (vp.x - max_w) * 0.5
	return {"x0": x0, "w": max_w, "h": vp.y, "shrink_h": shrink_h}

func _build_vignette() -> void:
	vignette_rect = ColorRect.new()
	vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = load("res://shaders/hero_visor_overlay.gdshader")
	vignette_rect.material = vignette_material
	add_child(vignette_rect)
	move_child(vignette_rect, 0)

func _build_hud() -> void:
	_build_top_left()
	_build_top_right()
	_build_bottom_left()
	_build_bottom_right()
	_build_compass()
	_build_interact_prompt()
	compass_root.visible = true
	bottom_left_panel.visible = true
	_build_touch_area()

func _build_top_left() -> void:
	top_left_rail = Control.new()
	top_left_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_left_rail)

	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_glass_style())
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_left_rail.add_child(panel)

	tl_05e_label = _make_label("086", 28, C_TEXT)
	top_left_rail.add_child(tl_05e_label)

	tl_line = ColorRect.new()
	tl_line.color = C_LINE
	top_left_rail.add_child(tl_line)

	tl_general_label = _make_label("06:14   N", 16, C_TEXT_DIM)
	top_left_rail.add_child(tl_general_label)

func _build_top_right() -> void:
	top_right_rail = Control.new()
	top_right_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_right_rail)

	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_glass_style())
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_right_rail.add_child(panel)

	tr_max_label = _make_label("MAX\n55 PSI", 14, C_TEXT)
	tr_max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top_right_rail.add_child(tr_max_label)

	tr_line = ColorRect.new()
	tr_line.color = C_LINE
	top_right_rail.add_child(tr_line)

	tr_70ec_label = _make_label("78.E0", 18, C_TEXT)
	tr_70ec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right_rail.add_child(tr_70ec_label)

func _build_bottom_left() -> void:
	bottom_left_panel = Control.new()
	bottom_left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_left_panel)

	bl_blur_rect = ColorRect.new()
	bl_blur_rect.color = Color(0.1, 0.2, 0.3, 0.15)
	bottom_left_panel.add_child(bl_blur_rect)

	bl_stat_line1 = _make_label("O2 99   PWR 78   TMP 99", 18, C_TEXT)
	bottom_left_panel.add_child(bl_stat_line1)

	bl_stat_line2 = _make_label("GRID 000.0 / 000.0", 15, C_TEXT_DIM)
	bottom_left_panel.add_child(bl_stat_line2)

	bl_line = ColorRect.new()
	bl_line.color = C_LINE
	bottom_left_panel.add_child(bl_line)

func _build_bottom_right() -> void:
	bottom_right_panel = Control.new()
	bottom_right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_right_panel)

	br_channel_label = _make_label("Channel", 14, C_TEXT_DIM)
	br_channel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_right_panel.add_child(br_channel_label)

	br_fiction_label = _make_label("CALM   VALLEY", 16, C_TEXT)
	br_fiction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_right_panel.add_child(br_fiction_label)

	br_id_label = _make_label("014", 15, C_TEXT_DIM)
	br_id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_right_panel.add_child(br_id_label)

	br_line = ColorRect.new()
	br_line.color = Color(0.55, 0.62, 0.68, 0.2)
	bottom_right_panel.add_child(br_line)

func _build_compass() -> void:
	compass_root = Control.new()
	compass_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(compass_root)

	compass_heading_label = _make_label("000° N", 17, C_COMPASS)
	compass_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_root.add_child(compass_heading_label)

	compass_wp_label = _make_label("SOL 247   CLONE 014", 14, C_TEXT_DIM)
	compass_wp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_root.add_child(compass_wp_label)

func _build_interact_prompt() -> void:
	interact_prompt_label = Label.new()
	interact_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	interact_prompt_label.add_theme_font_size_override("font_size", 14)
	interact_prompt_label.add_theme_color_override("font_color", C_TEXT)
	interact_prompt_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	interact_prompt_label.add_theme_constant_override("outline_size", 5)
	interact_prompt_label.text = "E  —  INTERACT"
	interact_prompt_label.visible = false
	interact_prompt_label.z_index = 8
	add_child(interact_prompt_label)

func _build_touch_area() -> void:
	look_touch_area = Control.new()
	look_touch_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_touch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(look_touch_area)

func _on_window_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	hud_scale = clampf(sqrt(vp.x * vp.y) / sqrt(1920.0 * 1080.0), 0.55, 1.25)

	var rail_w := 376.0 * hud_scale
	var rail_h := 36.0 * hud_scale

	# Top Left
	top_left_rail.size = Vector2(rail_w, rail_h)
	top_left_rail.position = Vector2(vp.x * 0.075, vp.y * 0.072)
	top_left_rail.rotation = deg_to_rad(4.4)

	tl_05e_label.position = Vector2(10 * hud_scale, -1 * hud_scale)
	tl_line.position = Vector2(72 * hud_scale, 18 * hud_scale)
	tl_line.size = Vector2(188 * hud_scale, 1.6)
	tl_general_label.position = Vector2(164 * hud_scale, 3 * hud_scale)

	# Top Right
	top_right_rail.size = Vector2(rail_w, rail_h)
	top_right_rail.position = Vector2(vp.x * 0.925 - rail_w, vp.y * 0.075)
	top_right_rail.rotation = deg_to_rad(-4.6)

	tr_max_label.position = Vector2(10 * hud_scale, -5 * hud_scale)
	tr_line.position = Vector2(78 * hud_scale, 18 * hud_scale)
	tr_line.size = Vector2(214 * hud_scale, 1.6)
	tr_70ec_label.position = Vector2(rail_w - 74 * hud_scale, 5 * hud_scale)

	# Bottom Left — height for two lines
	var bl_h := 64.0 * hud_scale
	var bl_w := minf(340.0 * hud_scale, vp.x * 0.36)
	bottom_left_panel.size = Vector2(bl_w, bl_h)
	bottom_left_panel.position = Vector2(maxf(14.0, vp.x * 0.016), vp.y * 0.89 - bl_h * 0.5)

	bl_stat_line1.position = Vector2(8 * hud_scale, 6 * hud_scale)
	bl_stat_line2.position = Vector2(8 * hud_scale, 26 * hud_scale)
	bl_blur_rect.position = Vector2(8 * hud_scale, 46 * hud_scale)
	bl_blur_rect.size = Vector2(bl_w - 16.0 * hud_scale, 8.0 * hud_scale)
	bl_line.position = Vector2(8 * hud_scale, bl_h - 9.0 * hud_scale)
	bl_line.size = Vector2(bl_w - 16.0 * hud_scale, 1.5)

	# Bottom Right — Channel block (reference layout)
	var br_w := minf(420.0 * hud_scale, vp.x * 0.42)
	var br_h := 70.0 * hud_scale
	bottom_right_panel.size = Vector2(br_w, br_h)
	var br_x := vp.x * 0.975 - br_w - 6.0
	br_x = clampf(br_x, 8.0, vp.x - br_w - 8.0)
	bottom_right_panel.position = Vector2(br_x, vp.y * 0.89 - br_h * 0.5)

	br_channel_label.position = Vector2(8.0 * hud_scale, 4.0 * hud_scale)
	br_channel_label.size = Vector2(br_w - 16.0 * hud_scale, 16.0 * hud_scale)
	br_fiction_label.position = Vector2(8.0 * hud_scale, 20.0 * hud_scale)
	br_fiction_label.size = Vector2(br_w - 16.0 * hud_scale, 24.0 * hud_scale)
	br_id_label.position = Vector2(br_w - 52.0 * hud_scale, 41.0 * hud_scale)
	br_id_label.size = Vector2(44.0 * hud_scale, 20.0 * hud_scale)
	br_line.position = Vector2(8.0 * hud_scale, br_h - 8.0 * hud_scale)
	br_line.size = Vector2(br_w - 16.0 * hud_scale, 1.5)

	compass_root.position = Vector2((vp.x * 0.5) - (160.0 * hud_scale), vp.y * 0.058)
	compass_root.size = Vector2(320.0 * hud_scale, 34.0 * hud_scale)
	compass_heading_label.position = Vector2(0.0, 0.0)
	compass_heading_label.size = Vector2(compass_root.size.x, 18.0 * hud_scale)
	compass_wp_label.position = Vector2(0.0, 14.0 * hud_scale)
	compass_wp_label.size = Vector2(compass_root.size.x, 16.0 * hud_scale)

	# Interaction prompt — subtle, below reticle
	var ip_w := minf(480.0 * hud_scale, vp.x * 0.65)
	interact_prompt_label.position = Vector2((vp.x - ip_w) * 0.5, vp.y * 0.5 + 52.0 * hud_scale)
	interact_prompt_label.size = Vector2(ip_w, 64.0 * hud_scale)

	_apply_font_scale()

func _apply_font_scale() -> void:
	_set_font_size(tl_05e_label, 24 * hud_scale)
	_set_font_size(tl_general_label, 14 * hud_scale)
	_set_font_size(tr_max_label, 14 * hud_scale)
	_set_font_size(tr_70ec_label, 19 * hud_scale)
	_set_font_size(bl_stat_line1, 14 * hud_scale)
	_set_font_size(bl_stat_line2, 12 * hud_scale)
	_set_font_size(br_channel_label, 13 * hud_scale)
	_set_font_size(br_fiction_label, 14 * hud_scale)
	_set_font_size(br_id_label, 15 * hud_scale)
	_set_font_size(compass_heading_label, 15 * hud_scale)
	_set_font_size(compass_wp_label, 12 * hud_scale)
	_set_font_size(interact_prompt_label, 14 * hud_scale)

func _draw_visor_frame(vp: Vector2, layout: Dictionary) -> void:
	var x0: float = layout.x0
	var w: float = layout.w
	var h: float = layout.h

	var top_border := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(vp.x, 0.0),
		Vector2(vp.x, h * 0.082),
		Vector2(x0 + (w * 0.72), h * 0.082),
		Vector2(x0 + (w * 0.655), h * 0.126),
		Vector2(x0 + (w * 0.345), h * 0.126),
		Vector2(x0 + (w * 0.28), h * 0.082),
		Vector2(0.0, h * 0.082)
	])

	var left_border := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(x0 + (w * 0.14), h * 0.02),
		Vector2(x0 + (w * 0.11), h * 0.18),
		Vector2(x0 + (w * 0.078), h * 0.46),
		Vector2(x0 + (w * 0.084), h * 0.72),
		Vector2(x0 + (w * 0.19), h),
		Vector2(0.0, h)
	])

	var right_border := PackedVector2Array([
		Vector2(vp.x, 0.0),
		Vector2(x0 + (w * 0.86), h * 0.02),
		Vector2(x0 + (w * 0.89), h * 0.18),
		Vector2(x0 + (w * 0.922), h * 0.46),
		Vector2(x0 + (w * 0.916), h * 0.72),
		Vector2(x0 + (w * 0.81), h),
		Vector2(vp.x, h)
	])

	var bottom_console := PackedVector2Array([
		Vector2(x0 + (w * 0.36), h),
		Vector2(x0 + (w * 0.405), h * 0.852),
		Vector2(x0 + (w * 0.595), h * 0.852),
		Vector2(x0 + (w * 0.64), h),
	])

	var lower_left_pod := PackedVector2Array([
		Vector2(0.0, h * 0.8),
		Vector2(x0 + (w * 0.012), h * 0.79),
		Vector2(x0 + (w * 0.05), h),
		Vector2(0.0, h)
	])

	var lower_right_pod := PackedVector2Array([
		Vector2(vp.x, h * 0.8),
		Vector2(x0 + (w * 0.988), h * 0.79),
		Vector2(x0 + (w * 0.95), h),
		Vector2(vp.x, h)
	])

	draw_colored_polygon(top_border, C_FRAME_DARK)
	draw_colored_polygon(left_border, C_FRAME_DARK)
	draw_colored_polygon(right_border, C_FRAME_DARK)
	draw_colored_polygon(bottom_console, C_FRAME_DARK)
	draw_colored_polygon(lower_left_pod, C_FRAME_DARK)
	draw_colored_polygon(lower_right_pod, C_FRAME_DARK)

	draw_polyline(top_border, C_FRAME_GLOW, 4.0, true)
	draw_polyline(left_border, C_FRAME_GLOW, 4.0, true)
	draw_polyline(right_border, C_FRAME_GLOW, 4.0, true)
	draw_polyline(bottom_console, C_FRAME_GLOW, 4.0, true)
	draw_polyline(lower_left_pod, C_FRAME_GLOW, 3.0, true)
	draw_polyline(lower_right_pod, C_FRAME_GLOW, 3.0, true)

	var slot_rect := Rect2(x0 + (w * 0.455), h * 0.032, w * 0.09, h * 0.018)
	draw_rect(slot_rect, C_SLOT_GLOW)
	draw_rect(Rect2(x0 + (w * 0.42), h * 0.038, w * 0.016, h * 0.008), C_AMBER)
	draw_rect(Rect2(x0 + (w * 0.564), h * 0.038, w * 0.016, h * 0.008), C_AMBER)

	var center_strip_y := h * 0.064
	draw_line(Vector2(x0 + (w * 0.33), center_strip_y), Vector2(x0 + (w * 0.44), center_strip_y), Color(C_LINE.r, C_LINE.g, C_LINE.b, 0.26), 1.2)
	draw_line(Vector2(x0 + (w * 0.56), center_strip_y), Vector2(x0 + (w * 0.67), center_strip_y), Color(C_LINE.r, C_LINE.g, C_LINE.b, 0.26), 1.2)

	var screen_rect := Rect2(x0 + (w * 0.424), h * 0.878, w * 0.152, h * 0.094)
	draw_rect(screen_rect, Color(0.02, 0.02, 0.02, 0.9))
	draw_rect(screen_rect, C_FRAME_MID, false, 2.0)

	var scr_right := screen_rect.position.x + screen_rect.size.x
	var cy_k := screen_rect.position.y + screen_rect.size.y * 0.5
	var r_knob := 5.5 * hud_scale
	var gap_k := 9.0 * hud_scale
	var k1x := scr_right + gap_k + r_knob
	var k2x := k1x + gap_k + r_knob * 2.0
	var knob_fill := Color(0.07, 0.07, 0.08, 0.92)
	draw_circle(Vector2(k1x, cy_k), r_knob, knob_fill)
	draw_arc(Vector2(k1x, cy_k), r_knob, 0, TAU, 28, C_FRAME_MID, 1.2, true)
	draw_circle(Vector2(k2x, cy_k), r_knob, knob_fill)
	draw_arc(Vector2(k2x, cy_k), r_knob, 0, TAU, 28, C_FRAME_MID, 1.2, true)

func _draw_top_left_grid(vp: Vector2, _layout: Dictionary) -> void:
	var gx := vp.x * 0.08 + 68.0 * hud_scale
	var gy := vp.y * 0.073 + 4.0 * hud_scale
	var gw := 176.0 * hud_scale
	var gh := 18.0 * hud_scale
	var cols := 8
	var rows := 4
	for i in range(cols + 1):
		var px := gx + (gw / float(cols)) * float(i)
		draw_line(Vector2(px, gy), Vector2(px, gy + gh), C_GRID_FAINT, 0.8)
	for j in range(rows + 1):
		var py := gy + (gh / float(rows)) * float(j)
		draw_line(Vector2(gx, py), Vector2(gx + gw, py), C_GRID_FAINT, 0.8)

func _draw_top_right_icon(vp: Vector2) -> void:
	var cx := vp.x * 0.92 - 20.0 * hud_scale
	var cy := vp.y * 0.078 + 18.0 * hud_scale
	var center := Vector2(cx, cy)
	var r := 18.0 * hud_scale
	var fill := Color(0.12, 0.14, 0.16, 0.55)
	draw_circle(center, r, fill)
	draw_arc(center, r, 0, TAU, 32, C_TEXT, 1.5, true)
	var diag := Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.82)
	draw_line(center + Vector2(-r * 0.68, -r * 0.68), center + Vector2(r * 0.68, r * 0.68), diag, 2.0)

func _draw_reticle(vp: Vector2) -> void:
	var center := vp * 0.5
	var tick := 4.2 * hud_scale
	var gap := 6.5 * hud_scale
	var c := Color(C_RETICLE.r, C_RETICLE.g, C_RETICLE.b, 0.34)
	var w := 1.25
	draw_line(center - Vector2(0, gap + tick), center - Vector2(0, gap), c, w)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + tick), c, w)
	draw_line(center - Vector2(gap + tick, 0), center - Vector2(gap, 0), c, w)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + tick, 0), c, w)
	draw_circle(center, 0.7 * hud_scale, Color(c.r, c.g, c.b, 0.42))

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_glass_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL_BG
	return style

func _set_font_size(label: Label, value: float) -> void:
	label.add_theme_font_size_override("font_size", maxi(int(round(value)), 10))

# ============================================================================
# PAUSE MENU
# ============================================================================

func toggle_pause_menu() -> void:
	if is_paused:
		_hide_pause_menu()
	else:
		_show_pause_menu()

func _show_pause_menu() -> void:
	if pause_menu != null:
		return
	
	is_paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	var pause_scene := load("res://scenes/pause_menu.tscn")
	if pause_scene:
		pause_menu = pause_scene.instantiate()
		pause_menu.resumed.connect(_on_pause_resumed)
		pause_menu.quit_to_menu.connect(_on_pause_quit_to_menu)
		add_child(pause_menu)

func _hide_pause_menu() -> void:
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null
	
	is_paused = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_pause_resumed() -> void:
	_hide_pause_menu()

func _on_pause_quit_to_menu() -> void:
	_hide_pause_menu()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ============================================================================
# MISSION LOG
# ============================================================================

func _build_mission_log() -> void:
	mission_log_container = VBoxContainer.new()
	mission_log_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_log_container.modulate = Color(1, 1, 1, 0.65)
	mission_log_container.add_theme_constant_override("separation", 6)
	add_child(mission_log_container)

func _on_mission_log_entry(message: String) -> void:
	# Create new log entry
	var entry := {
		"message": message,
		"time_remaining": MISSION_LOG_FADE_DURATION,
		"label": null
	}
	
	var label := Label.new()
	label.text = "> " + message
	label.add_theme_font_size_override("font_size", int(13 * hud_scale))
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	entry["label"] = label
	mission_log_entries.append(entry)
	mission_log_container.add_child(label)
	
	# Limit max entries
	while mission_log_entries.size() > MISSION_LOG_MAX_ENTRIES:
		var old_entry: Dictionary = mission_log_entries.pop_front()
		if old_entry.has("label") and is_instance_valid(old_entry["label"]):
			old_entry["label"].queue_free()

func _update_mission_log(delta: float) -> void:
	var vp := get_viewport_rect().size
	
	# Position log container at bottom center
	var log_w := minf(500.0 * hud_scale, vp.x * 0.6)
	mission_log_container.position = Vector2((vp.x - log_w) * 0.5, vp.y * 0.72)
	mission_log_container.size = Vector2(log_w, 150 * hud_scale)
	
	# Update each entry's fade
	var entries_to_remove: Array[int] = []
	for i in range(mission_log_entries.size()):
		var entry: Dictionary = mission_log_entries[i]
		entry["time_remaining"] -= delta
		
		if entry["time_remaining"] <= 0.0:
			entries_to_remove.append(i)
		else:
			# Fade out in last 2 seconds
			var alpha := 1.0
			if entry["time_remaining"] < 2.0:
				alpha = entry["time_remaining"] / 2.0
			
			var label: Label = entry["label"]
			if is_instance_valid(label):
				label.modulate.a = alpha
	
	# Remove expired entries (reverse order to avoid index issues)
	for i in range(entries_to_remove.size() - 1, -1, -1):
		var idx: int = entries_to_remove[i]
		var entry: Dictionary = mission_log_entries[idx]
		if entry.has("label") and is_instance_valid(entry["label"]):
			entry["label"].queue_free()
		mission_log_entries.remove_at(idx)
