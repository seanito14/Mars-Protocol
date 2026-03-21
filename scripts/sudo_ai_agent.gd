class_name SudoAIAgentSingleton
extends Node

## SudoAI — ElevenLabs Conversational AI Agent (WebSocket)
##
## Connects directly to the ElevenLabs Conversational AI WebSocket endpoint
## for real-time, bidirectional voice conversation with the SudoAI agent.
## Auto-connects on game start and supports hot word activation.

const AGENT_ID: String = "agent_8501km8et6jgexcbzctqvrg3zmgs"
const WS_BASE_URL: String = "wss://api.elevenlabs.io/v1/convai/conversation?agent_id="
const RECONNECT_DELAY: float = 3.0

enum AgentState { DISCONNECTED, CONNECTING, CONNECTED, LISTENING, SPEAKING, ERROR }

var state: AgentState = AgentState.DISCONNECTED
var socket: WebSocketPeer = WebSocketPeer.new()
var conversation_id: String = ""
var is_speaking: bool = false
var pending_audio_chunks: Array[PackedByteArray] = []
var reconnect_timer: float = -1.0
var hot_word_active: bool = false

## Audio playback
var audio_player: AudioStreamPlayer = null
var audio_buffer: PackedByteArray = PackedByteArray()

## Microphone capture
var mic_effect: AudioEffectCapture = null
var mic_bus_index: int = -1
var mic_stream_player: AudioStreamPlayer = null
var mic_active: bool = false
var mic_send_timer: float = 0.0
const MIC_SEND_INTERVAL: float = 0.1  # Send mic audio every 100ms

## Volume tracking for overlay waveform
var current_input_volume: float = 0.0
var current_output_volume: float = 0.0

func _ready() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Master"
	add_child(audio_player)
	audio_player.finished.connect(_on_audio_finished)
	call_deferred("_deferred_setup")

func _deferred_setup() -> void:
	_setup_microphone()
	print("SudoAI: Agent service ready. Auto-connecting...")
	connect_agent()

func _setup_microphone() -> void:
	# Create a dedicated mic bus with a capture effect
	var mic_bus_name := "SudoAIMic"
	mic_bus_index = AudioServer.get_bus_index(mic_bus_name)
	if mic_bus_index == -1:
		AudioServer.add_bus()
		mic_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(mic_bus_index, mic_bus_name)
		AudioServer.set_bus_mute(mic_bus_index, true)  # Mute playback of raw mic
		var capture := AudioEffectCapture.new()
		AudioServer.add_bus_effect(mic_bus_index, capture)
		mic_effect = capture
	else:
		mic_effect = AudioServer.get_bus_effect(mic_bus_index, 0) as AudioEffectCapture

	# Create a mic stream player
	mic_stream_player = AudioStreamPlayer.new()
	var mic_stream := AudioStreamMicrophone.new()
	mic_stream_player.stream = mic_stream
	mic_stream_player.bus = "SudoAIMic"
	add_child(mic_stream_player)

func _process(delta: float) -> void:
	# Handle reconnect timer
	if reconnect_timer >= 0.0:
		reconnect_timer -= delta
		if reconnect_timer <= 0.0:
			reconnect_timer = -1.0
			print("SudoAI: Attempting reconnect...")
			connect_agent()
		return

	if state == AgentState.DISCONNECTED or state == AgentState.ERROR:
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
			# Update volume levels for overlay
			_update_volume_levels()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			var code := socket.get_close_code()
			var reason := socket.get_close_reason()
			print("SudoAI: WebSocket closed [%d] %s" % [code, reason])
			_set_state(AgentState.DISCONNECTED)
			EventBus.sudo_ai_disconnected.emit(reason)
			# Schedule reconnect
			reconnect_timer = RECONNECT_DELAY

## ── Public API ──────────────────────────────────────────────────────────

func connect_agent() -> void:
	if state != AgentState.DISCONNECTED and state != AgentState.ERROR:
		return
	var url := WS_BASE_URL + AGENT_ID
	print("SudoAI: Connecting to %s ..." % url)
	_set_state(AgentState.CONNECTING)
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(url)
	if err != OK:
		push_error("SudoAI: Failed to initiate WebSocket connection. Error: %d" % err)
		_set_state(AgentState.ERROR)
		reconnect_timer = RECONNECT_DELAY

