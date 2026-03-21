class_name HeroVoiceService
extends Node

const DEFAULT_BRIDGE_URL: String = "http://127.0.0.1:8765"

@export var bridge_url: String = DEFAULT_BRIDGE_URL

var listening: bool = false
var conversation_state: String = "LOCAL DEMO"
var signed_url: String = ""
var contextual_update: String = ""
var http_ready: bool = false
var request_queue: Array[Dictionary] = []

@onready var bootstrap_request: HTTPRequest = HTTPRequest.new()
@onready var command_request: HTTPRequest = HTTPRequest.new()
@onready var audio_player: AudioStreamPlayer = AudioStreamPlayer.new()

func _ready() -> void:
	add_child(bootstrap_request)
	add_child(command_request)
	add_child(audio_player)
	bootstrap_request.request_completed.connect(_on_bootstrap_request_completed)
	command_request.request_completed.connect(_on_command_request_completed)
	audio_player.bus = "Master"
	call_deferred("request_signed_url")

func request_signed_url() -> void:
	if bootstrap_request.request("%s/signed-url" % bridge_url) != OK:
		_set_state("LOCAL DEMO")

func start_push_to_talk() -> void:
	if listening:
		return
	listening = true
	_set_state("LISTENING")
	EventBus.conversation_connected.emit("dictation")

func stop_push_to_talk(transcript: String = "") -> void:
	if not listening:
		return
	listening = false
	if transcript.strip_edges().is_empty():
		_set_state("READY" if http_ready else "LOCAL DEMO")
		return
	submit_command_text(transcript)

func toggle_listening() -> void:
	if listening:
		stop_push_to_talk("")
	else:
		start_push_to_talk()

func send_contextual_update(text: String) -> void:
	contextual_update = text

func is_listening() -> bool:
	return listening

func submit_command_text(text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return

	EventBus.transcript_received.emit(clean_text)
	var response_payload: Dictionary = _resolve_demo_command(clean_text)
	var payload := {
		"user_text": clean_text,
		"assistant_text": response_payload["response_text"],
		"command_id": response_payload["command_id"],
		"context": contextual_update,
	}
	request_queue.append(response_payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var request_error := command_request.request("%s/command" % bridge_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if request_error != OK:
		request_queue.pop_back()
		_emit_response(response_payload["response_text"], false, PackedByteArray())

func _resolve_demo_command(text: String) -> Dictionary:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("handle_voice_command"):
		return current_scene.call("handle_voice_command", text)
	return {
		"command_id": "unknown",
		"response_text": "Marvin here. Try scan, inspect wreckage, mark waypoint, or status.",
	}

func _on_bootstrap_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_set_state("LOCAL DEMO")
		return

	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_state("LOCAL DEMO")
		return

	signed_url = str(parsed.get("signed_url", ""))
	http_ready = true
	if signed_url.is_empty():
		_set_state("READY")
	else:
		_set_state("SIGNED URL READY")

func _on_command_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response_payload: Dictionary = {}
	if request_queue.size() > 0:
		response_payload = request_queue.pop_front()
	else:
		response_payload = {"response_text": "Marvin link recovered."}
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_emit_response(str(response_payload["response_text"]), false, PackedByteArray())
		return

	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_emit_response(str(response_payload["response_text"]), false, PackedByteArray())
		return

	var audio_base64: String = str(parsed.get("audio_base64", ""))
	var audio_bytes: PackedByteArray = Marshalls.base64_to_raw(audio_base64) if audio_base64 != "" else PackedByteArray()
	_emit_response(str(parsed.get("response_text", response_payload["response_text"])), bool(parsed.get("used_tts", false)), audio_bytes)

func _emit_response(response_text: String, used_tts: bool, audio_bytes: PackedByteArray) -> void:
	EventBus.agent_response_received.emit(response_text)
	EventBus.push_mission_log("> Marvin: %s" % response_text)
	_set_state("ELEVENLABS LIVE" if used_tts else "LOCAL DEMO")

	if audio_bytes.is_empty():
		return

	var stream := AudioStreamMP3.new()
	stream.data = audio_bytes
	audio_player.stream = stream
	audio_player.play()

func _set_state(state: String) -> void:
	conversation_state = state
	if state == "LISTENING":
		return
	if state == "LOCAL DEMO" or state == "READY" or state == "SIGNED URL READY" or state == "ELEVENLABS LIVE":
		EventBus.conversation_disconnected.emit(state)
