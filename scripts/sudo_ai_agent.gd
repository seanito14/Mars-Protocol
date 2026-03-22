class_name SudoAIAgentSingleton
extends Node

## SudoAI — canonical in-game voice agent.
##
## Architecture:
## - Local Python companion process handles wake-word standby + signed URL auth.
## - Godot only opens the ElevenLabs conversation after wake/manual activation.
## - Gameplay scenes receive one unified SudoAI path; the old hero_voice_service
##   remains a non-canonical fallback and is not used by the player-facing flow.

const AGENT_ID: String = "agent_8501km8et6jgexcbzctqvrg3zmgs"
const BRIDGE_BASE_URL: String = "http://127.0.0.1:8765"
const IOS_BRIDGE_BASE_URL_SETTING: String = "sudo_ai/ios_bridge_base_url"
const DEFAULT_IOS_BRIDGE_BASE_URL: String = "http://zs-Mac-mini.local:8765"
const BRIDGE_SCRIPT_PATH: String = "res://tools/sudo_ai_companion_launcher.py"
const IOS_AUDIO_SESSION_COMMAND_PATH: String = "user://ios_audio_session_command.json"
const BRIDGE_HEALTH_POLL_INTERVAL: float = 1.5
const BRIDGE_WAKE_EVENT_PORT: int = 4245
const RECONNECT_DELAY: float = 1.5
const ALWAYS_LISTEN_IN_GAMEPLAY: bool = true
const ACTIVATION_GREETING_PROMPT: String = "Give your brief startup greeting to the commander, then wait for their request."
const MAX_MIC_FRAMES_PER_PACKET: int = 1600
const MIC_SEND_INTERVAL: float = 0.1
const SILENCE_TIMEOUT_SECONDS: float = 4.5
const SPEECH_ACTIVITY_VOLUME_THRESHOLD: float = 0.014
const AGENT_AUDIO_FALLBACK_TIMEOUT: float = 1.2
const IOS_MASTER_VOLUME_RECOVERY_INTERVAL: float = 1.0
const GAMEPLAY_SCENE_PATHS := {
	"res://scenes/hero_demo.tscn": true,
	"res://scenes/landing_valley.tscn": true,
}

enum AgentState {
	OFFLINE,
	STANDBY,
	CONNECTING,
	CONNECTED,
	GREETING,
	LISTENING,
	SPEAKING,
	TIMEOUT,
	ERROR,
}

var state: AgentState = AgentState.OFFLINE
var socket: WebSocketPeer = WebSocketPeer.new()
var conversation_id: String = ""
var is_speaking: bool = false
var pending_audio_chunks: Array[PackedByteArray] = []
var reconnect_timer: float = -1.0
var should_reconnect: bool = false
var hot_word_active: bool = false
var agent_output_audio_format: String = "pcm_16000"
var user_input_audio_format: String = "pcm_16000"
var listen_after_activation_greeting: bool = false
var activation_greeting_in_progress: bool = false
var activation_greeting_played_for_scene: bool = false
var display_state_override: String = ""
var pending_scene_context: String = ""
var last_scene_path: String = ""
var last_routed_transcript: String = ""
var gameplay_voice_enabled: bool = false
var runtime_bootstrapped: bool = false
var scene_voice_started: bool = false
var scene_auto_activation_pending: bool = false
var bridge_launch_pid: int = -1
var bridge_base_url: String = ""
var bridge_available: bool = false
var bridge_auth_available: bool = false
var bridge_tts_available: bool = false
var bridge_wake_supported: bool = false
var bridge_wake_listening: bool = false
var bridge_wake_reason: String = ""
var bridge_last_wake_detected_at_ms: int = 0
var bridge_last_wake_detected_word: String = ""
var bridge_secret_import_ready: bool = false
var bridge_runtime_env_ready: bool = false
var bridge_dependency_install_ready: bool = false
var bridge_setup_error: String = ""
var last_bridge_setup_status_key: String = ""
var bridge_health_poll_timer: float = 0.0
var desired_wake_listener_enabled: bool = false
var silence_timer: float = SILENCE_TIMEOUT_SECONDS
var ios_audio_session_mode: String = ""
var pending_agent_audio_timeout: float = -1.0

## Audio playback
var audio_player: AudioStreamPlayer = null
var audio_buffer: PackedByteArray = PackedByteArray()

## Microphone capture
var mic_effect: AudioEffectCapture = null
var mic_bus_index: int = -1
var mic_stream_player: AudioStreamPlayer = null
var mic_active: bool = false
var mic_send_timer: float = 0.0

## Volume tracking for overlay waveform
var current_input_volume: float = 0.0
var current_output_volume: float = 0.0

## Bridge / wake-word networking
var wake_udp_server: UDPServer = UDPServer.new()
var wake_peers: Array[PacketPeerUDP] = []
var bridge_health_request: HTTPRequest = null
var bridge_signed_url_request: HTTPRequest = null
var bridge_wake_request: HTTPRequest = null
var bridge_tts_fallback_request: HTTPRequest = null
var pending_agent_fallback_text: String = ""
var ios_master_volume_recovery_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bridge_base_url = _resolve_bridge_base_url()
	_ensure_ios_master_output_level()

	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Master"
	add_child(audio_player)
	audio_player.finished.connect(_on_audio_finished)

	bridge_health_request = HTTPRequest.new()
	bridge_signed_url_request = HTTPRequest.new()
	bridge_wake_request = HTTPRequest.new()
	bridge_tts_fallback_request = HTTPRequest.new()
	add_child(bridge_health_request)
	add_child(bridge_signed_url_request)
	add_child(bridge_wake_request)
	add_child(bridge_tts_fallback_request)

	bridge_health_request.request_completed.connect(_on_bridge_health_request_completed)
	bridge_signed_url_request.request_completed.connect(_on_bridge_signed_url_request_completed)
	bridge_wake_request.request_completed.connect(_on_bridge_wake_request_completed)
	bridge_tts_fallback_request.request_completed.connect(_on_bridge_tts_fallback_request_completed)
	_sync_ios_audio_session_mode()

