class_name HeroPlayer
extends CharacterBody3D

const WALK_SPEED: float = 4.8
const RUN_SPEED: float = 7.6
const MOVE_ACCELERATION: float = 24.0
const MOVE_DECELERATION: float = 20.0
const DEFAULT_MOUSE_SENSITIVITY: float = 0.0021
const JOY_SENSITIVITY: float = 0.055
const TOUCH_LOOK_SENSITIVITY: float = 0.022
const JOY_DEADZONE: float = 0.16
const COYOTE_TIME: float = 0.14
const JUMP_VELOCITY: float = 4.7
const INTERACT_RANGE: float = 8.0
const INTERACT_ALIGNMENT: float = 0.74
const WORLD_EDGE_PADDING: float = 5.0
const OXYGEN_DRAIN_IDLE: float = 0.0794
const OXYGEN_DRAIN_WALK: float = 0.1111
const OXYGEN_DRAIN_RUN: float = 0.1534
const SUIT_POWER_IDLE_DRAIN: float = 0.0324
const SUIT_POWER_WALK_DRAIN: float = 0.0556
const SUIT_POWER_RUN_DRAIN: float = 0.091
const TEMPERATURE_IDLE_DRAIN: float = 0.0218
const TEMPERATURE_WALK_DRAIN: float = 0.0333
const TEMPERATURE_RUN_DRAIN: float = 0.05
const BREATHING_FREQUENCY: float = 1.35
const BREATHING_VERTICAL_AMOUNT: float = 0.028
const BREATHING_ROLL_AMOUNT: float = 0.018
const HEAD_BOB_WALK_FREQUENCY: float = 7.4
const HEAD_BOB_RUN_FREQUENCY: float = 11.2
const HEAD_BOB_WALK_AMOUNT: float = 0.036
const HEAD_BOB_RUN_AMOUNT: float = 0.075
const CAMERA_ROLL_AMOUNT: float = 0.05
const TERRAIN_TILT_AMOUNT: float = 0.35
const MOTION_SMOOTHNESS: float = 9.0
const RUN_FOV_BOOST: float = 5.0
const SETTINGS_PATH := "user://settings.cfg"
const MIN_MOUSE_SENSITIVITY: float = 0.0008
const MAX_MOUSE_SENSITIVITY: float = 0.0055
const MIN_FOV: float = 60.0
const MAX_FOV: float = 100.0

