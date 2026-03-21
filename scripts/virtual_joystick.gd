class_name VirtualJoystick
extends Control

signal vector_changed(value: Vector2)

@export var max_radius: float = 58.0
@export var deadzone: float = 0.12

@onready var knob: Control = $Knob

var active_touch_id: int = -1
var dragging_with_mouse: bool = false
var output_vector: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_recenter_knob()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_recenter_knob")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		var local_position := _to_local_position(touch_event.position)
		if touch_event.pressed and active_touch_id == -1 and _is_inside_joystick(local_position):
			active_touch_id = touch_event.index
			_update_output(local_position)
			accept_event()
			return
		if not touch_event.pressed and touch_event.index == active_touch_id:
			_reset_output()
			accept_event()
			return

	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == active_touch_id:
			_update_output(_to_local_position(drag_event.position))
			accept_event()
			return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		var mouse_position := _to_local_position(mouse_button.position)
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed and _is_inside_joystick(mouse_position):
				dragging_with_mouse = true
				_update_output(mouse_position)
				accept_event()
				return
			if not mouse_button.pressed and dragging_with_mouse:
				dragging_with_mouse = false
				_reset_output()
				accept_event()
				return

	if event is InputEventMouseMotion and dragging_with_mouse:
		var mouse_motion := event as InputEventMouseMotion
		_update_output(_to_local_position(mouse_motion.position))
		accept_event()

func _to_local_position(screen_position: Vector2) -> Vector2:
	return screen_position - get_global_rect().position

func _is_inside_joystick(local_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local_position)

func _update_output(local_position: Vector2) -> void:
	var center := size * 0.5
	var offset := local_position - center
	var limited_offset := offset.limit_length(max_radius)
	var normalized := limited_offset / max_radius
	if normalized.length() < deadzone:
		normalized = Vector2.ZERO
	output_vector = normalized.limit_length()
	_update_knob()
	vector_changed.emit(output_vector)

func _reset_output() -> void:
	active_touch_id = -1
	output_vector = Vector2.ZERO
	_update_knob()
	vector_changed.emit(output_vector)

func _recenter_knob() -> void:
	_update_knob()

func _update_knob() -> void:
	var center := size * 0.5
	knob.position = center - (knob.size * 0.5) + (output_vector * max_radius)
