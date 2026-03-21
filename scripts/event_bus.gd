class_name EventBusSingleton
extends Node

## Global Event Bus for ProjectMarsHighFidelity.
## Decouples the command server from rovers and players.
signal player_command_received(command: String, parameters: Dictionary)
signal mission_log_entry(message: String)
signal resource_threshold_crossed(resource_name: String, value: float)
signal telemetry_requested(context: String)
signal paywall_requested(context: String)
signal upgrade_purchased(upgrade_id: String, level: int, remaining_cubes: int)
signal clone_failed()
signal conversation_connected(mode: String)
signal conversation_disconnected(reason: String)
signal transcript_received(text: String)
signal agent_response_received(text: String)
signal scan_started(target_name: String)
signal scan_completed(target_name: String)
signal storm_state_changed(intensity: float)

# SudoAI Conversational Agent signals
signal sudo_ai_connected()
signal sudo_ai_disconnected(reason: String)
signal sudo_ai_state_changed(state_label: String)
signal sudo_ai_listening_started()
signal sudo_ai_listening_stopped()
signal sudo_ai_user_transcript(text: String)
signal sudo_ai_agent_response(text: String)
signal sudo_ai_speech_finished()
signal sudo_ai_hot_word_activated()
signal sudo_ai_overlay_dismissed()

func push_mission_log(message: String) -> void:
	mission_log_entry.emit(message)
