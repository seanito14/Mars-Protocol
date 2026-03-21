class_name RoverAgent
extends CharacterBody3D

enum State { IDLE, NAVIGATING, SAMPLING }

const SPEED: float = 8.0
const ARRIVAL_DISTANCE: float = 2.0
const MOVE_ACCELERATION: float = 18.0
const MOVE_DECELERATION: float = 16.0
var current_state: State = State.IDLE
var sampling_timer: float = 0.0
var target_position: Vector3 = Vector3.ZERO
var has_target: bool = false
var ground_clearance: float = 2.2

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	add_to_group("interactable")
	EventBus.player_command_received.connect(_on_command_received)
	ground_clearance = _get_ground_clearance()

func _physics_process(delta: float) -> void:
	global_position.y = _get_ground_height()
	velocity.y = 0.0

	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	match current_state:
		State.IDLE:
			horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, MOVE_DECELERATION * delta)
		State.NAVIGATING:
			if not has_target:
				_start_sampling()
			else:
				var planar_position := Vector2(global_position.x, global_position.z)
				var planar_target := Vector2(target_position.x, target_position.z)
				if planar_position.distance_to(planar_target) <= ARRIVAL_DISTANCE:
					_start_sampling()
				else:
					var next_pos := _get_navigation_target()
					var desired_direction := Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z).normalized()
					var desired_velocity := desired_direction * SPEED
					horizontal_velocity = horizontal_velocity.move_toward(desired_velocity, MOVE_ACCELERATION * delta)
					if horizontal_velocity.length() > 0.1:
						look_at(global_position + Vector3(horizontal_velocity.x, 0, horizontal_velocity.y), Vector3.UP)
		State.SAMPLING:
			horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, MOVE_DECELERATION * delta)
			sampling_timer -= delta
			if sampling_timer <= 0:
				EventBus.push_mission_log("Rover completed the sample cycle and is ready for a new assignment.")
				current_state = State.IDLE

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
	move_and_slide()
	global_position.y = _get_ground_height()
	velocity.y = 0.0

func _start_sampling() -> void:
	EventBus.push_mission_log("Rover arrived on station and started XOSS geological sampling.")
	current_state = State.SAMPLING
	sampling_timer = 5.0
	has_target = false

func _get_navigation_target() -> Vector3:
	return target_position

func _get_ground_height() -> float:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_ground_height"):
		return float(current_scene.call("get_ground_height", global_position.x, global_position.z)) + ground_clearance
	return global_position.y

func _get_ground_clearance() -> float:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return ground_clearance

	var shape := collision_shape.shape
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		return (capsule_shape.height * 0.5) + capsule_shape.radius + 0.2
	return ground_clearance

func _on_command_received(command: String, params: Dictionary) -> void:
	if command == "deploy_rover":
		var x: float = float(params.get("x", 0))
		var z: float = float(params.get("z", 0))
		target_position = Vector3(x, global_position.y, z)
		nav_agent.target_position = target_position
		has_target = true
		current_state = State.NAVIGATING
		EventBus.push_mission_log("Rover redeployed to %.1f, %.1f." % [x, z])

func get_interaction_name() -> String:
	return "XOSS Rover"

func get_interaction_prompt() -> String:
	return "Tap INTERACT or press E to top up oxygen and suit power."

func get_focus_position() -> Vector3:
	return global_position + Vector3.UP * 1.0

func interact(player: Node) -> void:
	if player != null and player.has_method("restore_oxygen"):
		player.call("restore_oxygen", 28.0)
	if player != null and player.has_method("restore_suit_power"):
		player.call("restore_suit_power", 32.0)
	if player != null and player.has_method("restore_temperature_resistance"):
		player.call("restore_temperature_resistance", 10.0)
	EventBus.push_mission_log("Rover hatch opened. Oxygen and suit power refilled from onboard reserves.")