func _ensure_ios_master_output_level() -> void:
	if OS.get_name() != "iOS":
		return
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return
	if AudioServer.is_bus_mute(master_bus):
		AudioServer.set_bus_mute(master_bus, false)
	var volume_db := AudioServer.get_bus_volume_db(master_bus)
	if volume_db <= -40.0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(0.85))

func _tick_ios_master_output_recovery(delta: float) -> void:
	if OS.get_name() != "iOS":
		return
	ios_master_volume_recovery_timer -= delta
	if ios_master_volume_recovery_timer > 0.0:
		return
	ios_master_volume_recovery_timer = IOS_MASTER_VOLUME_RECOVERY_INTERVAL
	_ensure_ios_master_output_level()

func _ensure_runtime_bootstrapped() -> void:
	if runtime_bootstrapped:
		return
	runtime_bootstrapped = true
	_setup_microphone()
	if _should_use_udp_wake_events():
		_setup_wake_udp_listener()
	_request_bridge_health()
	print("SudoAI: Agent service ready. Gameplay scenes will listen for 'sudo' in standby.")

func _setup_microphone() -> void:
	var mic_bus_name := "SudoAIMic"
	mic_bus_index = AudioServer.get_bus_index(mic_bus_name)
	if mic_bus_index == -1:
		AudioServer.add_bus()
		mic_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(mic_bus_index, mic_bus_name)
		AudioServer.set_bus_mute(mic_bus_index, true)
		var capture := AudioEffectCapture.new()
		AudioServer.add_bus_effect(mic_bus_index, capture)
		mic_effect = capture
	else:
		mic_effect = AudioServer.get_bus_effect(mic_bus_index, 0) as AudioEffectCapture

	mic_stream_player = AudioStreamPlayer.new()
	var mic_stream := AudioStreamMicrophone.new()
	mic_stream_player.stream = mic_stream
	mic_stream_player.bus = "SudoAIMic"
	add_child(mic_stream_player)

func _setup_wake_udp_listener() -> void:
	var listen_error := wake_udp_server.listen(BRIDGE_WAKE_EVENT_PORT)
	if listen_error != OK:
		push_warning("SudoAI: Failed to listen for wake events on UDP port %d." % BRIDGE_WAKE_EVENT_PORT)

func _process(delta: float) -> void:
	_tick_ios_master_output_recovery(delta)
	_update_scene_gate()
	if runtime_bootstrapped:
		if _should_use_udp_wake_events():
			_poll_wake_events()
		_poll_bridge_health(delta)
		_maybe_auto_activate_scene_intro()
	_update_volume_levels()

	if reconnect_timer >= 0.0:
		reconnect_timer -= delta
		if reconnect_timer <= 0.0:
			reconnect_timer = -1.0
			if should_reconnect and gameplay_voice_enabled and hot_word_active:
				connect_agent()

	if hot_word_active and gameplay_voice_enabled and state == AgentState.LISTENING and not is_speaking and not activation_greeting_in_progress and not _should_keep_agent_live():
		silence_timer -= delta
		if silence_timer <= 0.0:
			_enter_timeout_standby()

	if pending_agent_audio_timeout >= 0.0:
		pending_agent_audio_timeout -= delta
		if pending_agent_audio_timeout <= 0.0:
			_handle_missing_agent_audio()

	if state == AgentState.OFFLINE or state == AgentState.ERROR or state == AgentState.STANDBY or state == AgentState.TIMEOUT:
		return

	socket.poll()
	var ws_state := socket.get_ready_state()

	match ws_state:
		WebSocketPeer.STATE_CONNECTING:
			pass
		WebSocketPeer.STATE_OPEN:
			if state == AgentState.CONNECTING:
				_on_connected()
			_receive_messages()
			if mic_active:
				mic_send_timer += delta
				if mic_send_timer >= MIC_SEND_INTERVAL:
					mic_send_timer = 0.0
					_send_mic_audio()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if state != AgentState.OFFLINE and state != AgentState.STANDBY and state != AgentState.TIMEOUT:
				var reason := socket.get_close_reason()
				_handle_socket_closed(reason)

## ── Public API ──────────────────────────────────────────────────────────

func notify_gameplay_input_started() -> void:
	_start_gameplay_standby()

func prime_standby_only() -> void:
	_start_gameplay_standby()

func connect_agent() -> void:
	if not gameplay_voice_enabled:
		return
	if bridge_signed_url_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	should_reconnect = hot_word_active
	_set_state(AgentState.CONNECTING)
	var err := bridge_signed_url_request.request("%s/signed-url" % bridge_base_url)
	if err != OK:
		push_warning("SudoAI: Failed to request signed URL from the local bridge.")
		_handle_activation_failure("signed_url_request_failed")

func disconnect_agent() -> void:
	should_reconnect = false
	_close_socket_quietly("manual_disconnect")
	_stop_mic()
	hot_word_active = false
	pending_agent_fallback_text = ""
	listen_after_activation_greeting = false
	activation_greeting_in_progress = false
	is_speaking = false
	pending_audio_chunks.clear()
	audio_buffer.clear()
	EventBus.conversation_disconnected.emit("manual_disconnect")
	if gameplay_voice_enabled:
		if _should_request_wake_listener():
			_request_wake_listener(true)
		_emit_bridge_standby_state()
	else:
		_set_state_with_label(AgentState.OFFLINE, "OFFLINE")
	EventBus.sudo_ai_overlay_dismissed.emit()

func _start_gameplay_standby() -> void:
	_sync_scene_tracking()
	if not _is_current_scene_gameplay():
		return
	scene_voice_started = true
	_ensure_runtime_bootstrapped()
	if _can_enable_voice_for_current_scene():
		if gameplay_voice_enabled:
			_ensure_overlay_present()
		else:
			_enable_gameplay_voice()

