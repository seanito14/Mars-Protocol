class_name Player
extends CharacterBody3D

const MAX_HEALTH: float = 100.0
const WALK_SPEED: float = 5.5
const RUN_SPEED: float = 10.5
const JUMP_VELOCITY: float = 5.4
const MOUSE_SENSITIVITY: float = 0.002
const JOY_SENSITIVITY: float = 0.05
const TOUCH_LOOK_SENSITIVITY: float = 1.9
const JOY_DEADZONE: float = 0.15
const COYOTE_TIME: float = 0.15
const MOVE_ACCELERATION: float = 30.0
const MOVE_DECELERATION: float = 26.0
const HEAD_BOB_WALK_FREQUENCY: float = 8.0
const HEAD_BOB_RUN_FREQUENCY: float = 12.5
const HEAD_BOB_WALK_AMOUNT: float = 0.05
const HEAD_BOB_RUN_AMOUNT: float = 0.1
const CAMERA_ROLL_AMOUNT: float = 0.04
const TERRAIN_TILT_AMOUNT: float = 0.45
const TILT_SMOOTHNESS: float = 10.0
const FOV_SMOOTHNESS: float = 8.0
const RUN_FOV_BOOST: float = 7.0
const INTERACT_RANGE: float = 7.5
const INTERACT_ALIGNMENT: float = 0.72
const WORLD_EDGE_PADDING: float = 6.0
const OXYGEN_IDLE_DRAIN: float = 0.0794
const OXYGEN_WALK_DRAIN: float = 0.1111
const OXYGEN_RUN_DRAIN: float = 0.1534
const SUIT_POWER_IDLE_DRAIN: float = 0.0324
const SUIT_POWER_WALK_DRAIN: float = 0.0556
const SUIT_POWER_RUN_DRAIN: float = 0.0910
const TEMPERATURE_IDLE_DRAIN: float = 0.0218
const TEMPERATURE_WALK_DRAIN: float = 0.0333
const TEMPERATURE_RUN_DRAIN: float = 0.0500
const LOW_RESOURCE_THRESHOLD: float = 25.0
const LOW_RESOURCE_RESET_THRESHOLD: float = 35.0
const TELEMETRY_SCAN_COST: float = 9.0
const TELEMETRY_DURATION: float = 7.0
const DRONE_SCAN_DURATION: float = 6.0
const FAILURE_DURATION: float = 2.5

@onready var tilt_pivot: Node3D = $TiltPivot
@onready var pitch_pivot: Node3D = $TiltPivot/PitchPivot
@onready var camera: Camera3D = $TiltPivot/PitchPivot/Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var coyote_timer: float = 0.0
var joy_id: int = 0
var joy_jump_was_pressed: bool = false
var ground_clearance: float = 1.7
var look_pitch: float = 0.0
var head_bob_time: float = 0.0
var base_camera_position: Vector3 = Vector3.ZERO
var base_camera_fov: float = 80.0
var virtual_move_input: Vector2 = Vector2.ZERO
var virtual_look_input: Vector2 = Vector2.ZERO
var health: float = MAX_HEALTH
var oxygen: float = 100.0
var suit_power: float = 100.0
var temperature_resistance: float = 100.0
var heart_rate: float = 72.0
var external_temperature: float = -63.0
var drone_scans: int = 0
var surveyed_rocks: int = 0
var focused_interactable: Node3D = null
var focused_prompt: String = ""
var focused_name: String = ""
var interact_was_pressed: bool = false
var telemetry_target_position: Vector3 = Vector3.ZERO
var telemetry_target_name: String = ""
var telemetry_timer: float = 0.0
var failure_timer: float = 0.0
var is_failed: bool = false
var low_resource_ready := {
	"oxygen": true,
	"suit_power": true,
	"temperature_resistance": true,
}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var connected_joypads := Input.get_connected_joypads()
	if connected_joypads.size() > 0:
		joy_id = connected_joypads[0]
	ground_clearance = _get_ground_clearance()
	base_camera_position = camera.position
	base_camera_fov = camera.fov
	_restore_full_suit()
	EventBus.push_mission_log("Commander online. EVA suit synced to basecamp survival protocols.")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameState.is_paywall_visible():
			MonetizationService.hide_paywall()
			return
		if GameState.is_basecamp_terminal_open():
			GameState.close_basecamp_terminal()
			return
		if not is_failed:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if is_failed:
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_T or key_event.keycode == KEY_T:
			if not GameState.is_modal_open():
				request_telemetry_scan()
			return

	if GameState.is_modal_open():
		return

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		rotate_y(-mouse_event.relative.x * MOUSE_SENSITIVITY)
		look_pitch = clampf(look_pitch - mouse_event.relative.y * MOUSE_SENSITIVITY, -deg_to_rad(80), deg_to_rad(80))
		pitch_pivot.rotation.x = look_pitch

