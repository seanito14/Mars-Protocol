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
	_build_rover_geometry()
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
		return 1.2

	var shape := collision_shape.shape
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		return (capsule_shape.height * 0.5) + capsule_shape.radius + 0.2
	if shape is BoxShape3D:
		return (shape.size.y * 0.5) + collision_shape.position.y
	return 1.2

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

# --- Procedural Geometry Generation ---

func _build_rover_geometry() -> void:
	var root := Node3D.new()
	root.name = "RoverVisuals"
	add_child(root)

	# 1. Collision Shape
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2.6, 2.0, 3.2)
	collision.shape = box_shape
	collision.position = Vector3(0.0, 1.2, 0.0)
	add_child(collision)

	# 2. Materials
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.93, 0.93, 0.95, 1.0)
	body_mat.metallic = 0.28
	body_mat.roughness = 0.54

	var component_mat := StandardMaterial3D.new()
	component_mat.albedo_color = Color(0.22, 0.24, 0.28, 1.0)
	component_mat.metallic = 0.72
	component_mat.roughness = 0.36

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.12, 0.13, 0.15, 1.0)
	wheel_mat.metallic = 0.86
	wheel_mat.roughness = 0.46

	var gold_foil_mat := StandardMaterial3D.new()
	gold_foil_mat.albedo_color = Color(0.66, 0.62, 0.48, 1.0)
	gold_foil_mat.metallic = 0.7
	gold_foil_mat.roughness = 0.42
	gold_foil_mat.clearcoat_enabled = true
	
	var mmrtg_mat := StandardMaterial3D.new()
	mmrtg_mat.albedo_color = Color(0.08, 0.08, 0.09, 1.0)
	mmrtg_mat.metallic = 0.9
	mmrtg_mat.roughness = 0.5
	
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.02, 0.05, 0.1, 0.9)
	glass_mat.metallic = 0.8
	glass_mat.roughness = 0.1
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.1, 0.5, 0.6, 1.0)
	glass_mat.emission_energy_multiplier = 0.8

	# 3. Main Body (Warm Electronics Box)
	var main_body := _create_box(Vector3(1.8, 0.6, 2.2), body_mat)
	main_body.position = Vector3(0.0, 1.4, 0.0)
	root.add_child(main_body)

	var equipment_deck := _create_box(Vector3(1.6, 0.15, 2.0), component_mat)
	equipment_deck.position = Vector3(0.0, 1.775, 0.0)
	root.add_child(equipment_deck)
	
	var belly_pan := _create_box(Vector3(1.7, 0.2, 2.1), gold_foil_mat)
	belly_pan.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(belly_pan)

	# 4. Rocker-Bogie Suspension & Wheels
	var wheel_radius := 0.42
	var wheel_width := 0.4
	var track_width := 1.2
	var wheel_dist_z := 1.1

	var positions_z := [wheel_dist_z, 0.0, -wheel_dist_z]
	for side in [-1, 1]:
		# Main rocker arm
		var rocker := _create_cylinder(0.06, 2.4, component_mat)
		rocker.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
		rocker.position = Vector3(side * (track_width - 0.15), 1.0, 0.0)
		root.add_child(rocker)
		
		# Bogie arm (rear)
		var bogie := _create_cylinder(0.05, 1.4, component_mat)
		bogie.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
		bogie.position = Vector3(side * (track_width - 0.25), 0.7, -0.5)
		bogie.rotation.x = deg_to_rad(75.0)
		root.add_child(bogie)

		for i in range(3):
			# Wheel
			var wheel := _create_cylinder(wheel_radius, wheel_width, wheel_mat)
			wheel.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
			wheel.position = Vector3(side * track_width, wheel_radius, positions_z[i])
			root.add_child(wheel)

			# Suspension strut down to wheel
			var strut := _create_cylinder(0.04, 0.8, component_mat)
			strut.position = Vector3(side * (track_width - 0.1), 0.6 + (wheel_radius * 0.5), positions_z[i])
			root.add_child(strut)

	# 5. Remote Sensing Mast (RSM)
	var mast_root := Node3D.new()
	mast_root.position = Vector3(0.7, 1.7, 0.8)
	root.add_child(mast_root)
	
	var mast_pole := _create_cylinder(0.05, 1.1, component_mat)
	mast_pole.position = Vector3(0.0, 0.55, 0.0)
	mast_root.add_child(mast_pole)

	var mast_head := _create_box(Vector3(0.4, 0.25, 0.25), body_mat)
	mast_head.position = Vector3(0.0, 1.2, 0.0)
	mast_root.add_child(mast_head)

	var eye_left := _create_cylinder(0.04, 0.06, glass_mat)
	eye_left.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	eye_left.position = Vector3(0.1, 1.2, 0.13)
	mast_root.add_child(eye_left)

	var eye_right := _create_cylinder(0.04, 0.06, glass_mat)
	eye_right.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	eye_right.position = Vector3(-0.1, 1.2, 0.13)
	mast_root.add_child(eye_right)

	# 6. MMRTG (Radioisotope Thermoelectric Generator) - Back
	var mmrtg := _create_cylinder(0.25, 0.7, mmrtg_mat)
	mmrtg.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	mmrtg.position = Vector3(0.0, 1.3, -1.35)
	root.add_child(mmrtg)
	
	# MMRTG Fins
	for i in range(5):
		var fin := _create_box(Vector3(0.6, 0.6, 0.02), component_mat)
		fin.position = Vector3(0.0, 1.3, -1.1 - (i * 0.12))
		root.add_child(fin)

	# 7. Robotic Arm - Front
	var arm_base := _create_cylinder(0.08, 0.3, component_mat)
	arm_base.position = Vector3(0.0, 1.3, 1.2)
	root.add_child(arm_base)

	var arm_segment1 := _create_cylinder(0.06, 0.8, body_mat)
	arm_segment1.rotation = Vector3(deg_to_rad(-45.0), 0.0, 0.0)
	arm_segment1.position = Vector3(0.0, 1.0, 1.5)
	root.add_child(arm_segment1)
	
	var arm_segment2 := _create_cylinder(0.05, 0.7, body_mat)
	arm_segment2.rotation = Vector3(deg_to_rad(20.0), 0.0, 0.0)
	arm_segment2.position = Vector3(0.0, 0.85, 1.9)
	root.add_child(arm_segment2)

	var turret := _create_box(Vector3(0.35, 0.35, 0.45), component_mat)
	turret.position = Vector3(0.0, 0.7, 2.2)
	root.add_child(turret)
	
	var drill_bit := _create_cylinder(0.04, 0.4, component_mat)
	drill_bit.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	drill_bit.position = Vector3(0.0, 0.7, 2.5)
	root.add_child(drill_bit)

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh_inst.mesh = box
	return mesh_inst

func _create_cylinder(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = mat
	mesh_inst.mesh = cyl
	return mesh_inst
