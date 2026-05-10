# TemplateVersion: 1.4.0
extends Control

# Note: Escaped node path references for PowerShell Here-Strings
@onready var player_list: ItemList = get_node("MarginContainer/VBoxContainer/PlayerList")
@onready var start_button: Button = get_node("MarginContainer/VBoxContainer/StartButton")
@onready var status_label: Label = get_node("MarginContainer/VBoxContainer/StatusLabel")

const MAIN_LEVEL_PATH = "res://levels/map_01_graveyard/map_01_graveyard.tscn"

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	if multiplayer.is_server():
		status_label.text = "Hosting Game. Waiting for players..."
		start_button.visible = true
		start_button.pressed.connect(_on_start_button_pressed)
	else:
		status_label.text = "Connected! Waiting for host..."
		start_button.visible = false
		
	_update_player_list()

func _on_peer_connected(id: int) -> void: _update_player_list()
func _on_peer_disconnected(id: int) -> void: _update_player_list()
func _on_server_disconnected() -> void: get_tree().change_scene_to_file("res://ui/multiplayer_menus/host_join_screen/host_join_screen.tscn")

func _update_player_list() -> void:
	if player_list == null: return
	player_list.clear()
	var my_text = "Player " + str(multiplayer.get_unique_id()) + " (You)"
	if multiplayer.is_server(): my_text += " [HOST]"
	player_list.add_item(my_text)
	for peer_id in multiplayer.get_peers():
		player_list.add_item("Player " + str(peer_id))

func _on_start_button_pressed() -> void:
	if multiplayer.is_server(): _start_game.rpc()

@rpc("call_local", "authority", "reliable")
func _start_game() -> void:
	get_tree().change_scene_to_file(MAIN_LEVEL_PATH)
