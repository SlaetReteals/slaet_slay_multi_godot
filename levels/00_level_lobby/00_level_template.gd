extends Node2D

@export var _level_name: String = "Template"
@export var player_scene: PackedScene

@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawn_locations: Node2D = $SpawnLocations
@onready var local_client_hud: CanvasLayer = $LocalClientHUD # The strictly local UI layer
const INDICATOR_SCENE: PackedScene = preload("res://ui/hud/off_screen_indicator.tscn") 

var _available_spawn_points: Array[Node] = []
var _player_spawn_map: Dictionary = {}
var _has_local_player: bool = false

func _ready() -> void:
	if player_scene == null:
		LogManager.error(_level_name, "Player scene is not assigned!")
		return
		
	# 1. Custom spawn mapping
	player_spawner.spawn_function = _custom_spawn
	
	# 2. Listen for ANY player being spawned by the server
	player_spawner.spawned.connect(_on_player_spawned)
	
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		LogManager.error(_level_name, "No network peer found!")
		return
		
	if multiplayer.is_server():
		_available_spawn_points = spawn_locations.get_children()
		_available_spawn_points.shuffle()
		
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_spawn_player(multiplayer.get_unique_id())

func _on_peer_connected(id: int) -> void:
	_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	if _player_spawn_map.has(id):
		var marker: Marker2D = _player_spawn_map[id] as Marker2D
		_available_spawn_points.append(marker)
		_player_spawn_map.erase(id)
		
	var player_node: Node = get_node_or_null(str(id))
	if player_node != null:
		player_node.queue_free()

func _spawn_player(id: int) -> void:
	var target_pos: Vector2 = Vector2.ZERO
	
	if not _available_spawn_points.is_empty():
		var random_marker: Marker2D = _available_spawn_points.pop_back() as Marker2D
		target_pos = random_marker.global_position
		_player_spawn_map[id] = random_marker
	else:
		LogManager.warn("Template", "No spawn points left!")

	var spawn_data: Dictionary = {
		"id": id,
		"pos": target_pos
	}
	
	# 1. Capture the node that the Spawner creates
	var spawned_node: Node = player_spawner.spawn(spawn_data)
	
	# 2. MANUALLY trigger the UI logic for the Server/Host, 
	# since the 'spawned' signal won't fire locally for them.
	_on_player_spawned(spawned_node)

func _custom_spawn(data: Variant) -> Node:
	var player: Player = player_scene.instantiate() as Player
	player.name = str(data["id"])
	player.global_position = data["pos"]
	player.set_multiplayer_authority(data["id"])
	return player

# --- NEW: CLIENT-SIDE UI LOGIC ---

func _on_player_spawned(spawned_node: Node) -> void:
	var player_node: Player = spawned_node as Player
	if player_node == null:
		return
		
	if player_node.get_multiplayer_authority() == multiplayer.get_unique_id():
		# It's me! Wake up the UI and find everyone already playing.
		_has_local_player = true
		_setup_indicators_for_existing(player_node)
	else:
		# It's someone else! If I am already playing, track them.
		if _has_local_player:
			_create_indicator_for(player_node)

func _setup_indicators_for_existing(my_player: Player) -> void:
	# Use the group system to find all currently spawned players
	var all_players: Array[Node] = get_tree().get_nodes_in_group("players")
	
	for other_player in all_players:
		if other_player != my_player:
			_create_indicator_for(other_player as Player)

func _create_indicator_for(target_player: Player) -> void:
	if target_player == null:
		return
		
	# Instantiate using our preloaded constant
	var indicator: OffScreenIndicator = INDICATOR_SCENE.instantiate() as OffScreenIndicator
	indicator.target_player = target_player
	
	# Add it to the local CanvasLayer
	local_client_hud.add_child(indicator)
