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
		child.queue_free()
	
	call_deferred("spawn_level",scene_path)
		
		# The MultiplayerSpawner will automatically replicate this 
		# level_instance to all connected clients.
func spawn_level(scene_path):
	var new_scene: PackedScene = load(scene_path)
	if new_scene:
		var level_instance = new_scene.instantiate()
		level_container.add_child(level_instance)
