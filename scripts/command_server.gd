class_name CommandServerSingleton
extends Node

const DEFAULT_PREFERRED_PORT: int = 4242
const MAX_PORT_ATTEMPTS: int = 8
const RESERVED_PORTS := {
	4245: true,
}

var udp_server: UDPServer
var active_peers: Array[PacketPeerUDP] = []
var listening_port: int = -1

func _ready() -> void:
	udp_server = UDPServer.new()
	var preferred_port := _get_preferred_port()
	for port_offset in range(MAX_PORT_ATTEMPTS):
		var candidate_port := preferred_port + port_offset
		if RESERVED_PORTS.has(candidate_port):
			continue
		if udp_server.listen(candidate_port) == OK:
			listening_port = candidate_port
			break
	if listening_port == -1:
		push_warning("CommandServer: Could not bind any UDP port near %d. External command input disabled for this run." % preferred_port)
	else:
		print("CommandServer: Listening for Council AI on UDP port %d" % listening_port)

func _process(_delta: float) -> void:
	if listening_port == -1:
		return
	udp_server.poll()
	if udp_server.is_connection_available():
		var peer: PacketPeerUDP = udp_server.take_connection()
		active_peers.append(peer)
		print("CommandServer: Council peer connected from %s:%s" % [peer.get_packet_ip(), peer.get_packet_port()])
	
	for peer in active_peers:
		if peer.get_available_packet_count() > 0:
			var packet := peer.get_packet()
			var data_string := packet.get_string_from_utf8()
			_parse_command(data_string)

func _parse_command(data: String) -> void:
	var json := JSON.new()
	var error := json.parse(data)
	if error == OK:
		var result = json.data
		if result is Dictionary and result.has("command"):
			var cmd: String = result["command"]
			var params: Dictionary = result.get("parameters", {})
			print("CommandServer: Parsed command -> ", cmd, " | Params: ", params)
			EventBus.player_command_received.emit(cmd, params)
		else:
			push_warning("CommandServer: Invalid JSON payload structure.")
	else:
		push_warning("CommandServer: Failed to parse JSON. Error: " + json.get_error_message())

func _get_preferred_port() -> int:
	var env_port_text := OS.get_environment("COMMAND_SERVER_PORT").strip_edges()
	if not env_port_text.is_empty():
		var env_port := env_port_text.to_int()
		if env_port > 0 and env_port <= 65535:
			return env_port
	return DEFAULT_PREFERRED_PORT