func disconnect_agent() -> void:
	if state == AgentState.DISCONNECTED:
		return
	reconnect_timer = -1.0
	_stop_mic()
	socket.close(1000, "User requested disconnect")
	_set_state(AgentState.DISCONNECTED)
	EventBus.sudo_ai_disconnected.emit("user_disconnect")
	print("SudoAI: Disconnected.")

func start_listening() -> void:
	if state != AgentState.CONNECTED and state != AgentState.LISTENING:
		push_warning("SudoAI: Cannot listen — not connected (state: %s)." % get_state_label())
		return
	_start_mic()
	_set_state(AgentState.LISTENING)
	EventBus.sudo_ai_listening_started.emit()
	print("SudoAI: Microphone active — listening...")

func stop_listening() -> void:
	if state != AgentState.LISTENING:
		return
	_stop_mic()
	_set_state(AgentState.CONNECTED)
	EventBus.sudo_ai_listening_stopped.emit()
	print("SudoAI: Microphone stopped.")

func toggle_listening() -> void:
	if state == AgentState.LISTENING:
		stop_listening()
	else:
		start_listening()

func activate_hot_word() -> void:
	## Called when the hot word "Sudo" is detected in a transcript.
	if not hot_word_active:
		hot_word_active = true
		EventBus.sudo_ai_hot_word_activated.emit()
		print("SudoAI: Hot word 'Sudo' detected — activating voice mode.")
	if state == AgentState.CONNECTED:
		start_listening()

func deactivate_hot_word() -> void:
	hot_word_active = false
	if state == AgentState.LISTENING:
		stop_listening()
	EventBus.sudo_ai_overlay_dismissed.emit()

func send_text_message(text: String) -> void:
	if state < AgentState.CONNECTED:
		push_warning("SudoAI: Not connected, cannot send text.")
		return
	var payload := JSON.stringify({"user_audio_chunk": "", "text": text})
	socket.send_text(payload)
	EventBus.sudo_ai_user_transcript.emit(text)
	EventBus.push_mission_log("> Commander: %s" % text)

func send_contextual_update(context: String) -> void:
	if state < AgentState.CONNECTED:
		return
	var payload := JSON.stringify({"type": "contextual_update", "text": context})
	socket.send_text(payload)

func get_state_label() -> String:
	match state:
		AgentState.DISCONNECTED: return "OFFLINE"
		AgentState.CONNECTING: return "CONNECTING"
		AgentState.CONNECTED: return "CONNECTED"
		AgentState.LISTENING: return "LISTENING"
		AgentState.SPEAKING: return "SPEAKING"
		AgentState.ERROR: return "ERROR"
		_: return "UNKNOWN"

func is_connected_to_agent() -> bool:
	return state >= AgentState.CONNECTED

func is_agent_speaking() -> bool:
	return is_speaking

func get_input_volume() -> float:
	return current_input_volume

func get_output_volume() -> float:
	return current_output_volume

## ── Internal ────────────────────────────────────────────────────────────

func _on_connected() -> void:
	_set_state(AgentState.CONNECTED)
	print("SudoAI: WebSocket connected. Sending initiation data...")
	var init_payload := JSON.stringify({
		"type": "conversation_initiation_client_data",
	})
	socket.send_text(init_payload)
	EventBus.sudo_ai_connected.emit()

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
			conversation_id = str(data.get("conversation_initiation_metadata_event", {}).get("conversation_id", ""))
			print("SudoAI: Conversation started — ID: %s" % conversation_id)
			EventBus.push_mission_log("[SUDO AI] Conversation initiated.")

		"user_transcript":
			var event: Dictionary = data.get("user_transcription_event", {})
			var transcript: String = str(event.get("user_transcript", ""))
			if not transcript.is_empty():
				EventBus.sudo_ai_user_transcript.emit(transcript)
				EventBus.push_mission_log("> Commander: %s" % transcript)
				# Check for hot word
				if transcript.to_lower().contains("sudo") and not hot_word_active:
					activate_hot_word()

		"agent_response":
			var event: Dictionary = data.get("agent_response_event", {})
			var response: String = str(event.get("agent_response", ""))
			if not response.is_empty():
				is_speaking = true
				_set_state(AgentState.SPEAKING)
				EventBus.sudo_ai_agent_response.emit(response)
				EventBus.agent_response_received.emit(response)
				EventBus.push_mission_log("> SudoAI: %s" % response)

		"audio":
			var event: Dictionary = data.get("audio_event", {})
			var audio_b64: String = str(event.get("audio_base_64", ""))
			if not audio_b64.is_empty():
				var chunk := Marshalls.base64_to_raw(audio_b64)
				pending_audio_chunks.append(chunk)
				_try_play_audio()

		"ping":
			var event: Dictionary = data.get("ping_event", {})
			var event_id: int = int(event.get("event_id", 0))
			var ping_ms: int = int(event.get("ping_ms", 0))
			get_tree().create_timer(float(ping_ms) / 1000.0).timeout.connect(
				func(): _send_pong(event_id)
			)

		"interruption":
			audio_player.stop()
			pending_audio_chunks.clear()
			audio_buffer.clear()
			is_speaking = false
			if state == AgentState.SPEAKING:
				_set_state(AgentState.CONNECTED)

		"agent_response_correction":
			pass

		"internal_tentative_agent_response":
			pass

		_:
			pass

