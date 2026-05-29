extends Control

@onready var host_button: Button = $BoxContainer/HBoxContainer/HostButton
@onready var serverscan_button: Button = $BoxContainer/HBoxContainer/VBoxContainer/ServerScanButton
@onready var server_ip: Button = $BoxContainer/HBoxContainer/VBoxContainer/Server
@onready var scan_timeout: Timer = $ScanTimeout
func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	serverscan_button.pressed.connect(_on_scan_pressed)
		# Listen for the new discovery signal
	NetworkManager.server_discovered.connect(_on_server_discovered)
	
	multiplayer.peer_connected.connect(_on_network_peer_connected)
	multiplayer.peer_disconnected.connect(_on_network_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connection_success)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
# ... inside your host_join_screen.gd ...

func _on_host_pressed() -> void:
	LogManager.info("on_host_pressed", "Hosting game on port " + str(NetworkManager.PORT) + "...")
	if NetworkManager.host_game():
		LogManager.info("on_host_pressed", "Host successful. Local Peer ID: " + str(multiplayer.get_unique_id()))
		
		# We are the server, so we load the lobby.
		# Ensure you have a way to reference the Main node instance here.
		# Example using SceneTree:
		var main_node: Main = get_tree().root.get_node("Main") 
		if main_node:
			main_node.change_level("res://levels/01_level_lobby/01_level_lobby.tscn")
	else:
		LogManager.error("on_host_pressed", "Host failed! Check port.")

func _on_connection_success() -> void:
	LogManager.info("HOSTJOINSCREEN", "Successfully connected to the server!")
	# DO NOTHING ELSE HERE! 
	# Godot's MultiplayerSpawner will automatically spawn the lobby 
	# into the client's LevelContainer.

func _on_scan_pressed() -> void:
	LogManager.info("on_scan_pressed", "Scanning local network...")

	server_ip.text = "Scanning..."
	NetworkManager.scan_local_network()
	scan_timeout.start()
	
func _on_server_discovered(ip: String) -> void:
	LogManager.info("on_server_discovered", "Discovered host at: " + ip)
	
	server_ip.text = ip
	server_ip.pressed.connect(_on_join_server_pressed.bind(ip))

func _on_join_server_pressed(ip: String) -> void:
	LogManager.info("on_join_server_pressed","Joining " + ip + "...")
	NetworkManager.stop_scanning() # Stop polling UDP now that we chose a target
	NetworkManager.join_game(ip)

# --- Network Logging Callbacks ---

func _on_network_peer_connected(id: int) -> void:
	LogManager.info("HOSTJOINSCREEN", "Remote peer connected! ID: " + str(id))

func _on_network_peer_disconnected(id: int) -> void:
	LogManager.info("HOSTJOINSCREEN", "Peer disconnected: " + str(id))

#func _on_connection_success() -> void:
	#LogManager.info("HOSTJOINSCREEN", "Successfully connected to the server!")
	#_go_to_lobby()

func _on_connection_failed() -> void:
	LogManager.info("HOSTJOINSCREEN", "Connection failed.")

# --- Helpers ---

func _on_scan_timeout_timeout() -> void:
	if server_ip.text == "Scanning...":
		LogManager.info("scan_timeout","No Server Found")
		server_ip.text = "No Server Found"
		NetworkManager.stop_scanning()
	else:
		LogManager.info("scan_timeout","Server Found: " + str(server_ip.text))
		NetworkManager.stop_scanning()