func start_listening() -> void:
	if state != AgentState.CONNECTED and state != AgentState.LISTENING:
		return
	_start_mic()
	silence_timer = SILENCE_TIMEOUT_SECONDS
	_set_state(AgentState.LISTENING)
	EventBus.conversation_connected.emit("sudo ai")
	EventBus.sudo_ai_listening_started.emit()

func stop_listening() -> void:
	if state != AgentState.LISTENING:
		return
	_stop_mic()
	_set_state(AgentState.CONNECTED)
	EventBus.sudo_ai_listening_stopped.emit()

func toggle_listening() -> void:
	if state == AgentState.LISTENING:
		stop_listening()
	else:
		start_listening()

func activate_hot_word() -> void:
	if not gameplay_voice_enabled:
		return
	if hot_word_active:
		return
	scene_auto_activation_pending = false
	hot_word_active = true
	EventBus.sudo_ai_hot_word_activated.emit()
	if _should_request_wake_listener() and not _should_keep_agent_live():
		_request_wake_listener(false)
	if state == AgentState.CONNECTED:
		_begin_active_session()
	else:
		connect_agent()

func deactivate_hot_word() -> void:
	hot_word_active = false
	listen_after_activation_greeting = false
	pending_agent_fallback_text = ""
	_stop_mic()
	activation_greeting_in_progress = false
	if audio_player and audio_player.playing:
		audio_player.stop()
	pending_audio_chunks.clear()
	audio_buffer.clear()
	is_speaking = false
	should_reconnect = false
	_close_socket_quietly("standby")
	EventBus.sudo_ai_overlay_dismissed.emit()
	EventBus.conversation_disconnected.emit("standby")
	if gameplay_voice_enabled:
		if _should_request_wake_listener():
			_request_wake_listener(true)
		_emit_bridge_standby_state()
	else:
		_set_state_with_label(AgentState.OFFLINE, "OFFLINE")

func send_text_message(text: String) -> void:
	_send_user_message(text, true)

func send_contextual_update(context: String) -> void:
	pending_scene_context = context
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := JSON.stringify({"type": "contextual_update", "text": context})
	socket.send_text(payload)

func set_scene_context(context: String) -> void:
	send_contextual_update(context)

func get_state_label() -> String:
	if not display_state_override.is_empty():
		return display_state_override
	match state:
		AgentState.OFFLINE: return "OFFLINE"
		AgentState.STANDBY: return "STANDBY"
		AgentState.CONNECTING: return "CONNECTING"
		AgentState.CONNECTED: return "CONNECTED"
		AgentState.GREETING: return "GREETING"
		AgentState.LISTENING: return "LISTENING"
		AgentState.SPEAKING: return "SPEAKING"
		AgentState.TIMEOUT: return "TIMEOUT"
		AgentState.ERROR: return "ERROR"
		_: return "UNKNOWN"

func is_connected_to_agent() -> bool:
	return state != AgentState.OFFLINE and state != AgentState.ERROR

func is_agent_speaking() -> bool:
	return is_speaking

func get_input_volume() -> float:
	return current_input_volume

func get_output_volume() -> float:
	return current_output_volume

## ── Scene / standby control ─────────────────────────────────────────────

func _update_scene_gate() -> void:
	var scene_changed := _sync_scene_tracking()

	var desired_enabled := _can_enable_voice_for_current_scene()

	if scene_changed and desired_enabled and hot_word_active:
		deactivate_hot_word()

	if desired_enabled != gameplay_voice_enabled:
		if desired_enabled:
			_enable_gameplay_voice()
		else:
			_disable_gameplay_voice()
	elif desired_enabled:
		_ensure_overlay_present()

func _enable_gameplay_voice() -> void:
	_ensure_runtime_bootstrapped()
	gameplay_voice_enabled = true
	_ensure_overlay_present()
	_request_bridge_health()
	if _should_request_wake_listener():
		_request_wake_listener(true)
	else:
		desired_wake_listener_enabled = false
	_emit_bridge_standby_state()
	_maybe_auto_activate_scene_intro()

func _disable_gameplay_voice() -> void:
	gameplay_voice_enabled = false
	if not runtime_bootstrapped:
		_set_state_with_label(AgentState.OFFLINE, "OFFLINE")
		EventBus.sudo_ai_overlay_dismissed.emit()
		return
	desired_wake_listener_enabled = false
	if hot_word_active:
		deactivate_hot_word()
	else:
		_close_socket_quietly("scene_gate")
		_stop_mic()
		_set_state_with_label(AgentState.OFFLINE, "OFFLINE")
	if _should_request_wake_listener():
		_request_wake_listener(false)
	EventBus.sudo_ai_overlay_dismissed.emit()

func _is_current_scene_gameplay() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false
	return _is_gameplay_scene_path(str(current_scene.scene_file_path))

func _can_enable_voice_for_current_scene() -> bool:
	if not _is_current_scene_gameplay():
		return false
	if get_tree().paused:
		return false
	if GameState != null and GameState.has_method("is_modal_open") and bool(GameState.is_modal_open()):
		return false
	return true

func _sync_scene_tracking() -> bool:
	var current_scene := get_tree().current_scene
	var current_scene_path := ""
	if current_scene != null:
		current_scene_path = str(current_scene.scene_file_path)
	var scene_changed := current_scene_path != last_scene_path
	if not scene_changed:
		return false
	last_scene_path = current_scene_path
	last_routed_transcript = ""
	if _is_gameplay_scene_path(current_scene_path):
		scene_voice_started = true
		scene_auto_activation_pending = true
		activation_greeting_played_for_scene = false
	else:
		scene_voice_started = false
		scene_auto_activation_pending = false
		pending_scene_context = ""
	return true

func _maybe_auto_activate_scene_intro() -> void:
	if not gameplay_voice_enabled:
		return
	if not _is_current_scene_gameplay():
		return
	if hot_word_active or activation_greeting_in_progress:
		return
	if not bridge_available or not bridge_auth_available:
		return
	if not scene_auto_activation_pending and not _should_keep_agent_live():
		return
	scene_auto_activation_pending = false
	activate_hot_word()