func _send_pong(event_id: int) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := JSON.stringify({
		"type": "pong",
		"event_id": event_id,
	})
	socket.send_text(payload)

func _try_play_audio() -> void:
	if audio_player.playing:
		return
	if pending_audio_chunks.is_empty():
		return
	var combined := PackedByteArray()
	for chunk in pending_audio_chunks:
		combined.append_array(chunk)
	pending_audio_chunks.clear()
	var stream := AudioStreamMP3.new()
	stream.data = combined
	audio_player.stream = stream
	audio_player.play()
	is_speaking = true

func _on_audio_finished() -> void:
	if pending_audio_chunks.size() > 0:
		_try_play_audio()
	else:
		is_speaking = false
		if state == AgentState.SPEAKING:
			_set_state(AgentState.CONNECTED)
		EventBus.sudo_ai_speech_finished.emit()

## ── Microphone ──────────────────────────────────────────────────────────

func _start_mic() -> void:
	if mic_active:
		return
	mic_active = true
	mic_send_timer = 0.0
	if mic_effect:
		mic_effect.clear_buffer()
	if mic_stream_player:
		mic_stream_player.play()

func _stop_mic() -> void:
	if not mic_active:
		return
	mic_active = false
	if mic_stream_player:
		mic_stream_player.stop()

func _send_mic_audio() -> void:
	if not mic_effect or not mic_active:
		return
	var frames_available := mic_effect.get_frames_available()
	if frames_available == 0:
		return
	var stereo_frames := mic_effect.get_buffer(frames_available)
	# Convert stereo Vector2 frames to mono 16-bit PCM
	var pcm := PackedByteArray()
	pcm.resize(stereo_frames.size() * 2)
	var rms_sum: float = 0.0
	for i in range(stereo_frames.size()):
		var mono_sample: float = (stereo_frames[i].x + stereo_frames[i].y) * 0.5
		rms_sum += mono_sample * mono_sample
		var sample_int: int = clampi(int(mono_sample * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, sample_int)
	# Update input volume for overlay
	current_input_volume = sqrt(rms_sum / max(float(stereo_frames.size()), 1.0))
	# Send as base64
	var b64 := Marshalls.raw_to_base64(pcm)
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var payload := JSON.stringify({"user_audio_chunk": b64})
		socket.send_text(payload)

func _update_volume_levels() -> void:
	# Decay volumes smoothly when not actively receiving data
	if not mic_active:
		current_input_volume = lerpf(current_input_volume, 0.0, 0.1)
	if not is_speaking:
		current_output_volume = lerpf(current_output_volume, 0.0, 0.1)
	elif audio_player.playing:
		# Approximate output volume from playback position
		current_output_volume = lerpf(current_output_volume, 0.7 + randf() * 0.3, 0.15)
	else:
		current_output_volume = lerpf(current_output_volume, 0.0, 0.1)

## ── State Management ────────────────────────────────────────────────────

func _set_state(new_state: AgentState) -> void:
	if state == new_state:
		return
	state = new_state
	EventBus.sudo_ai_state_changed.emit(get_state_label())
