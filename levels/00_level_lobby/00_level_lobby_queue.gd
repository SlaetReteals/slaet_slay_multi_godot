extends Node2D

@export var player_scene: PackedScene
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawn_locations: Node2D = $SpawnLocations

var _available_spawn_points: Array[Node] = []
var _player_spawn_map: Dictionary = {}

func _ready() -> void:
	if player_scene == null:
		LogManager.error("Lobby", "Player scene is not assigned!")
		return
		
	# 1. THE FIX: Tell the spawner to use our custom function instead of default behavior
	player_spawner.spawn_function = _custom_spawn
	
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		LogManager.error("Lobby", "No network peer found!")
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
		LogManager.warn("Lobby", "No spawn points left!")

	# 2. INSTEAD OF add_child(), WE CALL spawn() ON THE SPAWNER
	# This bundles the ID and Position into one secure network packet.
	var spawn_data: Dictionary = {
		"id": id,
		"pos": target_pos
	}
	player_spawner.spawn(spawn_data)

# 3. THIS FUNCTION RUNS ON EVERY COMPUTER (Server AND Clients) SIMULTANEOUSLY
func _custom_spawn(data: Variant) -> Node:
	var player: Player = player_scene.instantiate() as Player
	
	# We unpack the Dictionary we sent over the network
	player.name = str(data["id"])
	player.global_position = data["pos"]
	player.set_multiplayer_authority(data["id"])
	
	# We return the node, and the MultiplayerSpawner automatically adds it to the tree!
	return player