@onready var breath_pivot: Node3D = $BreathPivot
@onready var tilt_pivot: Node3D = $BreathPivot/TiltPivot
@onready var pitch_pivot: Node3D = $BreathPivot/TiltPivot/PitchPivot
@onready var camera: Camera3D = $BreathPivot/TiltPivot/PitchPivot/Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var look_pitch: float = 0.0
var coyote_timer: float = 0.0
var joy_id: int = 0
var joy_jump_was_pressed: bool = false
var virtual_move_input: Vector2 = Vector2.ZERO
var virtual_look_input: Vector2 = Vector2.ZERO
var touch_look_delta: Vector2 = Vector2.ZERO
var base_camera_position: Vector3 = Vector3.ZERO
var base_camera_fov: float = 76.0
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var ground_clearance: float = 1.7
var oxygen: float = 100.0
var suit_power: float = 100.0
var temperature_resistance: float = 100.0
var heart_rate: float = 72.0
var breathing_phase: float = 0.0
var head_bob_time: float = 0.0
var storm_intensity: float = 0.0
var storm_bucket: int = -1
var focused_interactable: Node3D = null
var focused_prompt: String = ""
var focused_name: String = "Open Terrain"
var interact_was_pressed: bool = false
var active_waypoint_target: Node3D = null
var active_waypoint_label: String = ""
var scan_target_label: String = "Wreck Alpha"
var marvin_state: String = "STANDBY"
var marvin_message: String = "Sudo AI online. Move toward the wreckage and request a scan."
var last_transcript: String = ""
var sudo_ai_state: String = "OFFLINE"
var left_arm_root: Node3D
var left_hand_root: Node3D
var scanner_root: Node3D
var visor_glass_material: StandardMaterial3D
var scanner_screen_material: StandardMaterial3D
var storm_dust: GPUParticles3D

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var connected_joypads := Input.get_connected_joypads()
	if connected_joypads.size() > 0:
		joy_id = connected_joypads[0]
	ground_clearance = _get_ground_clearance()
	base_camera_position = camera.position
	base_camera_fov = camera.fov
	_apply_user_settings()
	_build_suit_rig()
	_build_storm_dust_particles()
	EventBus.transcript_received.connect(_on_transcript_received)
	EventBus.agent_response_received.connect(_on_agent_response_received)
	EventBus.conversation_connected.connect(_on_conversation_connected)
	EventBus.conversation_disconnected.connect(_on_conversation_disconnected)
	EventBus.scan_started.connect(_on_scan_started)
	EventBus.scan_completed.connect(_on_scan_completed)
	EventBus.sudo_ai_connected.connect(_on_sudo_ai_connected)
	EventBus.sudo_ai_disconnected.connect(_on_sudo_ai_disconnected)
	EventBus.sudo_ai_state_changed.connect(_on_sudo_ai_state_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var current_scene := get_tree().current_scene
		if current_scene != null:
			var hud := current_scene.get_node_or_null("CanvasLayer/HUD")
			if hud != null and hud.has_method("toggle_pause_menu"):
				hud.call("toggle_pause_menu")
				get_viewport().set_input_as_handled()
				return
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		rotate_y(-mouse_event.relative.x * mouse_sensitivity)
		look_pitch = clampf(look_pitch - (mouse_event.relative.y * mouse_sensitivity), -deg_to_rad(80.0), deg_to_rad(80.0))
		pitch_pivot.rotation.x = look_pitch
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_E:
			request_interaction()
		elif key_event.physical_keycode == KEY_T:
			request_scan()
		elif key_event.physical_keycode == KEY_F:
			_toggle_sudo_ai_activation()
		return

	if event is InputEventJoypadButton:
		var joypad_event := event as InputEventJoypadButton
		if joypad_event.pressed and joypad_event.button_index == JOY_BUTTON_X:
			_toggle_sudo_ai_activation()
			get_viewport().set_input_as_handled()

func _apply_user_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = clampf(
		float(config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)),
		MIN_MOUSE_SENSITIVITY,
		MAX_MOUSE_SENSITIVITY
	)
	var configured_fov := clampf(float(config.get_value("video", "fov", base_camera_fov)), MIN_FOV, MAX_FOV)
	base_camera_fov = configured_fov
	camera.fov = configured_fov

func _physics_process(delta: float) -> void:
	var ground_height := _get_ground_height()
	var is_grounded := global_position.y <= ground_height + 0.06 and velocity.y <= 0.0
	if not is_grounded:
		velocity.y -= gravity * delta
		coyote_timer -= delta
	else:
		global_position.y = ground_height
		velocity.y = 0.0
		coyote_timer = COYOTE_TIME

	var joy_jump_pressed := Input.is_joy_button_pressed(joy_id, JOY_BUTTON_A)
	var joy_jump_just_pressed := joy_jump_pressed and not joy_jump_was_pressed
	joy_jump_was_pressed = joy_jump_pressed
	if (Input.is_action_just_pressed("ui_accept") or joy_jump_just_pressed) and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0

	var look_input := _get_look_input()
	if look_input.length() > 0.001:
		rotate_y(-look_input.x)
		look_pitch = clampf(look_pitch - look_input.y, -deg_to_rad(80.0), deg_to_rad(80.0))
		pitch_pivot.rotation.x = look_pitch

	var input_dir := _get_move_input()
	var input_strength := clampf(input_dir.length(), 0.0, 1.0)
	var is_running := _wants_to_run(input_strength)
	var current_speed := RUN_SPEED if is_running else WALK_SPEED
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if direction != Vector3.ZERO:
		var target_velocity := Vector2(direction.x, direction.z) * current_speed * input_strength
		horizontal_velocity = horizontal_velocity.move_toward(target_velocity, MOVE_ACCELERATION * delta)
	else:
		horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, MOVE_DECELERATION * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
	move_and_slide()

	ground_height = _get_ground_height()
	if global_position.y < ground_height:
		global_position.y = ground_height
		velocity.y = 0.0

	_clamp_to_world()
	_enforce_ground_floor()
	_update_biostats(delta, input_strength, is_running)
	_update_interaction_focus()
	_handle_interaction_input()
	_update_presentation(delta, input_dir, is_grounded, is_running)
	_update_storm_dust()