func _physics_process(delta: float) -> void:
	_update_mouse_mode_for_ui()
	_update_telemetry_timer(delta)

	if is_failed:
		failure_timer -= delta
		velocity = Vector3.ZERO
		if failure_timer <= 0.0:
			get_tree().change_scene_to_file("res://scenes/game_over.tscn")
		return

	var ground_height := _get_ground_height()
	var is_grounded := global_position.y <= ground_height + 0.06 and velocity.y <= 0.0
	if not is_grounded:
		velocity.y -= gravity * delta
		coyote_timer -= delta
	else:
		global_position.y = ground_height
		velocity.y = 0.0
		coyote_timer = COYOTE_TIME

	var input_locked := GameState.is_modal_open()

	if not input_locked:
		var joy_jump_pressed := Input.is_joy_button_pressed(joy_id, JOY_BUTTON_A)
		var joy_jump_just_pressed := joy_jump_pressed and not joy_jump_was_pressed
		joy_jump_was_pressed = joy_jump_pressed
		if (Input.is_action_just_pressed("ui_accept") or joy_jump_just_pressed) and coyote_timer > 0.0:
			velocity.y = JUMP_VELOCITY
			coyote_timer = 0.0
	else:
		joy_jump_was_pressed = false

	var look_input := Vector2.ZERO if input_locked else _get_look_input()
	if look_input.length() > 0.001:
		rotate_y(-look_input.x)
		look_pitch = clampf(look_pitch - look_input.y, -deg_to_rad(80), deg_to_rad(80))
		pitch_pivot.rotation.x = look_pitch

	var input_dir := Vector2.ZERO if input_locked else _get_move_input()
	var input_strength := clampf(input_dir.length(), 0.0, 1.0)
	var is_running := not input_locked and _wants_to_run(input_strength)
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
	_update_status(delta, input_strength, is_running)
	_update_interaction_focus()
	if not input_locked:
		_handle_interaction_input()
	else:
		interact_was_pressed = false
	_update_motion_feedback(delta, input_dir, is_grounded, is_running)

func set_virtual_move_input(value: Vector2) -> void:
	virtual_move_input = value.limit_length()

func set_virtual_look_input(value: Vector2) -> void:
	virtual_look_input = value.limit_length()

func request_interaction() -> void:
	if is_failed or GameState.is_modal_open():
		return
	if focused_interactable != null and focused_interactable.has_method("interact"):
		focused_interactable.call("interact", self)
		_update_interaction_focus()

func request_telemetry_scan() -> void:
	if is_failed or GameState.is_modal_open():
		return
	EventBus.telemetry_requested.emit("manual")
	EventBus.push_mission_log("Scanning for high-tier debris...")
	if not MonetizationService.has_entitlement("pro"):
		MonetizationService.show_paywall("telemetry")
		return
	if suit_power < TELEMETRY_SCAN_COST:
		EventBus.push_mission_log("Telemetry aborted. Suit power reserves are too low.")
		return

	suit_power = max(suit_power - TELEMETRY_SCAN_COST, 0.0)
	if not _activate_telemetry_target(TELEMETRY_DURATION, "Telemetry beacon locked onto a debris signature."):
		EventBus.push_mission_log("Telemetry sweep complete. No additional debris signatures detected.")

func register_drone_scan() -> void:
	drone_scans += 1
	restore_temperature_resistance(8.0)
	EventBus.push_mission_log("Scout drone mapped a new debris corridor.")
	if not _activate_telemetry_target(DRONE_SCAN_DURATION, "Drone uplink marked a debris trail ahead."):
		EventBus.push_mission_log("Drone sweep complete. No fresh debris traces found.")

func catalog_rock_sample(sample_name: String) -> void:
	var _sample := sample_name
	surveyed_rocks += 1
	restore_temperature_resistance(2.5)

