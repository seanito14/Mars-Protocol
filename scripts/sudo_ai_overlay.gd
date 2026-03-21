class_name SudoAIOverlay
extends Control

## Futuristic voice waveform overlay for SudoAI.
## Shows "SUDO AI ACTIVATED" with animated voice waveform bars.
## Entirely procedural — no .tscn file needed.

const BAR_COUNT: int = 32
const BAR_WIDTH: float = 6.0
const BAR_GAP: float = 3.0
const BAR_MAX_HEIGHT: float = 80.0
const BAR_MIN_HEIGHT: float = 4.0
const OVERLAY_COLOR := Color(0.0, 0.0, 0.02, 0.35)
const PRIMARY_COLOR := Color(0.0, 0.83, 1.0, 1.0)        # #00D4FF — futuristic light blue
const SECONDARY_COLOR := Color(0.0, 1.0, 0.94, 1.0)       # #00FFF0 — cyan accent
const GLOW_COLOR := Color(0.0, 0.52, 0.78, 0.6)            # Soft glow behind text
const LABEL_FONT_SIZE: int = 36
const STATE_FONT_SIZE: int = 18
const FADE_DURATION: float = 0.4
const AUTO_DISMISS_DELAY: float = 3.0

var backdrop: ColorRect
var title_label: Label
var state_label: Label
var waveform_container: Control
var bars: Array[ColorRect] = []
var bar_targets: Array[float] = []
var bar_velocities: Array[float] = []
var glow_phase: float = 0.0
var ambient_phase: float = 0.0
var dismiss_timer: float = -1.0
var is_visible_overlay: bool = false
var fade_tween: Tween = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_init_bar_data()

	# Connect to SudoAI events
	EventBus.sudo_ai_hot_word_activated.connect(_on_hot_word_activated)
	EventBus.sudo_ai_overlay_dismissed.connect(_on_overlay_dismissed)
	EventBus.sudo_ai_listening_started.connect(_on_listening_started)
	EventBus.sudo_ai_listening_stopped.connect(_on_listening_stopped)
	EventBus.sudo_ai_state_changed.connect(_on_state_changed)
	EventBus.sudo_ai_speech_finished.connect(_on_speech_finished)
	EventBus.sudo_ai_agent_response.connect(_on_agent_response)

func _build_ui() -> void:
	# ── Backdrop ──
	backdrop = ColorRect.new()
	backdrop.color = OVERLAY_COLOR
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# ── Center container ──
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	# ── Title: "SUDO AI ACTIVATED" ──
	title_label = Label.new()
	title_label.text = "SUDO AI ACTIVATED"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	title_label.add_theme_color_override("font_color", PRIMARY_COLOR)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	# ── Waveform container ──
	waveform_container = Control.new()
	var total_width: float = (BAR_WIDTH + BAR_GAP) * float(BAR_COUNT) - BAR_GAP
	waveform_container.custom_minimum_size = Vector2(total_width, BAR_MAX_HEIGHT * 2.0 + 20.0)
	waveform_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(waveform_container)

	# ── Create bars ──
	for i in range(BAR_COUNT):
		var bar := ColorRect.new()
		var t := float(i) / float(BAR_COUNT - 1)
		bar.color = PRIMARY_COLOR.lerp(SECONDARY_COLOR, t)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		waveform_container.add_child(bar)
		bars.append(bar)

	# ── State label ──
	state_label = Label.new()
	state_label.text = "INITIALIZING..."
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.add_theme_font_size_override("font_size", STATE_FONT_SIZE)
	state_label.add_theme_color_override("font_color", PRIMARY_COLOR.lerp(Color.WHITE, 0.3))
	state_label.modulate.a = 0.8
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(state_label)

func _init_bar_data() -> void:
	bar_targets.clear()
	bar_velocities.clear()
	for i in range(BAR_COUNT):
		bar_targets.append(0.0)
		bar_velocities.append(0.0)