func set_virtual_move_input(value: Vector2) -> void:
	virtual_move_input = value.limit_length()

func set_virtual_look_input(value: Vector2) -> void:
	virtual_look_input = value.limit_length()

func add_touch_look_delta(value: Vector2) -> void:
	touch_look_delta += value

func request_interaction() -> void:
	if focused_interactable != null and focused_interactable.has_method("interact"):
		focused_interactable.call("interact", self)
		_update_interaction_focus()

func request_scan() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("trigger_manual_scan"):
		scene.call("trigger_manual_scan", self)

func _toggle_sudo_ai_activation() -> void:
	if not SudoAIAgent:
		return
	if SudoAIAgent.hot_word_active:
		SudoAIAgent.deactivate_hot_word()
	else:
		SudoAIAgent.activate_hot_word()

func restore_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen + amount, 12.0, GameState.get_max_oxygen())

func restore_suit_power(amount: float) -> void:
	suit_power = clampf(suit_power + amount, 0.0, GameState.get_max_suit_power())

func restore_temperature_resistance(amount: float) -> void:
	temperature_resistance = clampf(
		temperature_resistance + amount,
		0.0,
		GameState.get_max_temperature_resistance()
	)

func set_waypoint_target(target: Node3D, label: String) -> void:
	active_waypoint_target = target
	active_waypoint_label = label
	if target != null:
		scan_target_label = label

func clear_waypoint_target() -> void:
	active_waypoint_target = null
	active_waypoint_label = ""

func set_marvin_state(state: String, message: String) -> void:
	marvin_state = state
	marvin_message = message

func get_status_snapshot() -> Dictionary:
	var waypoint_distance := -1.0
	if active_waypoint_target != null and is_instance_valid(active_waypoint_target):
		waypoint_distance = global_position.distance_to(active_waypoint_target.global_position)

	return {
		"oxygen": oxygen,
		"oxygen_max": GameState.get_max_oxygen(),
		"suit_power": suit_power,
		"suit_power_max": GameState.get_max_suit_power(),
		"temperature_resistance": temperature_resistance,
		"temperature_resistance_max": GameState.get_max_temperature_resistance(),
		"heart_rate": heart_rate,
		"waypoint_bearing_deg": _get_waypoint_bearing_deg(),
		"breathing_phase": breathing_phase,
		"storm_intensity": storm_intensity,
		"active_waypoint": active_waypoint_label,
		"scan_target_label": scan_target_label,
		"marvin_conversation_state": marvin_state,
		"marvin_message": marvin_message,
		"last_transcript": last_transcript,
		"focus_prompt": focused_prompt,
		"focus_name": focused_name,
		"heading_label": _get_heading_label(),
		"heading_degrees": _get_heading_degrees(),
		"elevation_m": _get_elevation_meters(),
		"coords": Vector2(global_position.x / 10.0, global_position.z / 10.0),
		"storm_eta_label": GameState.get_storm_eta_label(),
		"time_label": GameState.get_mission_clock_label(),
		"waypoint_distance": waypoint_distance,
	}

func _get_move_input() -> Vector2:
	var keyboard_input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		keyboard_input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		keyboard_input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		keyboard_input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		keyboard_input.y += 1.0
	if keyboard_input != Vector2.ZERO:
		keyboard_input = keyboard_input.normalized()

	var action_input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if action_input.length() > keyboard_input.length():
		keyboard_input = action_input

	var stick_input := Vector2(Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y))
	if stick_input.length() > JOY_DEADZONE:
		keyboard_input = stick_input.limit_length()

	if virtual_move_input.length() > keyboard_input.length():
		keyboard_input = virtual_move_input

	return keyboard_input

