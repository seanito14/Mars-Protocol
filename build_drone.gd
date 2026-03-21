extends SceneTree

func _init():
	var drone = CharacterBody3D.new()
	drone.name = "ScoutDrone"
	
	# Attach the script
	var script = load("res://scripts/drone.gd")
	if script:
		drone.set_script(script)
	
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.5, 0.5, 1.5)
	col.shape = shape
	drone.add_child(col)
	col.owner = drone
	
	# Procedural "Nanite-like" Micro-Detail Normal Map
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.05
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.as_normal_map = true
	noise_tex.bump_strength = 2.0
	
	# High-Fidelity Metallic Hull Material
	var mat_body = StandardMaterial3D.new()
	mat_body.albedo_color = Color(0.8, 0.8, 0.85)
	mat_body.metallic = 1.0
	mat_body.roughness = 0.25
	mat_body.normal_enabled = true
	mat_body.normal_texture = noise_tex
	mat_body.uv1_scale = Vector3(3, 3, 3)
	
	# Carbon Fiber / Dark Metal Material
	var mat_dark = StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.1, 0.1, 0.15)
	mat_dark.metallic = 0.8
	mat_dark.roughness = 0.4
	
	# Glowing Optics Material
	var mat_lens = StandardMaterial3D.new()
	mat_lens.albedo_color = Color(1.0, 0.2, 0.0)
	mat_lens.emission_enabled = true
	mat_lens.emission = Color(1.0, 0.2, 0.0)
	mat_lens.emission_energy_multiplier = 8.0
	
	# Core Body
	var core = MeshInstance3D.new()
	core.name = "Core"
	var core_mesh = CapsuleMesh.new()
	core_mesh.radius = 0.35
	core_mesh.height = 1.0
	core_mesh.material = mat_body
	core.mesh = core_mesh
	core.rotation.x = PI/2
	drone.add_child(core)
	core.owner = drone
	
	# Camera Optic
	var cam = MeshInstance3D.new()
	cam.name = "CameraLens"
	var cam_mesh = SphereMesh.new()
	cam_mesh.radius = 0.18
	cam_mesh.height = 0.36
	cam_mesh.material = mat_lens
	cam.mesh = cam_mesh
	cam.position = Vector3(0, -0.2, 0.4)
	drone.add_child(cam)
	cam.owner = drone
	
	# Rotors Parent
	var rotors_node = Node3D.new()
	rotors_node.name = "Rotors"
	drone.add_child(rotors_node)
	rotors_node.owner = drone
	
	var dist = 0.6
	var arm_positions = [
		Vector3(dist, 0, dist), Vector3(-dist, 0, dist),
		Vector3(dist, 0, -dist), Vector3(-dist, 0, -dist)
	]
	
	for i in range(4):
		# Arm
		var arm = MeshInstance3D.new()
		arm.name = "Arm" + str(i)
		var arm_mesh = BoxMesh.new()
		arm_mesh.size = Vector3(0.1, 0.05, dist * 1.5)
		arm_mesh.material = mat_dark
		arm.mesh = arm_mesh
		arm.position = arm_positions[i] / 2.0
		var look_target = arm.position * 2.0
		look_target.y = arm.position.y
		arm.look_at_from_position(arm.position, look_target, Vector3.UP)
		drone.add_child(arm)
		arm.owner = drone
		
		# Motor
		var motor = MeshInstance3D.new()
		motor.name = "Motor" + str(i)
		var motor_mesh = CylinderMesh.new()
		motor_mesh.top_radius = 0.1
		motor_mesh.bottom_radius = 0.1
		motor_mesh.height = 0.15
		motor_mesh.material = mat_dark
		motor.mesh = motor_mesh
		motor.position = arm_positions[i]
		drone.add_child(motor)
		motor.owner = drone
		
		# Spinning Rotor Blade
		var rotor = MeshInstance3D.new()
		rotor.name = "Rotor" + str(i)
		var rotor_mesh = BoxMesh.new()
		rotor_mesh.size = Vector3(0.8, 0.02, 0.06)
		rotor_mesh.material = mat_body
		rotor.mesh = rotor_mesh
		rotor.position = arm_positions[i] + Vector3(0, 0.1, 0)
		rotors_node.add_child(rotor)
		rotor.owner = drone

	# Save the generated high-fidelity scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(drone)
	ResourceSaver.save(packed_scene, "res://scenes/drone.tscn")
	print("High-fidelity Drone scene generated successfully.")
	quit()
