class_name DebrisCube
extends Node3D

const HOVER_AMPLITUDE: float = 0.4
const ROTATION_SPEED: float = 0.9

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var pulse_light: OmniLight3D = $OmniLight3D

var base_height: float = 0.0
var hover_time: float = 0.0
var telemetry_timer: float = 0.0
var collected: bool = false

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("debris_cube")
	base_height = global_position.y
	if mesh.material_override != null:
		mesh.material_override = mesh.material_override.duplicate()
	_update_visuals()

func _process(delta: float) -> void:
	if collected:
		return

	hover_time += delta
	if telemetry_timer > 0.0:
		telemetry_timer = max(telemetry_timer - delta, 0.0)

	global_position.y = base_height + (sin(hover_time * 1.8) * HOVER_AMPLITUDE)
	rotation.y += delta * ROTATION_SPEED
	rotation.x = sin(hover_time * 1.1) * 0.12
	rotation.z = cos(hover_time * 1.4) * 0.08
	_update_visuals()

func get_interaction_name() -> String:
	return "Glowing Debris Cube"

func get_interaction_prompt() -> String:
	return "Tap INTERACT or press E to salvage this debris cube."

func get_focus_position() -> Vector3:
	return global_position + Vector3.UP * 0.2

func interact(_player: Node) -> void:
	if collected:
		return

	collected = true
	GameState.add_salvage_cubes(1)
	EventBus.push_mission_log("Recovered a glowing debris cube. Salvage stock increased by 1.")
	queue_free()

func mark_telemetry_target(duration: float) -> void:
	telemetry_timer = max(telemetry_timer, duration)
	_update_visuals()

func is_collected() -> bool:
	return collected

func _update_visuals() -> void:
	var material := mesh.material_override as BaseMaterial3D
	var highlight_strength := 1.0 if telemetry_timer > 0.0 else 0.0
	if material != null:
		material.emission_enabled = true
		material.emission = Color(1.0, 0.62 + (highlight_strength * 0.2), 0.28 + (highlight_strength * 0.45), 1.0)
		material.emission_energy_multiplier = 1.1 + (highlight_strength * 2.6)
	pulse_light.light_energy = 1.6 + (highlight_strength * 3.4)
	pulse_light.omni_range = 4.4 + (highlight_strength * 2.0)
