class_name GameStateSingleton
extends Node

const BASE_MAX_OXYGEN: float = 100.0
const BASE_MAX_SUIT_POWER: float = 100.0
const BASE_MAX_TEMPERATURE_RESISTANCE: float = 100.0
const OXYGEN_CAPACITY_BONUS_PER_LEVEL: float = 15.0
const DRAIN_REDUCTION_PER_LEVEL: float = 0.12
const MAX_UPGRADE_LEVEL: int = 3
const UPGRADE_COSTS := {
	"oxygen_capacity": [3, 5, 8],
	"suit_durability": [3, 5, 8],
}
const SAVE_PATH: String = "user://savegame.json"

var salvage_cubes: int = 0
var upgrade_levels := {
	"oxygen_capacity": 0,
	"suit_durability": 0,
}
var entitlements := {
	"free": true,
	"pro": false,
	"mod": false,
}
var sol_day: int = 247
var clone_iteration: int = 14
var mission_clock_seconds: float = float((14 * 3600) + (37 * 60))
var storm_eta_seconds: float = float((4 * 3600) + (22 * 60))
var respawn_position: Vector3 = Vector3.ZERO
var respawn_yaw: float = 0.0

# Session stats for game over summary
var rocks_surveyed: int = 0
var drones_deployed: int = 0
var distance_walked: float = 0.0
var is_paused: bool = false
var basecamp_terminal_open: bool = false
var paywall_visible: bool = false
var paywall_context: String = ""

func _process(delta: float) -> void:
	mission_clock_seconds += delta
	storm_eta_seconds = max(storm_eta_seconds - (delta * 0.35), 0.0)

func save_game() -> void:
	var data := {
		"salvage_cubes": salvage_cubes,
		"upgrade_levels": upgrade_levels,
		"sol_day": sol_day,
		"clone_iteration": clone_iteration
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err == OK:
		var data = json.data
		if typeof(data) == TYPE_DICTIONARY:
			salvage_cubes = int(data.get("salvage_cubes", 0))
			if data.has("upgrade_levels") and typeof(data["upgrade_levels"]) == TYPE_DICTIONARY:
				upgrade_levels = data["upgrade_levels"]
			sol_day = int(data.get("sol_day", 247))
			clone_iteration = int(data.get("clone_iteration", 14))
			return true
	return false

func reset_game() -> void:
	salvage_cubes = 0
	upgrade_levels = {
		"oxygen_capacity": 0,
		"suit_durability": 0,
	}
	sol_day = 247
	clone_iteration = 1
	mission_clock_seconds = float((14 * 3600) + (37 * 60))
	storm_eta_seconds = float((4 * 3600) + (22 * 60))
	rocks_surveyed = 0
	drones_deployed = 0
	distance_walked = 0.0

func reset_session_stats() -> void:
	rocks_surveyed = 0
	drones_deployed = 0
	distance_walked = 0.0

func add_rock_surveyed() -> void:
	rocks_surveyed += 1

func add_drone_deployed() -> void:
	drones_deployed += 1

func add_distance(dist: float) -> void:
	distance_walked += dist

func set_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused

func add_salvage_cubes(amount: int) -> void:
	salvage_cubes = max(salvage_cubes + amount, 0)

func get_salvage_cubes() -> int:
	return salvage_cubes

func get_upgrade_levels() -> Dictionary:
	return upgrade_levels.duplicate(true)

func get_upgrade_cost(upgrade_id: String) -> int:
	var level := int(upgrade_levels.get(upgrade_id, 0))
	if level >= MAX_UPGRADE_LEVEL:
		return -1
	return int(UPGRADE_COSTS.get(upgrade_id, [0])[level])

func purchase_upgrade(upgrade_id: String) -> bool:
	var level := int(upgrade_levels.get(upgrade_id, 0))
	var cost := get_upgrade_cost(upgrade_id)
	if cost < 0:
		EventBus.push_mission_log("Upgrade ceiling reached for %s." % _get_upgrade_name(upgrade_id))
		return false
	if salvage_cubes < cost:
		EventBus.push_mission_log("Need %d salvage cubes for %s." % [cost, _get_upgrade_name(upgrade_id)])
		return false

	salvage_cubes -= cost
	upgrade_levels[upgrade_id] = level + 1
	EventBus.upgrade_purchased.emit(upgrade_id, int(upgrade_levels[upgrade_id]), salvage_cubes)
	EventBus.push_mission_log("%s upgraded to level %d." % [_get_upgrade_name(upgrade_id), int(upgrade_levels[upgrade_id])])
	save_game()
	return true

func get_max_oxygen() -> float:
	return BASE_MAX_OXYGEN + (float(upgrade_levels["oxygen_capacity"]) * OXYGEN_CAPACITY_BONUS_PER_LEVEL)

func get_max_suit_power() -> float:
	return BASE_MAX_SUIT_POWER

func get_max_temperature_resistance() -> float:
	return BASE_MAX_TEMPERATURE_RESISTANCE

func get_suit_drain_multiplier() -> float:
	return max(0.4, 1.0 - (float(upgrade_levels["suit_durability"]) * DRAIN_REDUCTION_PER_LEVEL))

func set_respawn_transform(position: Vector3, yaw: float) -> void:
	respawn_position = position
	respawn_yaw = yaw

func get_respawn_position() -> Vector3:
	return respawn_position

func get_respawn_yaw() -> float:
	return respawn_yaw

func open_basecamp_terminal() -> void:
	basecamp_terminal_open = true

func close_basecamp_terminal() -> void:
	basecamp_terminal_open = false

func is_basecamp_terminal_open() -> bool:
	return basecamp_terminal_open

func open_paywall(context: String) -> void:
	paywall_context = context
	paywall_visible = true

func close_paywall() -> void:
	paywall_visible = false
	paywall_context = ""

func is_paywall_visible() -> bool:
	return paywall_visible

func get_paywall_context() -> String:
	return paywall_context

func is_modal_open() -> bool:
	return basecamp_terminal_open or paywall_visible

func set_entitlement(tier_id: String, enabled: bool = true) -> void:
	if not entitlements.has(tier_id):
		return
	entitlements[tier_id] = enabled
	if tier_id == "mod" and enabled:
		entitlements["pro"] = true
	if tier_id == "pro" and not enabled and bool(entitlements["mod"]):
		entitlements["pro"] = true

func has_entitlement(entitlement_id: String) -> bool:
	return bool(entitlements.get(entitlement_id, false))

func get_entitlements() -> Dictionary:
	return entitlements.duplicate(true)

func get_sol_day() -> int:
	return sol_day

func get_clone_iteration() -> int:
	return clone_iteration

func advance_clone_iteration() -> void:
	clone_iteration += 1
	sol_day += 1
	mission_clock_seconds = float((14 * 3600) + (37 * 60))
	storm_eta_seconds = float((4 * 3600) + (22 * 60))
	save_game()

func get_mission_clock_label() -> String:
	return _format_clock(mission_clock_seconds)

func get_storm_eta_label() -> String:
	var total_seconds := int(round(storm_eta_seconds))
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	return "%dh %02dm" % [hours, minutes]

func _get_upgrade_name(upgrade_id: String) -> String:
	match upgrade_id:
		"oxygen_capacity":
			return "Oxygen Capacity"
		"suit_durability":
			return "Suit Durability"
		_:
			return upgrade_id.capitalize()

func _format_clock(total_seconds: float) -> String:
	var normalized_seconds := int(fposmod(total_seconds, 24.0 * 3600.0))
	var hours := normalized_seconds / 3600
	var minutes := (normalized_seconds % 3600) / 60
	var seconds := normalized_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
