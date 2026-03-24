extends Node3D

const JEZERO_SCENE := preload("res://scenes/jezero_landing.tscn")
const FLYOVER_DURATION_SECONDS: float = 6.0

@onready var camera: Camera3D = $FlyoverCamera

var elapsed_time: float = 0.0
var landing_scene: Node3D = null

func _ready() -> void:
	landing_scene = JEZERO_SCENE.instantiate() as Node3D
	add_child(landing_scene)
	move_child(landing_scene, 0)
	_prepare_landing_scene()
	call_deferred("_activate_flyover_camera")

func _process(delta: float) -> void:
	elapsed_time = minf(elapsed_time + delta, FLYOVER_DURATION_SECONDS)
	_apply_camera_pose(elapsed_time / FLYOVER_DURATION_SECONDS)

func _prepare_landing_scene() -> void:
	var canvas_layer := landing_scene.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas_layer != null:
		canvas_layer.visible = false

	var player := landing_scene.get_node_or_null("Player") as Node3D
	if player != null:
		player.visible = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.set_process(false)
		player.set_physics_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)
		var player_camera := player.get_node_or_null("BreathPivot/TiltPivot/PitchPivot/Camera3D") as Camera3D
		if player_camera != null:
			player_camera.current = false

func _activate_flyover_camera() -> void:
	camera.current = true
	_apply_camera_pose(0.0)

func _apply_camera_pose(t: float) -> void:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	var eased_t: float = clamped_t * clamped_t * (3.0 - (2.0 * clamped_t))
	var start_position := Vector3(184.0, 32.0, 212.0)
	var mid_position := Vector3(86.0, 22.0, 142.0)
	var end_position := Vector3(-24.0, 18.0, 92.0)
	var focus_start := Vector3(46.0, 4.0, 88.0)
	var focus_mid := Vector3(8.0, 5.0, 94.0)
	var focus_end := Vector3(-18.0, 7.0, 104.0)
	var camera_position := _sample_curve(start_position, mid_position, end_position, eased_t)
	camera_position.y += sin(eased_t * PI) * 3.5
	var focus_point := _sample_curve(focus_start, focus_mid, focus_end, eased_t)
	camera.fov = lerpf(52.0, 46.0, eased_t)
	camera.global_position = camera_position
	camera.look_at(focus_point, Vector3.UP)

func _sample_curve(start_point: Vector3, mid_point: Vector3, end_point: Vector3, t: float) -> Vector3:
	if t <= 0.5:
		return start_point.lerp(mid_point, t / 0.5)
	return mid_point.lerp(end_point, (t - 0.5) / 0.5)
