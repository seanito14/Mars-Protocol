class_name BasecampTerminal
extends Node3D

@onready var terminal_screen: MeshInstance3D = $Screen
@onready var beacon_light: OmniLight3D = $OmniLight3D

var blink_time: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	if terminal_screen.material_override != null:
		terminal_screen.material_override = terminal_screen.material_override.duplicate()

func _process(delta: float) -> void:
	blink_time += delta
	var pulse := 0.5 + (0.5 * sin(blink_time * 2.4))
	beacon_light.light_energy = 1.2 + (pulse * 0.9)
	var material := terminal_screen.material_override as BaseMaterial3D
	if material != null:
		material.emission_enabled = true
		material.emission = Color(0.3, 0.95, 0.85, 1.0)
		material.emission_energy_multiplier = 1.4 + (pulse * 0.8)

func get_interaction_name() -> String:
	return "Basecamp Terminal"

func get_interaction_prompt() -> String:
	return "Tap INTERACT or press E to open the basecamp upgrade terminal."

func get_focus_position() -> Vector3:
	return global_position + Vector3.UP * 1.4

func interact(_player: Node) -> void:
	GameState.open_basecamp_terminal()
	EventBus.push_mission_log("Basecamp terminal linked. Upgrade queue is ready.")
