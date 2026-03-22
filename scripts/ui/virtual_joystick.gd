extends Control

signal vector_changed(value: Vector2)

@export var max_radius: float = 58.0
@export var deadzone: float = 0.12

@onready var knob: Control = $Knob
@onready var player: Node = get_tree().get_first_node_in_group("player")

var active_touch_id: int = -1
var dragging_with_mouse: bool = false
var output_vector: Vector2 = Vector2.ZERO

func _ready() -> void:
	# No need to block mouse, we use _input directly.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recenter_knob()
	if player == null:
		# Fallback if group is not set, find it in the current scene
		var root = get_tree().current_scene
		if root:
			player = root.get_node_or_null("Player")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_recenter_knob")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and active_touch_id == -1 and _is_inside_joystick(touch_event.position):
			active_touch_id = touch_event.index
			_update_output(touch_event.position)
			get_viewport().set_input_as_handled()
			return
		elif not touch_event.pressed and touch_event.index == active_touch_id:
			_reset_output()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == active_touch_id:
			_update_output(drag_event.position)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed and _is_inside_joystick(mouse_button.position):
				dragging_with_mouse = true
				_update_output(mouse_button.position)
				get_viewport().set_input_as_handled()
				return
			elif not mouse_button.pressed and dragging_with_mouse:
				dragging_with_mouse = false
				_reset_output()
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion and dragging_with_mouse:
		var mouse_motion := event as InputEventMouseMotion
		_update_output(mouse_motion.position)
		get_viewport().set_input_as_handled()

func _is_inside_joystick(global_pos: Vector2) -> bool:
	return get_global_rect().has_point(global_pos)

func _update_output(global_pos: Vector2) -> void:
	var global_center := get_global_rect().get_center()
	var offset := global_pos - global_center
	var limited_offset := offset.limit_length(max_radius)
	var normalized := limited_offset / max_radius
	
	if normalized.length() < deadzone:
		normalized = Vector2.ZERO
		
	output_vector = normalized.limit_length()
	_update_knob()
	vector_changed.emit(output_vector)
	
	if player and player.has_method("set_virtual_move_input"):
		player.set_virtual_move_input(output_vector)

func _reset_output() -> void:
	active_touch_id = -1
	dragging_with_mouse = false
	output_vector = Vector2.ZERO
	_update_knob()
	vector_changed.emit(output_vector)
	
	if player and player.has_method("set_virtual_move_input"):
		player.set_virtual_move_input(output_vector)

func _recenter_knob() -> void:
	_update_knob()

func _update_knob() -> void:
	var local_center := size * 0.5
	if knob:
		# Need to position it relative to the joystick's top-left
		# The knob's coordinates are local to the joystick Base
		knob.position = local_center - (knob.size * 0.5) + (output_vector * max_radius)