func _is_gameplay_scene_path(scene_path: String) -> bool:
	return bool(GAMEPLAY_SCENE_PATHS.get(scene_path, false))

func _ensure_overlay_present() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var canvas_layer := current_scene.get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return
	if canvas_layer.get_node_or_null("SudoAIOverlay") != null:
		return
	var overlay := SudoAIOverlay.new()
	overlay.name = "SudoAIOverlay"
	canvas_layer.add_child(overlay)

func _emit_bridge_standby_state() -> void:
	if not gameplay_voice_enabled:
		_set_state_with_label(AgentState.OFFLINE, "OFFLINE")
		return
	if not bridge_available:
		if _uses_remote_bridge():
			_set_state_with_label(AgentState.OFFLINE, "WAITING FOR MAC VOICE BRIDGE")
		else:
			_set_state_with_label(AgentState.OFFLINE, "OFFLINE")
		return
	if not bridge_secret_import_ready:
		_set_state_with_label(AgentState.ERROR, "SUDO SETUP REQUIRED")
		return
	if not bridge_auth_available:
		_set_state_with_label(AgentState.ERROR, "SUDO AUTH REQUIRED")
		return
	if _uses_remote_bridge():
		if _should_keep_agent_live():
			_set_state_with_label(AgentState.STANDBY, "RECONNECTING SUDO AI")
		else:
			_set_state_with_label(AgentState.STANDBY, "TAP SUDO TO TALK")
		return
	if bridge_wake_supported:
		if bridge_wake_listening:
			_set_state_with_label(AgentState.STANDBY, "LISTENING FOR SUDO")
		else:
			_set_state_with_label(AgentState.STANDBY, "STANDBY")
		return
	_set_state_with_label(AgentState.STANDBY, "PRESS F TO TALK")

## ── Local bridge / wake events ──────────────────────────────────────────

func _maybe_launch_voice_companion() -> void:
	if _uses_remote_bridge():
		return
	if bridge_available or bridge_launch_pid > 0:
		return
	var script_path := ProjectSettings.globalize_path(BRIDGE_SCRIPT_PATH)
	if not FileAccess.file_exists(script_path):
		return
	for candidate in PackedStringArray(["python3", "python"]):
		var pid := OS.create_process(candidate, PackedStringArray([script_path]))
		if pid > 0:
			bridge_launch_pid = pid
			print("SudoAI: Launched local voice companion with %s (pid %d)." % [candidate, pid])
			return

func _poll_bridge_health(delta: float) -> void:
	bridge_health_poll_timer -= delta
	if bridge_health_poll_timer > 0.0:
		return
	bridge_health_poll_timer = BRIDGE_HEALTH_POLL_INTERVAL
	_request_bridge_health()

func _request_bridge_health() -> void:
	if bridge_health_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var err := bridge_health_request.request("%s/health" % bridge_base_url)
	if err != OK:
		bridge_available = false
		_maybe_launch_voice_companion()
		bridge_health_poll_timer = 0.5
		if gameplay_voice_enabled and not hot_word_active:
			_emit_bridge_standby_state()

func _request_wake_listener(enabled: bool) -> void:
	if not _should_request_wake_listener():
		desired_wake_listener_enabled = false
		return
	desired_wake_listener_enabled = enabled
	if bridge_wake_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var endpoint := "/wake/start" if enabled else "/wake/stop"
	var err := bridge_wake_request.request(
		"%s%s" % [bridge_base_url, endpoint],
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		"{}"
	)
	if err != OK and enabled and gameplay_voice_enabled and not hot_word_active:
		_emit_bridge_standby_state()

func _poll_wake_events() -> void:
	wake_udp_server.poll()
	if wake_udp_server.is_connection_available():
		var peer: PacketPeerUDP = wake_udp_server.take_connection()
		wake_peers.append(peer)

	for peer in wake_peers:
		while peer.get_available_packet_count() > 0:
			var packet := peer.get_packet()
			_handle_wake_event(packet.get_string_from_utf8())

