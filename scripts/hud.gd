class_name TacticalHUD
extends Control

@onready var o2_label: Label = %O2Value
@onready var temp_label: Label = %TempValue
@onready var coords_label: Label = %CoordsValue
@onready var mission_log: RichTextLabel = %MissionLog

# Drone telemetry unique names
@onready var drone_battery: Label = %DroneBattery
@onready var drone_alt: Label = %DroneAlt
@onready var drone_status: Label = %DroneStatus

var player: Player = null
var drone: ScoutDrone = null

func _ready() -> void:
	EventBus.player_command_received.connect(_on_mission_command)
	player = get_tree().get_first_node_in_group("player") as Player
	
	# Find drone
	var drones = get_tree().get_nodes_in_group("drone")
	if drones.size() > 0:
		drone = drones[0] as ScoutDrone
	
	mission_log.append_text("[color=orange][SYSTEM][/color] All systems nominal. Scout Link Active.\n")

func _process(_delta: float) -> void:
	if player:
		_update_player_telemetry()
	if drone:
		_update_drone_telemetry()

func _update_player_telemetry() -> void:
	var lat: float = player.global_position.x / 10.0
	var lon: float = player.global_position.z / 10.0
	coords_label.text = "LAT: %.4f | LON: %.4f" % [lat, lon]
	temp_label.text = "TEMP: -62°C"
	o2_label.text = "O2: 98.4%"

func _update_drone_telemetry() -> void:
	var alt: float = drone.global_position.y - player.global_position.y
	drone_alt.text = "ALT: %.1fm" % alt
	drone_battery.text = "BAT: 88%"
	drone_status.text = "MODE: AUTO-FOLLOW"

func _on_mission_command(command: String, params: Dictionary) -> void:
	var timestamp: String = Time.get_time_string_from_system()
	mission_log.append_text("[%s] [color=cyan]CMD:[/color] %s %s\n" % [timestamp, command.to_upper(), str(params)])
