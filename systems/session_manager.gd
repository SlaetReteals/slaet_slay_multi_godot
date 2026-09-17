extends Node

# Reference to the node where your MultiplayerSpawner drops players
@export var player_spawn_container: Node

func check_game_over_condition() -> void:
		
	var all_dead: bool = true
	var players: Array[Node] = player_spawn_container.get_children()
	LogManager.info('session manager', 'player '+str(multiplayer.get_unique_id())) 
	#if not players.is_empty():
		#LogManager.info('session manager', 'not players.is_empty') 
#
		#return
		
	for node in players:
		LogManager.info('session manager', 'node in players') 

		print(node.name)
		print(node._is_dead)
		var player: Player = node as Player
		if player != null and not player._is_dead:
			all_dead = false
			break # At least one player is still alive
			
	if all_dead:
		LogManager.info('session manager', 'all_dead') 

		_execute_game_over()
		
@rpc('authority','call_local','reliable')
func _execute_game_over() -> void:
	if not multiplayer.is_server() or player_spawn_container == null:
		return
	# Optional: Delay the scene change so players can see their demise
	await get_tree().create_timer(2.0).timeout
	
	# Server changes the scene, Netfox/MultiplayerAPI will sync this to clients automatically
	var main_node: Main = get_tree().get_first_node_in_group(&"main") as Main
	if not main_node and get_tree().root.has_node("Main"):
		main_node = get_tree().root.get_node("Main") as Main
	if main_node:
		main_node.change_level("res://levels/01_level_lobby/01_level_lobby.tscn")
