class_name MonetizationServiceSingleton
extends Node

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

func show_paywall(context: String = "") -> void:
	GameState.open_paywall(context)
	EventBus.paywall_requested.emit(context)
	EventBus.push_mission_log("Premium telemetry uplink is locked. Review the field license tiers.")

func hide_paywall() -> void:
	GameState.close_paywall()

func purchase_tier(tier_id: String) -> bool:
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
