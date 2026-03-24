class_name VoiceAlertServiceSingleton
extends Node

const ALERT_LINES := {
	"oxygen": "Warning. Oxygen reserves below twenty five percent.",
	"suit_power": "Warning. Suit power below twenty five percent.",
	"temperature_resistance": "Warning. Thermal shielding below twenty five percent.",
}

var _audio_player: AudioStreamPlayer
var _tts_request: HTTPRequest
var _request_queue: Array[Dictionary] = []
var _is_speaking: bool = false
var _bridge_url: String = "http://127.0.0.1:8765"

func _ready() -> void:
	var sudo_agent := get_node_or_null("/root/SudoAIAgent")
	if sudo_agent != null and RuntimeFeatures != null and RuntimeFeatures.is_sudo_ai_enabled():
		_bridge_url = str(sudo_agent.get("bridge_base_url"))
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"
	add_child(_audio_player)
	_audio_player.finished.connect(_on_audio_finished)

	_tts_request = HTTPRequest.new()
	add_child(_tts_request)
	_tts_request.request_completed.connect(_on_tts_request_completed)

	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.resource_threshold_crossed.connect(_on_resource_threshold_crossed)

func speak(event_id: String, text: String) -> void:
	print("VoiceAlertService[%s]: %s" % [event_id, text])
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.push_mission_log("[SYSTEM] %s" % text)
	if RuntimeFeatures == null or not RuntimeFeatures.is_voice_bridge_enabled():
		return
	_queue_tts(text)

func _queue_tts(text: String) -> void:
	_request_queue.append({"text": text})
	_process_queue()

func _process_queue() -> void:
	if _is_speaking or _tts_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or _request_queue.is_empty():
		return
	var item := _request_queue.pop_front() as Dictionary
	var text := str(item["text"])
	_is_speaking = true
	var payload := JSON.stringify({
		"user_text": "",
		"assistant_text": text,
		"command_id": "voice_alert",
		"context": "gameplay_alert",
	})
	var err := _tts_request.request(
		"%s/command" % _bridge_url,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		payload
	)
	if err != OK:
		_is_speaking = false
		_process_queue()

func _on_tts_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_is_speaking = false
		_process_queue()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_is_speaking = false
		_process_queue()
		return
	
	var data := parsed as Dictionary
	var audio_b64 := str(data.get("audio_base64", ""))
	if audio_b64.is_empty():
		_is_speaking = false
		_process_queue()
		return
		
	var audio_bytes := Marshalls.base64_to_raw(audio_b64)
	if audio_bytes.is_empty():
		_is_speaking = false
		_process_queue()
		return

	var stream := AudioStreamMP3.new()
	stream.data = audio_bytes
	_audio_player.stream = stream
	_audio_player.play()

func _on_audio_finished() -> void:
	_is_speaking = false
	_process_queue()

func _on_resource_threshold_crossed(resource_name: String, value: float) -> void:
	var _ignored := value
	var alert_text := str(ALERT_LINES.get(resource_name, "Warning. Suit resources critical."))
	speak("%s_low" % resource_name, alert_text)
