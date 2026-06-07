extends Node
class_name Main

@onready var level_container: Node = $LevelContainer
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

func _ready() -> void:
	# Ensure the spawner is watching the correct path
	spawner.spawn_path = level_container.get_path()

# Only the server should call this function
func change_level(scene_path: String) -> void:
	if not multiplayer.is_server():
		return
		
	# 1. Clean up existing level
	for child in level_container.get_children():
		var sync_node: Node = child.get_node_or_null("StateSynchronizer")
		
		if is_instance_valid(sync_node):
			# Deregister using the synchronizer as the configuration context
			get_tree().get_multiplayer().object_configuration_remove(child, sync_node)
			
			# Halt orphan tick evaluation
			sync_node.set_process(false)
			sync_node.set_physics_process(false)
			
		child.queue_free()

	await get_tree().process_frame
	spawn_level(scene_path)
		# The MultiplayerSpawner will automatically replicate this 
		# level_instance to all connected clients.
func spawn_level(scene_path):
	var new_scene: PackedScene = load(scene_path)
	if new_scene:
		var level_instance = new_scene.instantiate()
		level_container.add_child(level_instance)