func _get_look_input() -> Vector2:
	var look_input := Vector2.ZERO
	var stick_input := Vector2(Input.get_joy_axis(joy_id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(joy_id, JOY_AXIS_RIGHT_Y))
	if stick_input.length() > JOY_DEADZONE:
		look_input += stick_input * JOY_SENSITIVITY
	if virtual_look_input.length() > 0.01:
		look_input += virtual_look_input * TOUCH_LOOK_SENSITIVITY
	if touch_look_delta.length() > 0.0:
		look_input += touch_look_delta * TOUCH_LOOK_SENSITIVITY * 0.08
		touch_look_delta = Vector2.ZERO
	return look_input

func _wants_to_run(input_strength: float) -> bool:
	if input_strength <= 0.01:
		return false
	if Input.is_physical_key_pressed(KEY_SHIFT):
		return true
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_LEFT_STICK):
		return true
	return virtual_move_input.length() > 0.9

func _update_biostats(delta: float, input_strength: float, is_running: bool) -> void:
	var oxygen_drain := OXYGEN_DRAIN_IDLE
	var suit_drain := SUIT_POWER_IDLE_DRAIN
	var temp_drain := TEMPERATURE_IDLE_DRAIN
	if input_strength > 0.04:
		oxygen_drain = OXYGEN_DRAIN_RUN if is_running else OXYGEN_DRAIN_WALK
		suit_drain = SUIT_POWER_RUN_DRAIN if is_running else SUIT_POWER_WALK_DRAIN
		temp_drain = TEMPERATURE_RUN_DRAIN if is_running else TEMPERATURE_WALK_DRAIN

	var suit_mult := GameState.get_suit_drain_multiplier()
	var temp_mult := suit_mult
	if GameState.storm_eta_seconds <= 0.0:
		temp_mult *= 15.0

	var o_max := GameState.get_max_oxygen()
	oxygen = clampf(oxygen - (oxygen_drain * delta), 12.0, o_max)
	suit_power = clampf(suit_power - (suit_drain * suit_mult * delta), 0.0, GameState.get_max_suit_power())
	temperature_resistance = clampf(
		temperature_resistance - (temp_drain * temp_mult * delta),
		0.0,
		GameState.get_max_temperature_resistance()
	)

	var effort: float = 0.18 + (input_strength * (0.5 if not is_running else 0.95))
	var oxygen_stress: float = 1.0 - (oxygen / maxf(o_max, 0.001))
	var thermal_stress: float = 1.0 - (temperature_resistance / maxf(GameState.get_max_temperature_resistance(), 0.001))
	var target_hr: float = 72.0 + (effort * 24.0) + (oxygen_stress * 16.0) + (thermal_stress * 10.0)
	heart_rate = lerpf(heart_rate, target_hr, delta * 1.4)

	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_storm_intensity"):
		storm_intensity = float(scene.call("get_storm_intensity", global_position, -camera.global_transform.basis.z))
		var bucket := int(floor(storm_intensity * 4.0))
		if bucket != storm_bucket:
			storm_bucket = bucket
			EventBus.storm_state_changed.emit(storm_intensity)

func _update_interaction_focus() -> void:
	var camera_position := camera.global_position
	var forward := -camera.global_transform.basis.z
	var best_score := -INF
	var best_candidate: Node3D = null
	for candidate_variant in get_tree().get_nodes_in_group("interactable"):
		var candidate := candidate_variant as Node3D
		if candidate == null:
			continue
		var focus_position := candidate.global_position
		if candidate.has_method("get_focus_position"):
			focus_position = candidate.call("get_focus_position")
		var to_target := focus_position - camera_position
		var distance := to_target.length()
		if distance > INTERACT_RANGE or distance <= 0.05:
			continue
		var alignment := forward.dot(to_target / distance)
		if alignment < INTERACT_ALIGNMENT:
			continue
		var score := (alignment * 12.0) - distance
		if score > best_score:
			best_score = score
			best_candidate = candidate

	focused_interactable = best_candidate
	if focused_interactable != null:
		focused_name = str(focused_interactable.call("get_interaction_name")) if focused_interactable.has_method("get_interaction_name") else focused_interactable.name
		focused_prompt = str(focused_interactable.call("get_interaction_prompt")) if focused_interactable.has_method("get_interaction_prompt") else ""
	else:
		focused_name = "Open Terrain"
		focused_prompt = "Walk the crater, inspect the wreckage, and talk to Sudo AI."