func _handle_wake_event(raw_json: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var event := parsed as Dictionary
	var event_type := str(event.get("type", ""))
	match event_type:
		"wake_ready":
			bridge_wake_supported = true
			bridge_wake_listening = true
			if gameplay_voice_enabled and not hot_word_active:
				_emit_bridge_standby_state()
		"wake_detected":
			if gameplay_voice_enabled and not hot_word_active and not is_speaking and not activation_greeting_in_progress:
				EventBus.push_mission_log("[SUDO AI] Wake word detected.")
				activate_hot_word()
		"mic_blocked":
			bridge_wake_supported = false
			bridge_wake_reason = "mic_blocked"
			if gameplay_voice_enabled and not hot_word_active:
				_emit_bridge_standby_state()
		"wake_error":
			bridge_wake_supported = false
			bridge_wake_reason = str(event.get("message", "wake_error"))
			if gameplay_voice_enabled and not hot_word_active:
				_emit_bridge_standby_state()

func _on_bridge_health_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	bridge_available = result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if not bridge_available:
		bridge_auth_available = false
		bridge_tts_available = false
		bridge_secret_import_ready = false
		bridge_runtime_env_ready = false
		bridge_dependency_install_ready = false
		bridge_setup_error = ""
		last_bridge_setup_status_key = ""
		_maybe_launch_voice_companion()
		bridge_health_poll_timer = 0.5
		if gameplay_voice_enabled and not hot_word_active:
			_emit_bridge_standby_state()
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		bridge_available = false
		bridge_auth_available = false
		bridge_tts_available = false
		bridge_secret_import_ready = false
		bridge_runtime_env_ready = false
		bridge_dependency_install_ready = false
		bridge_setup_error = ""
		last_bridge_setup_status_key = ""
		_maybe_launch_voice_companion()
		bridge_health_poll_timer = 0.5
		if gameplay_voice_enabled and not hot_word_active:
			_emit_bridge_standby_state()
		return

	var payload := parsed as Dictionary
	bridge_tts_available = bool(payload.get("tts_enabled", false))
	bridge_auth_available = bool(payload.get("agent_enabled", false))
	bridge_wake_supported = bool(payload.get("wake_supported", false))
	bridge_wake_listening = bool(payload.get("wake_listening", false))
	bridge_wake_reason = str(payload.get("wake_reason", ""))
	var wake_detected_at_ms := _variant_to_int(
		payload.get("wake_last_detected_at_ms", bridge_last_wake_detected_at_ms),
		bridge_last_wake_detected_at_ms
	)
	var wake_detected_word := str(payload.get("wake_last_detected_word", bridge_last_wake_detected_word))
	var wake_detection_changed := wake_detected_at_ms > 0 and wake_detected_at_ms != bridge_last_wake_detected_at_ms
	bridge_last_wake_detected_at_ms = wake_detected_at_ms
	bridge_last_wake_detected_word = wake_detected_word
	bridge_secret_import_ready = bool(payload.get("secret_import_ready", false))
	bridge_runtime_env_ready = bool(payload.get("runtime_env_ready", false))
	bridge_dependency_install_ready = bool(payload.get("dependency_install_ready", false))
	bridge_setup_error = str(payload.get("setup_error", ""))
	_report_bridge_setup_status()

	if wake_detection_changed and gameplay_voice_enabled and not hot_word_active and not is_speaking and not activation_greeting_in_progress:
		EventBus.push_mission_log("[SUDO AI] Wake word detected.")
		activate_hot_word()

	if gameplay_voice_enabled and desired_wake_listener_enabled and bridge_wake_supported and not bridge_wake_listening and not hot_word_active:
		_request_wake_listener(true)

	if gameplay_voice_enabled and not hot_word_active:
		_emit_bridge_standby_state()
	_maybe_auto_activate_scene_intro()

func _on_bridge_signed_url_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_handle_activation_failure("signed_url_unavailable")
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_handle_activation_failure("signed_url_invalid")
		return

	var payload := parsed as Dictionary
	var signed_url := str(payload.get("signed_url", ""))
	if signed_url.is_empty():
		_handle_activation_failure("signed_url_missing")
		return

	socket = WebSocketPeer.new()
	pending_agent_audio_timeout = -1.0
	var err := socket.connect_to_url(signed_url)
	if err != OK:
		_handle_activation_failure("socket_connect_failed")

func _on_bridge_wake_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		if desired_wake_listener_enabled and gameplay_voice_enabled and not hot_word_active:
			_emit_bridge_standby_state()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var payload := parsed as Dictionary
	bridge_wake_supported = bool(payload.get("wake_supported", bridge_wake_supported))
	bridge_wake_listening = bool(payload.get("wake_listening", bridge_wake_listening))
	bridge_wake_reason = str(payload.get("wake_reason", bridge_wake_reason))
	if gameplay_voice_enabled and not hot_word_active:
		_emit_bridge_standby_state()
	_maybe_auto_activate_scene_intro()

func _on_bridge_tts_fallback_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var has_pending_fallback := not pending_agent_fallback_text.is_empty()
	if not has_pending_fallback:
		return
	pending_agent_fallback_text = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_resume_after_missing_audio()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_resume_after_missing_audio()
		return
	var payload := parsed as Dictionary
	var audio_base64 := str(payload.get("audio_base64", ""))
	var used_tts := bool(payload.get("used_tts", false))
	if not used_tts or audio_base64.is_empty():
		_resume_after_missing_audio()
		return
	var audio_bytes := Marshalls.base64_to_raw(audio_base64)
	if audio_bytes.is_empty():
		_resume_after_missing_audio()
		return
	var stream := AudioStreamMP3.new()
	stream.data = audio_bytes
	audio_player.stream = stream
	audio_player.play()
	is_speaking = true
	_set_state(AgentState.SPEAKING)

func _report_bridge_setup_status() -> void:
	var status_key := "%s|%s|%s|%s|%s|%s|%s" % [
		str(bridge_secret_import_ready),
		str(bridge_runtime_env_ready),
		str(bridge_dependency_install_ready),
		str(bridge_auth_available),
		str(bridge_wake_supported),
		bridge_wake_reason,
		bridge_setup_error
	]
	if status_key == last_bridge_setup_status_key:
		return
	last_bridge_setup_status_key = status_key
	var message := _build_bridge_setup_status_message()
	if not message.is_empty():
		EventBus.push_mission_log(message)

func _build_bridge_setup_status_message() -> String:
	if not bridge_available:
		if _uses_remote_bridge():
			return "[SUDO AI] Waiting for the Mac voice bridge at %s." % bridge_base_url
		return "[SUDO AI] Local voice bridge offline."
	if not bridge_secret_import_ready:
		match bridge_setup_error:
			"secret_source_missing":
				return "[SUDO AI] Setup required: add sudoaiapi.rtf to the Desktop with ElevenLabs credentials."
			"secret_import_invalid":
				return "[SUDO AI] Setup required: sudoaiapi.rtf could not be parsed. Use env-style ELEVENLABS entries."
			"secret_persist_failed":
				return "[SUDO AI] Setup blocked: secure secret import could not be saved."
			_:
				return "[SUDO AI] Setup required: ElevenLabs credentials not imported yet."
	if not bridge_runtime_env_ready:
		if bridge_setup_error == "runtime_env_create_failed" or bridge_setup_error == "runtime_env_missing_python":
			return "[SUDO AI] Secure runtime setup failed. Manual voice may still work, but wake word is unavailable."
		return "[SUDO AI] Bootstrapping secure voice runtime."
	if not bridge_dependency_install_ready:
		if bridge_setup_error == "dependency_install_failed":
			return "[SUDO AI] Voice dependencies failed to install. Wake word is unavailable until setup succeeds."
		if bridge_setup_error == "dependency_manifest_missing":
			return "[SUDO AI] Voice dependency manifest missing. Wake word is unavailable."
		return "[SUDO AI] Installing SudoAI voice dependencies."
	if not bridge_auth_available:
		return "[SUDO AI] ElevenLabs auth unavailable. Check the imported credentials."
	if _uses_remote_bridge():
		return "[SUDO AI] iPad voice bridge ready. Tap SUDO to talk."
	if bridge_wake_supported:
		return "[SUDO AI] Wake word standby ready."
	if bridge_wake_reason == "missing_vosk_model":
		return "[SUDO AI] Wake word unavailable until SUDO_AI_WAKE_MODEL_PATH points to a Vosk model."
	if bridge_wake_reason == "missing_python_dependencies":
		return "[SUDO AI] Wake word runtime still installing."
	if not bridge_wake_reason.is_empty():
		return "[SUDO AI] Wake word unavailable right now. Press F to talk."
	return ""

## ── Internal conversation flow ──────────────────────────────────────────

func _on_connected() -> void:
	_set_state(AgentState.CONNECTED)
	var init_payload := JSON.stringify({"type": "conversation_initiation_client_data"})
	socket.send_text(init_payload)
	EventBus.sudo_ai_connected.emit()
	if not pending_scene_context.is_empty():
		send_contextual_update(pending_scene_context)
	_begin_active_session()

func _begin_active_session() -> void:
	if not hot_word_active:
		return
	if activation_greeting_played_for_scene:
		start_listening()
		return
	_speak_activation_greeting()

func _receive_messages() -> void:
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		var text := packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_handle_message(parsed as Dictionary)

func _handle_message(data: Dictionary) -> void:
	var msg_type: String = str(data.get("type", ""))

	match msg_type:
		"conversation_initiation_metadata":
			var event: Dictionary = data.get("conversation_initiation_metadata_event", {})
			conversation_id = str(event.get("conversation_id", ""))
			agent_output_audio_format = str(event.get("agent_output_audio_format", agent_output_audio_format)).to_lower()
			user_input_audio_format = str(event.get("user_input_audio_format", user_input_audio_format)).to_lower()
			EventBus.push_mission_log("[SUDO AI] Conversation initiated.")

		"vad_score":
			var event: Dictionary = data.get("vad_score_event", {})
			var vad_score := float(event.get("vad_score", 0.0))
			if vad_score > 0.25 and hot_word_active:
				silence_timer = SILENCE_TIMEOUT_SECONDS

		"user_transcript":
			var event: Dictionary = data.get("user_transcription_event", {})
			var transcript: String = str(event.get("user_transcript", "")).strip_edges()
			if transcript.is_empty():
				return
			EventBus.sudo_ai_user_transcript.emit(transcript)
			EventBus.transcript_received.emit(transcript)
			EventBus.push_mission_log("> Commander: %s" % transcript)
			silence_timer = SILENCE_TIMEOUT_SECONDS
			_route_scene_voice_command(transcript)

		"agent_response":
			var event: Dictionary = data.get("agent_response_event", {})
			var response: String = str(event.get("agent_response", ""))
			if response.is_empty():
				return
			is_speaking = true
			pending_agent_fallback_text = response
			_set_state(AgentState.SPEAKING)
			pending_agent_audio_timeout = AGENT_AUDIO_FALLBACK_TIMEOUT
			EventBus.sudo_ai_agent_response.emit(response)
			EventBus.agent_response_received.emit(response)
			EventBus.push_mission_log("> SudoAI: %s" % response)

		"audio":
			var event: Dictionary = data.get("audio_event", {})
			var audio_b64: String = str(event.get("audio_base_64", ""))
			if audio_b64.is_empty():
				return
			pending_agent_fallback_text = ""
			pending_agent_audio_timeout = -1.0
			var chunk := Marshalls.base64_to_raw(audio_b64)
			pending_audio_chunks.append(chunk)
			_try_play_audio()

		"ping":
			var event: Dictionary = data.get("ping_event", {})
			var event_id := _variant_to_int(event.get("event_id", 0), 0)
			var ping_ms := _variant_to_int(event.get("ping_ms", 0), 0)
			get_tree().create_timer(float(ping_ms) / 1000.0).timeout.connect(func(): _send_pong(event_id))

		"interruption":
			audio_player.stop()
			pending_audio_chunks.clear()
			audio_buffer.clear()
			pending_agent_fallback_text = ""
			is_speaking = false
			if hot_word_active and mic_active:
				silence_timer = SILENCE_TIMEOUT_SECONDS
				_set_state(AgentState.LISTENING)
			else:
				_set_state(AgentState.CONNECTED)

func _send_pong(event_id: int) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := JSON.stringify({
		"type": "pong",
		"event_id": event_id,
	})
	socket.send_text(payload)

func _route_scene_voice_command(transcript: String) -> void:
	if transcript == last_routed_transcript:
		return
	last_routed_transcript = transcript
	var current_scene := get_tree().current_scene
	if current_scene == null or not current_scene.has_method("handle_voice_command"):
		return
	var result: Variant = current_scene.call("handle_voice_command", transcript)
	if typeof(result) != TYPE_DICTIONARY:
		return
	var payload := result as Dictionary
	var command_id := str(payload.get("command_id", ""))
	if command_id.is_empty() or command_id == "unknown" or command_id == "empty":
		return
	var response_text := str(payload.get("response_text", "")).strip_edges()
	if not response_text.is_empty():
		send_contextual_update("Gameplay command '%s' executed locally. Result: %s" % [command_id, response_text])

func _try_play_audio() -> void:
	if audio_player.playing:
		return
	if pending_audio_chunks.is_empty():
		return
	pending_agent_audio_timeout = -1.0
	var combined := PackedByteArray()
	for chunk in pending_audio_chunks:
		combined.append_array(chunk)
	pending_audio_chunks.clear()
	var stream := _build_audio_stream(combined)
	if stream == null:
		push_warning("SudoAI: Could not build audio stream for format %s." % agent_output_audio_format)
		is_speaking = false
		return
	audio_player.stream = stream
	audio_player.play()
	is_speaking = true

func _on_audio_finished() -> void:
	if pending_audio_chunks.size() > 0:
		_try_play_audio()
		return

	is_speaking = false
	pending_agent_audio_timeout = -1.0
	EventBus.sudo_ai_speech_finished.emit()
	if activation_greeting_in_progress:
		_finish_activation_greeting(true)
	elif hot_word_active and mic_active and gameplay_voice_enabled:
		silence_timer = SILENCE_TIMEOUT_SECONDS
		_set_state(AgentState.LISTENING)
	else:
		_set_state(AgentState.CONNECTED)

## ── Microphone streaming ────────────────────────────────────────────────

func _start_mic() -> void:
	if mic_active:
		return
	mic_active = true
	mic_send_timer = 0.0
	if mic_effect:
		mic_effect.clear_buffer()
	if mic_stream_player:
		mic_stream_player.play()
	_sync_ios_audio_session_mode()

func _stop_mic() -> void:
	if not mic_active:
		return
	mic_active = false
	if mic_stream_player:
		mic_stream_player.stop()
	_sync_ios_audio_session_mode()

func _send_mic_audio() -> void:
	if not mic_effect or not mic_active:
		return
	var frames_available := mic_effect.get_frames_available()
	if frames_available == 0:
		return
	var stereo_frames := mic_effect.get_buffer(mini(frames_available, MAX_MIC_FRAMES_PER_PACKET))
	var mono_samples := PackedFloat32Array()
	mono_samples.resize(stereo_frames.size())
	var rms_sum: float = 0.0
	for i in range(stereo_frames.size()):
		var mono_sample: float = (stereo_frames[i].x + stereo_frames[i].y) * 0.5
		mono_samples[i] = mono_sample
		rms_sum += mono_sample * mono_sample
	current_input_volume = sqrt(rms_sum / max(float(stereo_frames.size()), 1.0))
	if current_input_volume > SPEECH_ACTIVITY_VOLUME_THRESHOLD:
		silence_timer = SILENCE_TIMEOUT_SECONDS
	var mix_rate := AudioServer.get_mix_rate()
	var target_rate := _extract_pcm_sample_rate(user_input_audio_format)
	var resampled := _resample_mono_samples(mono_samples, mix_rate, target_rate)
	var pcm := PackedByteArray()
	pcm.resize(resampled.size() * 2)
	for i in range(resampled.size()):
		var sample_int: int = clampi(int(resampled[i] * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, sample_int)
	var b64 := Marshalls.raw_to_base64(pcm)
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var payload := JSON.stringify({"user_audio_chunk": b64})
		socket.send_text(payload)

func _update_volume_levels() -> void:
	if not mic_active:
		current_input_volume = lerpf(current_input_volume, 0.0, 0.12)
	if not is_speaking:
		current_output_volume = lerpf(current_output_volume, 0.0, 0.12)
	elif audio_player.playing:
		current_output_volume = lerpf(current_output_volume, 0.76, 0.15)

## ── Greeting / timeout / state helpers ─────────────────────────────────

func _speak_activation_greeting() -> void:
	if activation_greeting_in_progress:
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		activation_greeting_played_for_scene = true
		start_listening()
		return
	activation_greeting_in_progress = true
	activation_greeting_played_for_scene = true
	is_speaking = true
	pending_agent_audio_timeout = AGENT_AUDIO_FALLBACK_TIMEOUT
	listen_after_activation_greeting = true
	_set_state(AgentState.GREETING)
	_send_user_message(ACTIVATION_GREETING_PROMPT, false)

func _finish_activation_greeting(start_listening_after: bool) -> void:
	if not activation_greeting_in_progress:
		return
	activation_greeting_in_progress = false
	is_speaking = false
	pending_agent_audio_timeout = -1.0
	EventBus.sudo_ai_speech_finished.emit()
	if start_listening_after and listen_after_activation_greeting and hot_word_active:
		start_listening()
	elif hot_word_active:
		_set_state(AgentState.CONNECTED)
	else:
		if gameplay_voice_enabled:
			_emit_bridge_standby_state()
		else:
			_set_state(AgentState.CONNECTED)
	listen_after_activation_greeting = false

func _enter_timeout_standby() -> void:
	if _should_keep_agent_live():
		silence_timer = SILENCE_TIMEOUT_SECONDS
		return
	EventBus.push_mission_log("[SUDO AI] Returning to standby after silence timeout.")
	EventBus.conversation_disconnected.emit("timeout")
	_set_state(AgentState.TIMEOUT)
	deactivate_hot_word()

func _handle_activation_failure(reason: String) -> void:
	push_warning("SudoAI: Activation failed (%s)." % reason)
	if bridge_setup_error.is_empty():
		EventBus.push_mission_log("[SUDO AI] ElevenLabs connection unavailable. Check the secure bridge setup.")
	else:
		_report_bridge_setup_status()
	hot_word_active = false
	should_reconnect = false
	pending_agent_fallback_text = ""
	_stop_mic()
	_close_socket_quietly(reason)
	pending_agent_audio_timeout = -1.0
	if _should_request_wake_listener():
		_request_wake_listener(true)
	EventBus.sudo_ai_overlay_dismissed.emit()
	if gameplay_voice_enabled:
		_emit_bridge_standby_state()
	else:
		_set_state_with_label(AgentState.ERROR, "OFFLINE")

func _handle_socket_closed(reason: String) -> void:
	_stop_mic()
	is_speaking = false
	pending_agent_fallback_text = ""
	activation_greeting_in_progress = false
	listen_after_activation_greeting = false
	pending_agent_audio_timeout = -1.0
	pending_audio_chunks.clear()
	audio_buffer.clear()
	EventBus.sudo_ai_disconnected.emit(reason)
	if should_reconnect and hot_word_active and gameplay_voice_enabled:
		_set_state(AgentState.CONNECTING)
		reconnect_timer = RECONNECT_DELAY
	else:
		if gameplay_voice_enabled:
			_emit_bridge_standby_state()
		else:
			_set_state_with_label(AgentState.OFFLINE, "OFFLINE")

func _close_socket_quietly(reason: String) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN or socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		socket.close(1000, reason)
	socket = WebSocketPeer.new()

func _send_user_message(text: String, log_as_user: bool) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := JSON.stringify({
		"type": "user_message",
		"text": text,
	})
	socket.send_text(payload)
	if log_as_user:
		EventBus.sudo_ai_user_transcript.emit(text)
		EventBus.transcript_received.emit(text)
		EventBus.push_mission_log("> Commander: %s" % text)

func _build_audio_stream(audio_bytes: PackedByteArray) -> AudioStream:
	if audio_bytes.is_empty():
		return null
	if agent_output_audio_format.begins_with("pcm_"):
		var pcm_stream := AudioStreamWAV.new()
		pcm_stream.format = AudioStreamWAV.FORMAT_16_BITS
		pcm_stream.mix_rate = _extract_pcm_sample_rate(agent_output_audio_format)
		pcm_stream.stereo = false
		pcm_stream.data = audio_bytes
		return pcm_stream
	if agent_output_audio_format.begins_with("mp3"):
		var mp3_stream := AudioStreamMP3.new()
		mp3_stream.data = audio_bytes
		return mp3_stream
	return null

func _resample_mono_samples(samples: PackedFloat32Array, from_rate: int, to_rate: int) -> PackedFloat32Array:
	if samples.is_empty():
		return samples
	if from_rate <= 0 or to_rate <= 0 or from_rate == to_rate:
		return samples
	var output_size := maxi(int(round(float(samples.size()) * float(to_rate) / float(from_rate))), 1)
	var output := PackedFloat32Array()
	output.resize(output_size)
	var ratio := float(from_rate) / float(to_rate)
	for i in range(output_size):
		var source_position := float(i) * ratio
		var base_index := mini(int(floor(source_position)), samples.size() - 1)
		var next_index := mini(base_index + 1, samples.size() - 1)
		var weight := source_position - float(base_index)
		output[i] = lerpf(samples[base_index], samples[next_index], weight)
	return output

func _extract_pcm_sample_rate(format_name: String) -> int:
	var parts := format_name.split("_", false)
	if parts.size() < 2:
		return 16000
	return maxi(parts[1].to_int(), 8000)

func _handle_missing_agent_audio() -> void:
	pending_agent_audio_timeout = -1.0
	if _can_request_bridge_tts_fallback():
		_request_bridge_tts_fallback(pending_agent_fallback_text)
		return
	pending_agent_fallback_text = ""
	_resume_after_missing_audio()

func _can_request_bridge_tts_fallback() -> bool:
	if pending_agent_fallback_text.is_empty():
		return false
	if not bridge_available or not bridge_tts_available:
		return false
	if bridge_tts_fallback_request == null:
		return false
	return bridge_tts_fallback_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED

func _request_bridge_tts_fallback(text: String) -> void:
	if bridge_tts_fallback_request == null:
		return
	var payload := JSON.stringify({
		"user_text": "",
		"assistant_text": text,
		"command_id": "sudo_ai_fallback",
		"context": "fallback_agent_audio",
	})
	var err := bridge_tts_fallback_request.request(
		"%s/command" % bridge_base_url,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		payload
	)
	if err != OK:
		pending_agent_fallback_text = ""
		_resume_after_missing_audio()

func _resume_after_missing_audio() -> void:
	if not hot_word_active or not gameplay_voice_enabled:
		is_speaking = false
		return
	is_speaking = false
	if activation_greeting_in_progress:
		_finish_activation_greeting(true)
		return
	if mic_active:
		silence_timer = SILENCE_TIMEOUT_SECONDS
		_set_state(AgentState.LISTENING)
	else:
		_set_state(AgentState.CONNECTED)

func _variant_to_int(value: Variant, default_value: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return floori(float(value))
		TYPE_STRING:
			var text := str(value).strip_edges()
			return text.to_int() if not text.is_empty() else default_value
		TYPE_BOOL:
			return 1 if bool(value) else 0
		_:
			return default_value

func _set_state(new_state: AgentState) -> void:
	_set_state_with_label(new_state, "")

func _set_state_with_label(new_state: AgentState, label_override: String) -> void:
	var state_changed := state != new_state or display_state_override != label_override
	state = new_state
	display_state_override = label_override
	_sync_ios_audio_session_mode()
	if state_changed:
		EventBus.sudo_ai_state_changed.emit(get_state_label())

func _sync_ios_audio_session_mode() -> void:
	if not _uses_remote_bridge():
		return
	var desired_mode := _get_ios_audio_session_mode()
	if desired_mode == ios_audio_session_mode:
		return
	ios_audio_session_mode = desired_mode
	var absolute_path := ProjectSettings.globalize_path(IOS_AUDIO_SESSION_COMMAND_PATH)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"mode": desired_mode,
		"updated_at": Time.get_ticks_msec(),
	}))

func _get_ios_audio_session_mode() -> String:
	if gameplay_voice_enabled and _is_current_scene_gameplay():
		return "voice"
	if hot_word_active or mic_active or activation_greeting_in_progress:
		return "voice"
	match state:
		AgentState.CONNECTING, AgentState.CONNECTED, AgentState.GREETING, AgentState.LISTENING, AgentState.SPEAKING:
			return "voice"
		_:
			return "playback"

func _uses_remote_bridge() -> bool:
	return OS.get_name() == "iOS"

func _should_keep_agent_live() -> bool:
	return ALWAYS_LISTEN_IN_GAMEPLAY and gameplay_voice_enabled and _is_current_scene_gameplay()

func _should_use_udp_wake_events() -> bool:
	return not _uses_remote_bridge()

func _should_request_wake_listener() -> bool:
	return true

func _resolve_bridge_base_url() -> String:
	if not _uses_remote_bridge():
		return BRIDGE_BASE_URL
	var configured := str(ProjectSettings.get_setting(IOS_BRIDGE_BASE_URL_SETTING, DEFAULT_IOS_BRIDGE_BASE_URL)).strip_edges()
	if configured.is_empty():
		return DEFAULT_IOS_BRIDGE_BASE_URL
	return configured