func _process(delta: float) -> void:
	if not is_visible_overlay:
		return

	glow_phase = fposmod(glow_phase + delta * 2.2, TAU)
	ambient_phase = fposmod(ambient_phase + delta * 1.4, TAU)

	# ── Title glow pulse ──
	var glow_factor := 0.75 + 0.25 * sin(glow_phase)
	title_label.modulate.a = glow_factor
	title_label.add_theme_color_override("font_color", PRIMARY_COLOR.lerp(Color.WHITE, 0.15 * sin(glow_phase * 0.5)))

	# ── Update bar targets ──
	var input_vol: float = 0.0
	var output_vol: float = 0.0
	if SudoAIAgent:
		input_vol = SudoAIAgent.get_input_volume()
		output_vol = SudoAIAgent.get_output_volume()

	var active_volume := maxf(input_vol * 3.0, output_vol)

	for i in range(BAR_COUNT):
		var t := float(i) / float(BAR_COUNT - 1)
		var center_distance: float = absf(t - 0.5) * 2.0  # 0 at center, 1 at edges

		# Ambient wave (always running)
		var ambient := sin(ambient_phase + t * TAU * 2.0) * 0.15 + 0.15

		# Voice-reactive component
		var voice_component: float = 0.0
		if active_volume > 0.01:
			var wave1 := sin((ambient_phase * 3.8) + t * TAU * 3.0) * 0.5 + 0.5
			var wave2 := sin((ambient_phase * 5.2) + t * TAU * 1.5 + 1.3) * 0.5 + 0.5
			var wave3 := sin((ambient_phase * 7.1) + t * TAU * 4.5 + 2.7) * 0.5 + 0.5
			voice_component = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2) * active_volume
			voice_component *= (1.0 - center_distance * 0.4)  # Taller in center

		bar_targets[i] = clampf(ambient + voice_component, 0.05, 1.0)

	# ── Animate bars with spring physics ──
	var container_center_y := waveform_container.custom_minimum_size.y * 0.5
	var total_width: float = (BAR_WIDTH + BAR_GAP) * float(BAR_COUNT) - BAR_GAP
	var start_x := (waveform_container.custom_minimum_size.x - total_width) * 0.5

	for i in range(BAR_COUNT):
		# Spring toward target
		var diff := bar_targets[i] - bar_velocities[i]
		bar_velocities[i] += diff * delta * 12.0
		bar_velocities[i] = clampf(bar_velocities[i], 0.0, 1.0)

		var bar_height := lerpf(BAR_MIN_HEIGHT, BAR_MAX_HEIGHT, bar_velocities[i])
		var x_pos := start_x + float(i) * (BAR_WIDTH + BAR_GAP)
		var y_pos := container_center_y - bar_height  # Bars grow upward from center

		bars[i].position = Vector2(x_pos, y_pos)
		bars[i].size = Vector2(BAR_WIDTH, bar_height * 2.0)  # Symmetric above/below center

		# Color intensity based on height
		var t := float(i) / float(BAR_COUNT - 1)
		var base_color: Color = PRIMARY_COLOR.lerp(SECONDARY_COLOR, t)
		bars[i].color = base_color.lerp(Color.WHITE, bar_velocities[i] * 0.3)
		bars[i].modulate.a = 0.5 + bar_velocities[i] * 0.5

	# ── Auto-dismiss countdown ──
	if dismiss_timer >= 0.0:
		dismiss_timer -= delta
		if dismiss_timer <= 0.0:
			dismiss_timer = -1.0
			hide_overlay()

func show_overlay() -> void:
	if is_visible_overlay:
		return
	is_visible_overlay = true
	visible = true
	dismiss_timer = -1.0
	modulate.a = 0.0
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	state_label.text = "LISTENING..."

func hide_overlay() -> void:
	if not is_visible_overlay:
		return
	is_visible_overlay = false
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fade_tween.finished.connect(func(): visible = false)

func schedule_dismiss() -> void:
	dismiss_timer = AUTO_DISMISS_DELAY

## ── Event Handlers ──────────────────────────────────────────────────────

func _on_hot_word_activated() -> void:
	show_overlay()

func _on_overlay_dismissed() -> void:
	hide_overlay()

func _on_listening_started() -> void:
	show_overlay()
	state_label.text = "LISTENING..."

func _on_listening_stopped() -> void:
	state_label.text = "STANDBY"
	schedule_dismiss()

func _on_state_changed(state_text: String) -> void:
	match state_text:
		"SPEAKING":
			state_label.text = "SUDO AI SPEAKING..."
			dismiss_timer = -1.0  # Cancel dismiss while speaking
		"LISTENING":
			state_label.text = "LISTENING..."
			dismiss_timer = -1.0
		"CONNECTED":
			if is_visible_overlay:
				state_label.text = "STANDBY"
		"OFFLINE", "ERROR":
			state_label.text = state_text
			schedule_dismiss()

func _on_speech_finished() -> void:
	state_label.text = "STANDBY"
	schedule_dismiss()

func _on_agent_response(_text: String) -> void:
	if not is_visible_overlay:
		show_overlay()
	state_label.text = "SUDO AI SPEAKING..."
	dismiss_timer = -1.0