func _handle_interaction_input() -> void:
	var keyboard_interact := Input.is_physical_key_pressed(KEY_E)
	var joy_interact := Input.is_joy_button_pressed(joy_id, JOY_BUTTON_B)
	var interact_pressed := keyboard_interact or joy_interact
	if focused_interactable == null:
		interact_was_pressed = interact_pressed
		return
	if interact_pressed and not interact_was_pressed:
		request_interaction()
	interact_was_pressed = interact_pressed

func _update_presentation(delta: float, input_dir: Vector2, is_grounded: bool, is_running: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var move_strength := clampf(horizontal_speed / RUN_SPEED, 0.0, 1.0)
	var moving_on_ground := is_grounded and input_dir.length() > 0.01 and horizontal_speed > 0.1

	breathing_phase = fposmod(breathing_phase + (delta * BREATHING_FREQUENCY * (1.0 + (move_strength * 0.3))), 1.0)
	var breath_wave := sin(breathing_phase * TAU)

	var bob_amount := HEAD_BOB_RUN_AMOUNT if is_running else HEAD_BOB_WALK_AMOUNT
	var bob_frequency := HEAD_BOB_RUN_FREQUENCY if is_running else HEAD_BOB_WALK_FREQUENCY
	if moving_on_ground:
		head_bob_time += delta * bob_frequency * lerpf(0.65, 1.15, move_strength)
	else:
		head_bob_time = lerpf(head_bob_time, 0.0, delta * 4.0)

	var bob_offset := Vector3.ZERO
	if moving_on_ground:
		bob_offset.y = sin(head_bob_time) * bob_amount
		bob_offset.x = cos(head_bob_time * 0.5) * bob_amount * 0.48

	var breathing_offset := Vector3(0.0, breath_wave * BREATHING_VERTICAL_AMOUNT, 0.0)
	camera.position = camera.position.lerp(base_camera_position + breathing_offset + bob_offset, delta * MOTION_SMOOTHNESS)

	var ground_normal := _get_ground_normal()
	var local_normal := global_basis.inverse() * ground_normal
	var terrain_pitch := atan2(local_normal.z, local_normal.y) * TERRAIN_TILT_AMOUNT
	var terrain_roll := -atan2(local_normal.x, local_normal.y) * TERRAIN_TILT_AMOUNT
	var strafe_roll := -input_dir.x * CAMERA_ROLL_AMOUNT
	var breathing_roll := breath_wave * BREATHING_ROLL_AMOUNT
	var bob_roll := sin(head_bob_time * 0.5) * bob_amount * 0.18 if moving_on_ground else 0.0
	var target_tilt := Vector3(terrain_pitch + (breath_wave * 0.012), 0.0, terrain_roll + strafe_roll + breathing_roll + bob_roll)
	tilt_pivot.rotation = Vector3(
		lerp_angle(tilt_pivot.rotation.x, target_tilt.x, delta * MOTION_SMOOTHNESS),
		0.0,
		lerp_angle(tilt_pivot.rotation.z, target_tilt.z, delta * MOTION_SMOOTHNESS)
	)
	pitch_pivot.rotation.x = look_pitch
	camera.fov = lerpf(camera.fov, base_camera_fov + (RUN_FOV_BOOST * move_strength if is_running else 0.0), delta * MOTION_SMOOTHNESS)

	if left_arm_root != null:
		left_arm_root.position = Vector3(-0.46, -0.62 + (breath_wave * 0.02) + (bob_offset.y * 0.4), -0.76 + (move_strength * 0.02))
		left_arm_root.rotation = Vector3(-0.72 + (breath_wave * 0.024), 0.1 + (input_dir.x * 0.05), -0.32 + (breath_wave * 0.018))
	if left_hand_root != null:
		left_hand_root.rotation = Vector3(-0.2 + (sin(head_bob_time) * 0.08), 0.0, -0.1 - (breath_wave * 0.06))
	if scanner_root != null:
		scanner_root.position = Vector3(0.0, -0.72 + (breath_wave * 0.012), -0.92)
		scanner_root.rotation = Vector3(-0.12 + (breath_wave * 0.01), 0.0, 0.0)
	if scanner_screen_material != null:
		scanner_screen_material.emission_energy_multiplier = 1.3 + (storm_intensity * 1.1) + (move_strength * 0.4)
	if visor_glass_material != null:
		visor_glass_material.albedo_color.a = 0.025 + (storm_intensity * 0.035)

func _build_storm_dust_particles() -> void:
	storm_dust = GPUParticles3D.new()
	storm_dust.name = "StormDustParticles"
	camera.add_child(storm_dust)
	storm_dust.position = Vector3(0.0, 0.0, -2.4)
	storm_dust.amount = 240
	storm_dust.lifetime = 2.2
	storm_dust.explosiveness = 0.0
	storm_dust.randomness = 0.5
	storm_dust.visibility_aabb = AABB(Vector3(-32, -24, -18), Vector3(64, 48, 28))
	storm_dust.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	storm_dust.emitting = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 5.5, 1.4)
	pm.direction = Vector3(0.18, 0.08, 1.0)
	pm.spread = 0.75
	pm.initial_velocity_min = 0.9
	pm.initial_velocity_max = 4.2
	pm.angular_velocity_min = -0.8
	pm.angular_velocity_max = 0.8
	pm.gravity = Vector3(0.15, -0.05, 0.0)
	pm.scale_min = 0.07
	pm.scale_max = 0.24
	pm.color = Color(0.78, 0.48, 0.22, 0.55)
	storm_dust.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.38, 0.38)
	storm_dust.draw_pass_1 = quad

	var dust_mat := StandardMaterial3D.new()
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.albedo_color = Color(0.85, 0.52, 0.24, 0.48)
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	storm_dust.material_override = dust_mat