func restore_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen + amount, 0.0, GameState.get_max_oxygen())

func restore_suit_power(amount: float) -> void:
	suit_power = clampf(suit_power + amount, 0.0, GameState.get_max_suit_power())

func restore_temperature_resistance(amount: float) -> void:
	temperature_resistance = clampf(temperature_resistance + amount, 0.0, GameState.get_max_temperature_resistance())

func restore_health(amount: float) -> void:
	health = clampf(health + amount, 0.0, MAX_HEALTH)

func apply_upgrade_purchase(upgrade_id: String) -> void:
	if upgrade_id == "oxygen_capacity":
		restore_oxygen(GameState.OXYGEN_CAPACITY_BONUS_PER_LEVEL)
	if upgrade_id == "suit_durability":
		restore_suit_power(8.0)
		restore_temperature_resistance(8.0)

func get_status_snapshot() -> Dictionary:
	var telemetry_target: Variant = null
	if telemetry_timer > 0.0:
		telemetry_target = {
			"name": telemetry_target_name,
			"coords": Vector2(telemetry_target_position.x / 10.0, telemetry_target_position.z / 10.0),
		}

	var waypoint_data := _get_waypoint_data()

	return {
		"health": health,
		"oxygen": oxygen,
		"oxygen_max": GameState.get_max_oxygen(),
		"suit_power": suit_power,
		"suit_power_max": GameState.get_max_suit_power(),
		"temperature_resistance": temperature_resistance,
		"temperature_resistance_max": GameState.get_max_temperature_resistance(),
		"salvage_cubes": GameState.get_salvage_cubes(),
		"upgrade_levels": GameState.get_upgrade_levels(),
		"is_failed": is_failed,
		"telemetry_target": telemetry_target,
		"focus_name": focused_name,
		"focus_prompt": focused_prompt,
		"coords": Vector2(global_position.x / 10.0, global_position.z / 10.0),
		"scans": drone_scans,
		"rocks": surveyed_rocks,
		"heart_rate": heart_rate,
		"external_temperature": external_temperature,
		"heading_label": _get_heading_label(),
		"heading_degrees": _get_heading_degrees(),
		"waypoint_name": waypoint_data["name"],
		"waypoint_distance": waypoint_data["distance"],
		"elevation_m": _get_elevation_meters(),
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
		look_input += virtual_look_input * TOUCH_LOOK_SENSITIVITY * 0.02

	return look_input

func _wants_to_run(input_strength: float) -> bool:
	if input_strength <= 0.01:
		return false
	if Input.is_physical_key_pressed(KEY_SHIFT):
		return true
	if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_LEFT_STICK):
		return true
	return virtual_move_input.length() > 0.88

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
	return 500.0

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

func _update_status(delta: float, input_strength: float, is_running: bool) -> void:
	var oxygen_drain := OXYGEN_IDLE_DRAIN
	var suit_power_drain := SUIT_POWER_IDLE_DRAIN
	var temperature_drain := TEMPERATURE_IDLE_DRAIN
	if input_strength > 0.05:
		oxygen_drain = OXYGEN_RUN_DRAIN if is_running else OXYGEN_WALK_DRAIN
		suit_power_drain = SUIT_POWER_RUN_DRAIN if is_running else SUIT_POWER_WALK_DRAIN
		temperature_drain = TEMPERATURE_RUN_DRAIN if is_running else TEMPERATURE_WALK_DRAIN

	var suit_drain_multiplier := GameState.get_suit_drain_multiplier()
	var temp_drain_multiplier := suit_drain_multiplier
	if GameState.storm_eta_seconds <= 0.0:
		temp_drain_multiplier *= 15.0

	oxygen = clampf(oxygen - (oxygen_drain * delta), 0.0, GameState.get_max_oxygen())
	suit_power = clampf(suit_power - (suit_power_drain * suit_drain_multiplier * delta), 0.0, GameState.get_max_suit_power())
	temperature_resistance = clampf(temperature_resistance - (temperature_drain * temp_drain_multiplier * delta), 0.0, GameState.get_max_temperature_resistance())

	if suit_power <= 0.0:
		health = clampf(health - (3.8 * delta), 0.0, MAX_HEALTH)
	if temperature_resistance <= 0.0:
		health = clampf(health - (5.2 * delta), 0.0, MAX_HEALTH)
	elif health < MAX_HEALTH:
		health = clampf(health + (0.6 * delta), 0.0, MAX_HEALTH)

	var effort: float = 0.18 + (input_strength * (0.5 if not is_running else 0.95))
	var oxygen_stress: float = 1.0 - (oxygen / max(GameState.get_max_oxygen(), 0.001))
	var thermal_stress: float = 1.0 - (temperature_resistance / max(GameState.get_max_temperature_resistance(), 0.001))
	var target_heart_rate: float = 72.0 + (effort * 24.0) + (oxygen_stress * 16.0) + (thermal_stress * 10.0)
	heart_rate = lerpf(heart_rate, target_heart_rate, delta * 1.4)

	var temperature_target: float = -63.0 - (oxygen_stress * 1.5) - (thermal_stress * 3.6) + (sin(Time.get_ticks_msec() * 0.0004) * 0.6)
	external_temperature = lerpf(external_temperature, temperature_target, delta * 0.75)

	_check_resource_threshold("oxygen", oxygen, GameState.get_max_oxygen())
	_check_resource_threshold("suit_power", suit_power, GameState.get_max_suit_power())
	_check_resource_threshold("temperature_resistance", temperature_resistance, GameState.get_max_temperature_resistance())

	if oxygen <= 0.0:
		_begin_clone_failure()

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
		focused_prompt = "Approach a rover, terminal, drone, rock, or debris cube to interact."

