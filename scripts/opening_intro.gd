class_name OpeningIntro
extends Control

const DEFAULT_VIDEO_SIZE := Vector2i(1920, 1080)
const EDGE_SHADER := preload("res://shaders/intro_edge_fill.gdshader")

@export_file("*.ogv") var intro_stream_path: String = "res://assets/video/opening_scene.ogv"
@export_file("*.tscn") var next_scene_path: String = "res://scenes/hero_demo.tscn"
@export_range(0.0, 10.0, 0.1) var skip_delay_seconds: float = 1.0
@export_range(0.05, 5.0, 0.05) var fade_duration: float = 0.4
@export_enum("mirror_blur", "none") var adaptive_fill_mode: String = "mirror_blur"

var _transitioning: bool = false
var _skip_allowed: bool = false

var _background_rect: ColorRect
var _main_video_rect: TextureRect
var _top_fill_rect: ColorRect
var _bottom_fill_rect: ColorRect
var _left_fill_rect: ColorRect
var _right_fill_rect: ColorRect
var _skip_hint_label: Label
var _fade_rect: ColorRect
var _subviewport: SubViewport
var _video_player: VideoStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ensure_skip_intro_action()
	_build_ui()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)

	var intro_stream := _load_intro_stream()
	if intro_stream == null:
		push_warning("Opening intro stream is unavailable. Falling back to hero demo.")
		call_deferred("_go_to_next_scene")
		return

	_video_player.stream = intro_stream
	_video_player.finished.connect(_on_intro_finished)
	_video_player.play()
	_fade_rect.modulate.a = 1.0
	_skip_hint_label.modulate.a = 0.0

	var fade_in := create_tween()
	fade_in.tween_property(_fade_rect, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(skip_delay_seconds).timeout.connect(_unlock_skip)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _skip_allowed:
		_start_transition()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return

	if event.is_action_pressed("skip_intro") and _skip_allowed:
		_start_transition()
		get_viewport().set_input_as_handled()
		return

	if not _skip_allowed:
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_start_transition()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		if screen_touch.pressed:
			_start_transition()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton:
		var joypad_button := event as InputEventJoypadButton
		if joypad_button.pressed and joypad_button.button_index == JOY_BUTTON_BACK:
			_start_transition()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_background_rect = ColorRect.new()
	_background_rect.color = Color.BLACK
	_background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_rect)

	_subviewport = SubViewport.new()
	_subviewport.name = "VideoViewport"
	_subviewport.disable_3d = true
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_subviewport.size = DEFAULT_VIDEO_SIZE
	_subviewport.transparent_bg = false
	add_child(_subviewport)

	_video_player = VideoStreamPlayer.new()
	_video_player.name = "IntroVideoPlayer"
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subviewport.add_child(_video_player)

	var source_texture: ViewportTexture = _subviewport.get_texture()
	_main_video_rect = TextureRect.new()
	_main_video_rect.name = "MainVideo"
	_main_video_rect.texture = source_texture
	_main_video_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_main_video_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_video_rect)

	_top_fill_rect = _make_fill_rect("TopFill", source_texture)
	_bottom_fill_rect = _make_fill_rect("BottomFill", source_texture)
	_left_fill_rect = _make_fill_rect("LeftFill", source_texture)
	_right_fill_rect = _make_fill_rect("RightFill", source_texture)
	add_child(_top_fill_rect)
	add_child(_bottom_fill_rect)
	add_child(_left_fill_rect)
	add_child(_right_fill_rect)

	_skip_hint_label = Label.new()
	_skip_hint_label.name = "SkipHint"
	_skip_hint_label.text = "Tap, click, or press a button to skip"
	_skip_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_skip_hint_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_skip_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skip_hint_label)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

func _make_fill_rect(node_name: String, source_texture: Texture2D) -> ColorRect:
	var fill_rect := ColorRect.new()
	fill_rect.name = node_name
	fill_rect.color = Color.WHITE
	fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = EDGE_SHADER
	material.set_shader_parameter("source_texture", source_texture)
	material.set_shader_parameter("source_texel_size", Vector2(1.0 / float(DEFAULT_VIDEO_SIZE.x), 1.0 / float(DEFAULT_VIDEO_SIZE.y)))
	fill_rect.material = material
	return fill_rect

func _apply_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_background_rect.size = viewport_size
	_fade_rect.size = viewport_size
	_skip_hint_label.position = Vector2(0.0, viewport_size.y - 56.0)
	_skip_hint_label.size = Vector2(viewport_size.x - 28.0, 32.0)

	var video_aspect := float(DEFAULT_VIDEO_SIZE.x) / float(DEFAULT_VIDEO_SIZE.y)
	var viewport_aspect := viewport_size.x / maxf(viewport_size.y, 0.001)
	var main_size := Vector2.ZERO
	if viewport_aspect > video_aspect:
		main_size.y = viewport_size.y
		main_size.x = viewport_size.y * video_aspect
	else:
		main_size.x = viewport_size.x
		main_size.y = viewport_size.x / video_aspect

	var main_position := (viewport_size - main_size) * 0.5
	_main_video_rect.position = main_position
	_main_video_rect.size = main_size
	_layout_fill_rects(viewport_size, Rect2(main_position, main_size))