func _storm_screen_strength() -> float:
	if GameState.storm_eta_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - GameState.storm_eta_seconds / 300.0, 0.0, 1.0)

func _update_storm_dust() -> void:
	if storm_dust == null:
		return
	var s := _storm_screen_strength()
	storm_dust.emitting = s > 0.02
	storm_dust.speed_scale = lerpf(0.45, 1.45, s)

func _build_suit_rig() -> void:
	var suit_root := Node3D.new()
	suit_root.name = "SuitRig"
	camera.add_child(suit_root)

	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.04, 0.05, 0.06, 1.0)
	frame_material.roughness = 0.9
	frame_material.metallic = 0.3

	visor_glass_material = StandardMaterial3D.new()
	visor_glass_material.albedo_color = Color(0.1, 0.16, 0.18, 0.025)
	visor_glass_material.emission_enabled = true
	visor_glass_material.emission = Color(0.08, 0.2, 0.22, 1.0)
	visor_glass_material.emission_energy_multiplier = 0.08
	visor_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visor_glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	scanner_screen_material = StandardMaterial3D.new()
	scanner_screen_material.albedo_color = Color(0.04, 0.12, 0.16, 1.0)
	scanner_screen_material.emission_enabled = true
	scanner_screen_material.emission = Color(0.1, 0.88, 1.0, 1.0)
	scanner_screen_material.emission_energy_multiplier = 1.4
	scanner_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var suit_fabric_material := StandardMaterial3D.new()
	suit_fabric_material.albedo_color = Color(0.8, 0.78, 0.74, 1.0)
	suit_fabric_material.roughness = 0.98

	# The visor framing now lives in the 2D HUD overlay, so keep the
	# first-person rig lighter to avoid obscuring the scene.
	# The visor framing is now handled in the HUD overlay.

	scanner_root = Node3D.new()
	scanner_root.name = "ChestScanner"
	suit_root.add_child(scanner_root)
	scanner_root.position = Vector3(0.0, -0.72, -0.92)

	var scanner_body := _create_box_mesh(Vector3(0.48, 0.14, 0.18), frame_material)
	scanner_root.add_child(scanner_body)

	var scanner_screen := _create_box_mesh(Vector3(0.34, 0.05, 0.12), scanner_screen_material)
	scanner_screen.position = Vector3(0.0, 0.03, -0.05)
	scanner_root.add_child(scanner_screen)

	left_arm_root = Node3D.new()
	left_arm_root.name = "LeftArmRoot"
	suit_root.add_child(left_arm_root)
	left_arm_root.position = Vector3(-0.46, -0.62, -0.76)
	left_arm_root.rotation = Vector3(-0.72, 0.1, -0.32)

	var upper_arm := _create_capsule_mesh(0.072, 0.42, suit_fabric_material)
	upper_arm.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	left_arm_root.add_child(upper_arm)

	left_hand_root = Node3D.new()
	left_arm_root.add_child(left_hand_root)
	left_hand_root.position = Vector3(-0.28, -0.06, 0.0)

	var glove := _create_box_mesh(Vector3(0.18, 0.11, 0.16), suit_fabric_material)
	left_hand_root.add_child(glove)

	var wrist_plate := _create_box_mesh(Vector3(0.08, 0.09, 0.1), frame_material)
	wrist_plate.position = Vector3(0.1, 0.0, 0.0)
	left_hand_root.add_child(wrist_plate)

