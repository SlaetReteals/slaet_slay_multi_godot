extends Node

# Reference to the node where your MultiplayerSpawner drops players
@export var player_spawn_container: Node2D

func check_game_over_condition() -> void:
		
	var all_dead: bool = true
	var players: Array[Node] = player_spawn_container.get_children()
	LogManager.info('session manager', 'player '+str(multiplayer.get_unique_id())) 
	if not players.is_empty():
		return
		
	for node in players:
		var player: Player = node as Player
		if player != null and not player._is_dead:
			all_dead = false
			break # At least one player is still alive
			
	if all_dead:
		_execute_game_over()
		
@rpc('authority','call_local','reliable')
func _execute_game_over() -> void:
	if not multiplayer.is_server() or player_spawn_container == null:
		return
	# Optional: Delay the scene change so players can see their demise
	await get_tree().create_timer(2.0).timeout
	
	# Server changes the scene, Netfox/MultiplayerAPI will sync this to clients automatically
	get_tree().change_scene_to_file("res://ui/multiplayer_menus/host_join_screen/host_join_screen.tscn")
