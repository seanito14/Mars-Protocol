class_name DataLog
extends Node3D

const HOVER_AMPLITUDE: float = 0.3
const ROTATION_SPEED: float = 0.7
const OXYGEN_RESTORE: float = 15.0
const SUIT_POWER_RESTORE: float = 20.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var pulse_light: OmniLight3D = $OmniLight3D

var base_height: float = 0.0
var hover_time: float = 0.0
var collected: bool = false

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("data_log")
	base_height = global_position.y
	if mesh.material_override != null:
		mesh.material_override = mesh.material_override.duplicate()
	_update_visuals()

func _process(delta: float) -> void:
	if collected:
		return

	hover_time += delta
	global_position.y = base_height + (sin(hover_time * 1.5) * HOVER_AMPLITUDE)
	rotation.y += delta * ROTATION_SPEED
	rotation.x = sin(hover_time * 0.9) * 0.1
	rotation.z = cos(hover_time * 1.2) * 0.06
	_update_visuals()

func get_interaction_name() -> String:
	return "Data Log Fragment"

func get_interaction_prompt() -> String:
	return "Tap INTERACT or press E to recover data and restore suit resources."

func get_focus_position() -> Vector3:
	return global_position + Vector3.UP * 0.3

func interact(player: Node) -> void:
	if collected:
		return

	collected = true
	if player != null and player.has_method("restore_oxygen"):
		player.call("restore_oxygen", OXYGEN_RESTORE)
	if player != null and player.has_method("restore_suit_power"):
		player.call("restore_suit_power", SUIT_POWER_RESTORE)

	EventBus.push_mission_log("Recovered a data log fragment. Oxygen restored by %.0f%%, suit power by %.0f%%." % [OXYGEN_RESTORE, SUIT_POWER_RESTORE])
	queue_free()

func is_collected() -> bool:
	return collected

func _update_visuals() -> void:
	var material := mesh.material_override as BaseMaterial3D
	if material != null:
		material.emission_enabled = true
		material.emission = Color(0.28, 0.62, 1.0, 1.0)
		material.emission_energy_multiplier = 1.4
	pulse_light.light_energy = 1.8
	pulse_light.omni_range = 5.0