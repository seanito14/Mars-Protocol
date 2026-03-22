class_name MonetizationServiceSingleton
extends Node

const IOS_BRIDGE_COMMAND_PATH := "user://revenuecat_command.json"
const IOS_BRIDGE_STATE_PATH := "user://revenuecat_state.json"
const IOS_POLL_INTERVAL := 0.35
const IOS_ENTITLEMENT_ID := "pro"

const TIER_DEFINITIONS := {
	"free": {
		"label": "Free",
		"price": "bash",
		"description": "Base EVA kit with manual scavenging.",
		"entitlements": [],
	},
	"pro": {
		"label": "Pro",
		"price": "$4.99",
		"description": "Telemetry beacon scans for nearby high-tier debris.",
		"entitlements": ["pro"],
	},
	"mod": {
		"label": "Mod",
		"price": "$19.99",
		"description": "Pro telemetry plus future command automation unlocks.",
		"entitlements": ["pro", "mod"],
	},
}

var ios_poll_timer: float = 0.0
var ios_last_result_id: String = ""
var ios_last_setup_error: String = ""
var ios_last_pro_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if not _uses_ios_revenuecat():
		return
	ios_poll_timer += delta
	if ios_poll_timer < IOS_POLL_INTERVAL:
		return
	ios_poll_timer = 0.0
	_poll_ios_bridge_state()

func show_paywall(context: String = "") -> void:
	if _uses_ios_revenuecat():
		GameState.open_paywall(context)
		EventBus.paywall_requested.emit(context)
		EventBus.push_mission_log("Opening premium uplink...")
		_queue_ios_bridge_command("present_paywall", context)
		return
	GameState.open_paywall(context)
	EventBus.paywall_requested.emit(context)
	EventBus.push_mission_log("Premium telemetry uplink is locked. Review the field license tiers.")

func hide_paywall() -> void:
	GameState.close_paywall()

func purchase_tier(tier_id: String) -> bool:
	if _uses_ios_revenuecat():
		show_paywall("tier:%s" % tier_id)
		return true
	if not TIER_DEFINITIONS.has(tier_id):
		return false

	if tier_id == "free":
		hide_paywall()
		EventBus.push_mission_log("Continuing on the Free exploration tier.")
		return true

	for entitlement_id in TIER_DEFINITIONS[tier_id]["entitlements"]:
		GameState.set_entitlement(str(entitlement_id), true)

	hide_paywall()
	EventBus.push_mission_log("%s sandbox entitlement activated." % TIER_DEFINITIONS[tier_id]["label"])
	return true

func restore_purchases() -> bool:
	if _uses_ios_revenuecat():
		GameState.open_paywall("restore")
		EventBus.push_mission_log("Checking premium uplink restores...")
		_queue_ios_bridge_command("restore_purchases", "restore")
		return true
	var restored_any := false
	for entitlement_id in ["pro", "mod"]:
		if GameState.has_entitlement(entitlement_id):
			restored_any = true
	if restored_any:
		EventBus.push_mission_log("Mock purchase restore complete.")
	else:
		EventBus.push_mission_log("No sandbox purchases were found to restore.")
	return restored_any

func has_entitlement(entitlement_id: String) -> bool:
	return GameState.has_entitlement(entitlement_id)

func get_tier_definitions() -> Dictionary:
	return TIER_DEFINITIONS.duplicate(true)

func _uses_ios_revenuecat() -> bool:
	return OS.get_name() == "iOS"

func _queue_ios_bridge_command(action: String, context: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(IOS_BRIDGE_COMMAND_PATH)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		GameState.close_paywall()
		EventBus.push_mission_log("[RevenueCat] Failed to open the iOS purchase bridge.")
		return
	var payload := {
		"request_id": "%s-%s" % [str(Time.get_unix_time_from_system()), str(Time.get_ticks_msec())],
		"action": action,
		"context": context,
	}
	file.store_string(JSON.stringify(payload))

func _poll_ios_bridge_state() -> void:
	var absolute_path := ProjectSettings.globalize_path(IOS_BRIDGE_STATE_PATH)
	if not FileAccess.file_exists(absolute_path):
		return
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return
	var raw := file.get_as_text()
	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	_apply_ios_bridge_state(json.data as Dictionary)

func _apply_ios_bridge_state(payload: Dictionary) -> void:
	var setup_error := str(payload.get("setup_error", ""))
	if setup_error != ios_last_setup_error:
		ios_last_setup_error = setup_error
		if not setup_error.is_empty():
			EventBus.push_mission_log(_describe_ios_setup_error(setup_error))

	var pro_active := bool(payload.get("pro_active", false))
	if pro_active != ios_last_pro_active:
		ios_last_pro_active = pro_active
		GameState.set_entitlement(IOS_ENTITLEMENT_ID, pro_active)

	var last_result_id := str(payload.get("last_result_id", ""))
	if last_result_id.is_empty() or last_result_id == ios_last_result_id:
		return

	ios_last_result_id = last_result_id
	var result := str(payload.get("last_result", "none"))
	var message := str(payload.get("last_message", ""))
	match result:
		"purchased":
			GameState.set_entitlement(IOS_ENTITLEMENT_ID, true)
			GameState.close_paywall()
			EventBus.push_mission_log("Premium telemetry uplink activated.")
		"restored":
			GameState.set_entitlement(IOS_ENTITLEMENT_ID, true)
			GameState.close_paywall()
			EventBus.push_mission_log("Premium telemetry uplink restored.")
		"cancelled":
			GameState.close_paywall()
			EventBus.push_mission_log("Premium uplink review dismissed.")
		"not_presented":
			GameState.close_paywall()
			EventBus.push_mission_log(_describe_ios_bridge_message(message))
		"error":
			GameState.close_paywall()
			EventBus.push_mission_log(_describe_ios_bridge_message(message))

func _describe_ios_setup_error(code: String) -> String:
	match code:
		"secret_api_key_provided":
			return "[RevenueCat] Replace the Desktop token with the Apple public SDK key from Apps & Providers. Secret sk_ keys are not allowed in the app."
		"invalid_public_api_key":
			return "[RevenueCat] The Desktop RevenueCat token is not a valid Apple public SDK key."
		"missing_public_api_key":
			return "[RevenueCat] Add the Apple public SDK key to /Users/z/Desktop/revenuecatapi.txt to enable purchases."
		_:
			return "[RevenueCat] Setup error: %s" % code

func _describe_ios_bridge_message(code: String) -> String:
	match code:
		"no_current_offering":
			return "[RevenueCat] No current offering is available. Set Mars Offering as current in RevenueCat."
		"offerings_error":
			return "[RevenueCat] Could not reach the premium offering right now."
		"restore_error":
			return "[RevenueCat] Restore failed. Try again in a moment."
		"purchase_error":
			return "[RevenueCat] Purchase failed. Please try again."
		"missing_root_view_controller":
			return "[RevenueCat] The native paywall could not be presented."
		"unsupported_ios_version":
			return "[RevenueCat] Hosted paywalls require iOS 15 or newer."
		"invalid_command_payload":
			return "[RevenueCat] The purchase bridge received an invalid command."
		"unknown_command":
			return "[RevenueCat] The purchase bridge received an unknown command."
		_:
			if not code.is_empty():
				return "[RevenueCat] %s" % code.capitalize()
			return "[RevenueCat] The premium uplink could not be opened."