func _create_box_mesh(size_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance

func _create_capsule_mesh(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance

func _get_ground_height() -> float:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_ground_height"):
		return float(current_scene.call("get_ground_height", global_position.x, global_position.z)) + ground_clearance
	return global_position.y

func _get_ground_normal() -> Vector3:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_ground_normal"):
		return current_scene.call("get_ground_normal", global_position.x, global_position.z)
	return Vector3.UP

func _get_world_half_size() -> float:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_world_half_size"):
		return float(current_scene.call("get_world_half_size"))
	return 400.0

func _get_ground_clearance() -> float:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return ground_clearance

	var shape := collision_shape.shape
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		return (capsule_shape.height * 0.5) + capsule_shape.radius + 0.2
	return ground_clearance

func _clamp_to_world() -> void:
	var world_half_size := _get_world_half_size() - WORLD_EDGE_PADDING
	global_position.x = clampf(global_position.x, -world_half_size, world_half_size)
	global_position.z = clampf(global_position.z, -world_half_size, world_half_size)

func _enforce_ground_floor() -> void:
	var ground_height := _get_ground_height()
	if global_position.y < ground_height - 1.0:
		global_position.y = ground_height
		velocity.y = 0.0

func _get_waypoint_bearing_deg() -> float:
	if active_waypoint_target == null or not is_instance_valid(active_waypoint_target):
		return -1000.0
	var to_wp := active_waypoint_target.global_position - global_position
	var flat := Vector2(to_wp.x, to_wp.z)
	if flat.length_squared() < 0.01:
		return -1000.0
	flat = flat.normalized()
	var fwd := Vector2(-sin(rotation.y), -cos(rotation.y))
	return rad_to_deg(fwd.angle_to(flat))

func _get_heading_degrees() -> float:
	return fposmod(rad_to_deg(rotation.y), 360.0)

func _get_heading_label() -> String:
	var heading := _get_heading_degrees()
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var index := int(round(heading / 45.0)) % labels.size()
	return labels[index]

func _get_elevation_meters() -> float:
	var ground_height := _get_ground_height() - ground_clearance
	return (ground_height - 42.0) * 8.0

func _on_transcript_received(text: String) -> void:
	last_transcript = text
	marvin_state = "PROCESSING"

func _on_agent_response_received(text: String) -> void:
	marvin_state = "SUDO AI LINKED"
	marvin_message = text

func _on_conversation_connected(mode: String) -> void:
	marvin_state = "VOICE %s" % mode.to_upper()

func _on_conversation_disconnected(reason: String) -> void:
	marvin_state = reason.to_upper()

func _on_scan_started(target_name: String) -> void:
	scan_target_label = target_name
	marvin_state = "SCANNING"

func _on_scan_completed(target_name: String) -> void:
	scan_target_label = target_name
	marvin_state = "SCAN COMPLETE"

func _on_sudo_ai_connected() -> void:
	sudo_ai_state = "SUDO AI ONLINE"
	EventBus.push_mission_log("[SUDO AI] Connected to ElevenLabs agent.")

func _on_sudo_ai_disconnected(_reason: String) -> void:
	sudo_ai_state = "SUDO AI OFFLINE"

func _on_sudo_ai_state_changed(state_text: String) -> void:
	sudo_ai_state = "SUDO AI: %s" % state_text
