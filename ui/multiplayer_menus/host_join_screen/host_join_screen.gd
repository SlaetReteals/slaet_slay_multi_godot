extends Control

@onready var host_button: Button = $BoxContainer/HBoxContainer/HostButton
@onready var serverscan_button: Button = $BoxContainer/HBoxContainer/VBoxContainer/ServerScanButton
@onready var server_ip: Button = $BoxContainer/HBoxContainer/VBoxContainer/Server
@onready var scan_timeout: Timer = $ScanTimeout
#@onready var server_list: VBoxContainer = $BoxContainer/HBoxContainer/VBoxContainer/ServerList
func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	serverscan_button.pressed.connect(_on_scan_pressed)
		# Listen for the new discovery signal
	NetworkManager.server_discovered.connect(_on_server_discovered)
	
	multiplayer.peer_connected.connect(_on_network_peer_connected)
	multiplayer.peer_disconnected.connect(_on_network_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connection_success)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	LogManager.info("on_host_pressed", "Hosting game on port " + str(NetworkManager.PORT) + "...")
	if NetworkManager.host_game():
		LogManager.info("on_host_pressed", "Host successful. Local Peer ID: " + str(multiplayer.get_unique_id()))
		_go_to_lobby()
	else:
		LogManager.error("on_host_pressed", "Host failed! Check port.")

func _on_scan_pressed() -> void:
	LogManager.info("on_scan_pressed", "Scanning local network...")
	
	## --- Debug Popup ---
	#var debug_dialog: AcceptDialog = AcceptDialog.new()
	#debug_dialog.title = "Debug: LAN Scan"
	#debug_dialog.dialog_text = "Initiating UDP Broadcast...\nTarget Port: " + str(NetworkManager.PORT) + "\nClearing cached UI elements."
	#
	## Add to the tree and display
	#add_child(debug_dialog)
	#debug_dialog.popup_centered()
	#
	## Ensure the node frees itself when closed to prevent memory leaks
	#debug_dialog.confirmed.connect(debug_dialog.queue_free)
	#debug_dialog.canceled.connect(debug_dialog.queue_free)
	## -------------------
	
	# Clear out any old buttons from previous scans
#	for child: Node in server_list.get_children():
#		child.queue_free()
	server_ip.text = "Scanning..."
	NetworkManager.scan_local_network()
	scan_timeout.start()
	
func _on_server_discovered(ip: String) -> void:
	LogManager.info("on_server_discovered", "Discovered host at: " + ip)
	
	server_ip.text = ip
	server_ip.pressed.connect(_on_join_server_pressed.bind(ip))
	
	# Create a new button for this specific server
	#var btn: Button = Button.new()
	#btn.text = "Join Server: " + ip
	
	# .bind(ip) passes the specific string to the function when pressed
	#btn.pressed.connect(_on_join_server_pressed.bind(ip))
#	server_list.add_child(btn)

func _on_join_server_pressed(ip: String) -> void:
	LogManager.info("on_join_server_pressed","Joining " + ip + "...")
	NetworkManager.stop_scanning() # Stop polling UDP now that we chose a target
	NetworkManager.join_game(ip)

# --- Network Logging Callbacks ---

func _on_network_peer_connected(id: int) -> void:
	LogManager.info("HOSTJOINSCREEN", "Remote peer connected! ID: " + str(id))

func _on_network_peer_disconnected(id: int) -> void:
	LogManager.info("HOSTJOINSCREEN", "Peer disconnected: " + str(id))

func _on_connection_success() -> void:
	LogManager.info("HOSTJOINSCREEN", "Successfully connected to the server!")
	_go_to_lobby()

func _on_connection_failed() -> void:
	LogManager.info("HOSTJOINSCREEN", "Connection failed.")

# --- Helpers ---

func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://levels/00_level_lobby/00_level_template.tscn")

func _on_scan_timeout_timeout() -> void:
	if server_ip.text == "Scanning...":
		LogManager.info("scan_timeout","No Server Found")
		server_ip.text = "No Server Found"
		NetworkManager.stop_scanning()
	else:
		LogManager.info("scan_timeout","Server Found: " + str(server_ip.text))
		NetworkManager.stop_scanning()
