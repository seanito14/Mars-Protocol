class_name ScoutDrone
extends CharacterBody3D

const FOLLOW_SPEED: float = 10.0
const HOVER_HEIGHT: float = 12.0
const LERP_SMOOTHING: float = 2.0

var player: Node3D = null

@onready var rotors: Node3D = $Rotors

func _ready() -> void:
	# Look for the player in the group
	player = get_tree().get_first_node_in_group("player") as Node3D
	
	# Safely connect to EventBus if it exists
	if get_node_or_null("/root/EventBus"):
		EventBus.player_command_received.connect(_on_command)

func _physics_process(delta: float) -> void:
	# Spin the high-fidelity rotors
	if rotors:
		for rotor in rotors.get_children():
			rotor.rotate_y(30.0 * delta)
			
	if not player:
		player = get_tree().get_first_node_in_group("player") as Node3D
		if not player:
			return
	
	# Target position: In front, to the right, and slightly elevated so it's in view
	var forward_dir: Vector3 = -player.global_transform.basis.z
	var right_dir: Vector3 = player.global_transform.basis.x
	var target_pos: Vector3 = player.global_position + (forward_dir * 3.5) + (right_dir * 2.0) + Vector3(0, 2.5, 0)
	
	# Smoothly move toward target
	global_position = global_position.lerp(target_pos, LERP_SMOOTHING * delta)
	
	# Rotate to face player's forward direction
	var target_rotation: float = player.global_rotation.y
	global_rotation.y = lerp_angle(global_rotation.y, target_rotation, LERP_SMOOTHING * delta)
	
	# Tilt drone based on movement for realistic weight
	var tilt: float = (global_position.x - target_pos.x) * 0.1
	rotation.z = lerp(rotation.z, tilt, LERP_SMOOTHING * delta)

func _on_command(command: String, _params: Dictionary) -> void:
	if command == "scan_area":
		print("Drone: Initiating wide-spectrum high-resolution scan...")