func _layout_fill_rects(viewport_size: Vector2, main_rect: Rect2) -> void:
	var fill_rects := [_top_fill_rect, _bottom_fill_rect, _left_fill_rect, _right_fill_rect]
	for fill_rect in fill_rects:
		fill_rect.visible = false

	if adaptive_fill_mode != "mirror_blur":
		return

	var horizontal_gap := main_rect.position.x
	var vertical_gap := main_rect.position.y
	if horizontal_gap > 1.0:
		_left_fill_rect.position = Vector2.ZERO
		_left_fill_rect.size = Vector2(horizontal_gap, viewport_size.y)
		_configure_fill_material(_left_fill_rect, Vector4(0.0, 0.0, 0.17, 1.0), true, false)
		_left_fill_rect.visible = true

		_right_fill_rect.position = Vector2(main_rect.position.x + main_rect.size.x, 0.0)
		_right_fill_rect.size = Vector2(viewport_size.x - _right_fill_rect.position.x, viewport_size.y)
		_configure_fill_material(_right_fill_rect, Vector4(0.83, 0.0, 1.0, 1.0), true, false)
		_right_fill_rect.visible = true
	elif vertical_gap > 1.0:
		_top_fill_rect.position = Vector2.ZERO
		_top_fill_rect.size = Vector2(viewport_size.x, vertical_gap)
		_configure_fill_material(_top_fill_rect, Vector4(0.0, 0.0, 1.0, 0.18), false, true)
		_top_fill_rect.visible = true

		_bottom_fill_rect.position = Vector2(0.0, main_rect.position.y + main_rect.size.y)
		_bottom_fill_rect.size = Vector2(viewport_size.x, viewport_size.y - _bottom_fill_rect.position.y)
		_configure_fill_material(_bottom_fill_rect, Vector4(0.0, 0.82, 1.0, 1.0), false, true)
		_bottom_fill_rect.visible = true

func _configure_fill_material(fill_rect: ColorRect, sample_rect: Vector4, mirror_x: bool, mirror_y: bool) -> void:
	var material := fill_rect.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("sample_rect", sample_rect)
	material.set_shader_parameter("mirror_x", mirror_x)
	material.set_shader_parameter("mirror_y", mirror_y)

func _unlock_skip() -> void:
	if _transitioning:
		return
	_skip_allowed = true
	var hint_tween := create_tween()
	hint_tween.tween_property(_skip_hint_label, "modulate:a", 0.72, 0.22)

func _start_transition() -> void:
	if _transitioning:
		return
	_transitioning = true
	_skip_allowed = false
	var fade_out := create_tween()
	fade_out.tween_property(_fade_rect, "modulate:a", 1.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_out.finished.connect(_go_to_next_scene)

func _on_intro_finished() -> void:
	_start_transition()

func _go_to_next_scene() -> void:
	if is_instance_valid(_video_player):
		_video_player.stop()
	var scene_error := get_tree().change_scene_to_file(next_scene_path)
	if scene_error != OK:
		push_error("Failed to load next scene: %s (error %d)" % [next_scene_path, scene_error])

func _load_intro_stream() -> VideoStream:
	if intro_stream_path.is_empty():
		return null
	if not ResourceLoader.exists(intro_stream_path):
		return null
	return load(intro_stream_path) as VideoStream

func _ensure_skip_intro_action() -> void:
	if not InputMap.has_action("skip_intro"):
		InputMap.add_action("skip_intro")

	_bind_key_if_missing(KEY_SPACE)
	_bind_key_if_missing(KEY_ENTER)
	_bind_key_if_missing(KEY_KP_ENTER)
	_bind_key_if_missing(KEY_ESCAPE)
	_bind_key_if_missing(KEY_BACK)
	_bind_joypad_if_missing(JOY_BUTTON_A)
	_bind_joypad_if_missing(JOY_BUTTON_BACK)

func _bind_key_if_missing(keycode: Key) -> void:
	for event in InputMap.action_get_events("skip_intro"):
		if event is InputEventKey and (event as InputEventKey).keycode == keycode:
			return

	var input_event := InputEventKey.new()
	input_event.keycode = keycode
	InputMap.action_add_event("skip_intro", input_event)

func _bind_joypad_if_missing(button_index: JoyButton) -> void:
	for event in InputMap.action_get_events("skip_intro"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
			return

	var input_event := InputEventJoypadButton.new()
	input_event.button_index = button_index
	InputMap.action_add_event("skip_intro", input_event)