func _handle_interaction_input() -> void:
	var keyboard_interact := Input.is_physical_key_pressed(KEY_E)
	var joy_interact := Input.is_joy_button_pressed(joy_id, JOY_BUTTON_X)
	var interact_pressed := keyboard_interact or joy_interact
	if focused_interactable == null:
		interact_was_pressed = interact_pressed
		return
	if interact_pressed and not interact_was_pressed:
		request_interaction()
	interact_was_pressed = interact_pressed

func _update_motion_feedback(delta: float, input_dir: Vector2, is_grounded: bool, is_running: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var move_strength := clampf(horizontal_speed / RUN_SPEED, 0.0, 1.0)
	var moving_on_ground := is_grounded and input_dir.length() > 0.01 and horizontal_speed > 0.1

	var bob_amount := HEAD_BOB_RUN_AMOUNT if is_running else HEAD_BOB_WALK_AMOUNT
	var bob_frequency := HEAD_BOB_RUN_FREQUENCY if is_running else HEAD_BOB_WALK_FREQUENCY
	if moving_on_ground:
		head_bob_time += delta * bob_frequency * lerpf(0.65, 1.15, move_strength)
	else:
		head_bob_time = lerpf(head_bob_time, 0.0, delta * 6.0)

	var bob_offset := Vector3.ZERO
	if moving_on_ground:
		bob_offset.y = sin(head_bob_time) * bob_amount
		bob_offset.x = cos(head_bob_time * 0.5) * bob_amount * 0.65

	camera.position = camera.position.lerp(base_camera_position + bob_offset, delta * TILT_SMOOTHNESS)

	var ground_normal := _get_ground_normal()
	var local_normal := global_basis.inverse() * ground_normal
	var terrain_pitch := atan2(local_normal.z, local_normal.y) * TERRAIN_TILT_AMOUNT
	var terrain_roll := -atan2(local_normal.x, local_normal.y) * TERRAIN_TILT_AMOUNT
	var strafe_roll := -input_dir.x * CAMERA_ROLL_AMOUNT * lerpf(0.4, 1.0, move_strength)
	var bob_roll := sin(head_bob_time * 0.5) * bob_amount * 0.2 if moving_on_ground else 0.0

	var target_tilt := Vector3(terrain_pitch, 0.0, terrain_roll + strafe_roll + bob_roll)
	tilt_pivot.rotation = Vector3(
		lerp_angle(tilt_pivot.rotation.x, target_tilt.x, delta * TILT_SMOOTHNESS),
		0.0,
		lerp_angle(tilt_pivot.rotation.z, target_tilt.z, delta * TILT_SMOOTHNESS)
	)

	pitch_pivot.rotation.x = look_pitch
	var fov_target := base_camera_fov + (RUN_FOV_BOOST * move_strength if is_running and moving_on_ground else 0.0)
	camera.fov = lerpf(camera.fov, fov_target, delta * FOV_SMOOTHNESS)

func _activate_telemetry_target(duration: float, success_message: String) -> bool:
	var nearest := _find_nearest_debris_cube()
	if nearest == null:
		telemetry_timer = 0.0
		telemetry_target_name = ""
		return false

	telemetry_timer = duration
	telemetry_target_position = nearest.global_position
	telemetry_target_name = str(nearest.call("get_interaction_name")) if nearest.has_method("get_interaction_name") else nearest.name
	if nearest.has_method("mark_telemetry_target"):
		nearest.call("mark_telemetry_target", duration)
	EventBus.push_mission_log(success_message)
	return true

func _find_nearest_debris_cube() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for candidate_variant in get_tree().get_nodes_in_group("debris_cube"):
		var candidate := candidate_variant as Node3D
		if candidate == null:
			continue
		if candidate.has_method("is_collected") and bool(candidate.call("is_collected")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest

func _update_telemetry_timer(delta: float) -> void:
	if telemetry_timer <= 0.0:
		return
	telemetry_timer = max(telemetry_timer - delta, 0.0)
	if telemetry_timer <= 0.0:
		telemetry_target_name = ""
		telemetry_target_position = Vector3.ZERO

func _check_resource_threshold(resource_id: String, current_value: float, max_value: float) -> void:
	var percent_remaining: float = (current_value / max(max_value, 0.001)) * 100.0
	if percent_remaining <= LOW_RESOURCE_THRESHOLD and bool(low_resource_ready[resource_id]):
		low_resource_ready[resource_id] = false
		EventBus.resource_threshold_crossed.emit(resource_id, percent_remaining)
	elif percent_remaining >= LOW_RESOURCE_RESET_THRESHOLD:
		low_resource_ready[resource_id] = true

func _begin_clone_failure() -> void:
	if is_failed:
		return
	is_failed = true
	failure_timer = FAILURE_DURATION
	velocity = Vector3.ZERO
	GameState.advance_clone_iteration()
	GameState.close_basecamp_terminal()
	GameState.close_paywall()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.clone_failed.emit()
	EventBus.push_mission_log("CLONE ITERATION FAILED")

func _respawn_from_basecamp() -> void:
	is_failed = false
	failure_timer = 0.0
	global_position = GameState.get_respawn_position()
	rotation = Vector3(0.0, GameState.get_respawn_yaw(), 0.0)
	velocity = Vector3.ZERO
	look_pitch = 0.0
	head_bob_time = 0.0
	tilt_pivot.rotation = Vector3.ZERO
	pitch_pivot.rotation = Vector3.ZERO
	camera.position = base_camera_position
	camera.fov = base_camera_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_restore_full_suit()
	EventBus.push_mission_log("Clone shell reinitialized at basecamp. Resume EVA.")

func _restore_full_suit() -> void:
	health = MAX_HEALTH
	oxygen = GameState.get_max_oxygen()
	suit_power = GameState.get_max_suit_power()
	temperature_resistance = GameState.get_max_temperature_resistance()
	heart_rate = 72.0
	external_temperature = -63.0
	for resource_id in low_resource_ready.keys():
		low_resource_ready[resource_id] = true

func _update_mouse_mode_for_ui() -> void:
	if GameState.is_modal_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _get_heading_degrees() -> int:
	var heading := int(round(fposmod(rad_to_deg(rotation.y), 360.0)))
	return 360 if heading == 0 else heading

func _get_heading_label() -> String:
	var degrees := float(_get_heading_degrees())
	var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var index := int(round(degrees / 45.0)) % directions.size()
	return directions[index]

func _get_waypoint_data() -> Dictionary:
	var target := telemetry_target_position if telemetry_timer > 0.0 else Vector3.ZERO
	var target_name := telemetry_target_name if telemetry_timer > 0.0 else "Debris Field Alpha"
	if telemetry_timer <= 0.0:
		var nearest := _find_nearest_debris_cube()
		if nearest != null:
			target = nearest.global_position
			target_name = "Debris Field Alpha"
	if target == Vector3.ZERO:
		return {
			"name": "No active fix",
			"distance": -1.0,
		}
	return {
		"name": target_name,
		"distance": global_position.distance_to(target),
	}

func _get_elevation_meters() -> float:
	return -4501.0 + ((global_position.y - ground_clearance) * 1.7)
