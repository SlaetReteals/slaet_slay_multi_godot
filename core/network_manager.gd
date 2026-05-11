extends Node

const PORT: int = 8765
const MAX_PLAYERS: int = 2
const BROADCAST_PORT: int = 8766
const DISCOVER_MSG: String = "DISCOVER"
const REPLY_MSG: String = "SERVER_HERE"

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal server_discovered(ip: String) 

var _udp_server: UDPServer
var _udp_client: PacketPeerUDP
var _discovered_ips: Array[String] = [] 

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(false) 

func host_game() -> bool:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(PORT, MAX_PLAYERS)
	
	if error != OK: 
		LogManager.error("NetworkManager", "Failed to host game on port " + str(PORT))
		return false
		
	multiplayer.multiplayer_peer = peer
	_start_udp_server()
	return true

func join_game(address: String) -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, PORT)
	
	if error != OK:
		LogManager.error("NetworkManager", "Failed to join game at " + address)
		return
		
	multiplayer.multiplayer_peer = peer

# --- LAN DISCOVERY LOGIC ---

func scan_local_network() -> void:
	_discovered_ips.clear() 
	_udp_client = PacketPeerUDP.new()
	_udp_client.set_broadcast_enabled(true)
	_udp_client.set_dest_address("255.255.255.255", BROADCAST_PORT)
	
	var packet: PackedByteArray = DISCOVER_MSG.to_utf8_buffer()
	_udp_client.put_packet(packet)
	set_process(true) 
	LogManager.info("NetworkManager","Scanning Started")

func stop_scanning() -> void:
	if _udp_client != null:
		_udp_client.close()
		_udp_client = null
		
	if _udp_server == null or not _udp_server.is_listening():
		set_process(false)
	
	LogManager.info("NetworkManager","Scanning Stopped")


func _start_udp_server() -> void:
	_udp_server = UDPServer.new()
	var error: Error = _udp_server.listen(BROADCAST_PORT)
	if error == OK:
		set_process(true)

func _process(_delta: float) -> void:
	if _udp_server != null and _udp_server.is_listening():
		_poll_udp_server()
	if _udp_client != null:
		_poll_udp_client()

func _poll_udp_server() -> void:
	_udp_server.poll()
	if _udp_server.is_connection_available():
		var peer: PacketPeerUDP = _udp_server.take_connection()
		var packet: PackedByteArray = peer.get_packet()
		
		if packet.get_string_from_utf8() == DISCOVER_MSG:
			var reply: PackedByteArray = REPLY_MSG.to_utf8_buffer()
			peer.put_packet(reply)

func _poll_udp_client() -> void:
	if _udp_client.get_available_packet_count() > 0:
		var packet: PackedByteArray = _udp_client.get_packet()
		
		if packet.get_string_from_utf8() == REPLY_MSG:
			var host_ip: String = _udp_client.get_packet_ip()
			
			if not _discovered_ips.has(host_ip):
				_discovered_ips.append(host_ip)
				server_discovered.emit(host_ip)

# --- INTERNAL SIGNAL ROUTING ---

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)

func _on_server_disconnected() -> void:
	server_disconnected.emit()
