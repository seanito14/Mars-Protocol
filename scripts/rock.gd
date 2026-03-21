class_name RockSample
extends Node3D

@export var sample_name: String = "Basalt"

@onready var mesh: MeshInstance3D = $MeshInstance3D

var collected: bool = false

func _ready() -> void:
	add_to_group("interactable")
	rotation_degrees = Vector3(0.0, fposmod(global_position.x * 11.0 + global_position.z * 7.0, 360.0), 0.0)
	var size_bias: float = 0.8 + (abs(sin(global_position.x * 0.18 + global_position.z * 0.11)) * 0.55)
	scale = Vector3(1.25, 0.85, 1.0) * size_bias

func get_interaction_name() -> String:
	return "%s Rock" % sample_name

func get_interaction_prompt() -> String:
	if collected:
		return "Geology tag already uploaded. Keep exploring the crater."
	return "Tap INTERACT or press E to scan this %s outcrop." % sample_name.to_lower()

func get_focus_position() -> Vector3:
	return global_position + Vector3.UP * 0.6

func interact(player: Node) -> void:
	if collected:
		EventBus.push_mission_log("%s sample site already cataloged." % sample_name)
		return
	collected = true
	mesh.scale *= 0.72
	mesh.modulate = Color(0.68, 0.63, 0.58, 1.0)
	EventBus.push_mission_log("%s outcrop logged. No recoverable debris detected." % sample_name)
	if player != null and player.has_method("catalog_rock_sample"):
		player.call("catalog_rock_sample", sample_name)
