class_name VoiceAlertServiceSingleton
extends Node

const ALERT_LINES := {
	"oxygen": "Warning. Oxygen reserves below twenty five percent.",
	"suit_power": "Warning. Suit power below twenty five percent.",
	"temperature_resistance": "Warning. Thermal shielding below twenty five percent.",
}

func _ready() -> void:
	EventBus.resource_threshold_crossed.connect(_on_resource_threshold_crossed)

func speak(event_id: String, text: String) -> void:
	print("VoiceAlertService[%s]: %s" % [event_id, text])
	EventBus.push_mission_log("[VOICE] %s" % text)

func _on_resource_threshold_crossed(resource_name: String, value: float) -> void:
	var _ignored := value
	var alert_text := str(ALERT_LINES.get(resource_name, "Warning. Suit resources critical."))
	speak("%s_low" % resource_name, alert_text)
