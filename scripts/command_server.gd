class_name CommandServerSingleton
extends Node

const PORT: int = 4242
var udp_server: UDPServer
var active_peers: Array[PacketPeerUDP] = []

func _ready() -> void:
	udp_server = UDPServer.new()
	if udp_server.listen(PORT) != OK:
		push_error("CommandServer: Failed to listen on port " + str(PORT))
	else:
		print("CommandServer: Listening for Council AI on UDP port " + str(PORT))

func _process(_delta: float) -> void:
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
