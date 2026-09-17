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
		
	# 1. Inform all peers (host & clients) to mute synchronizers so no in-flight packets target the old level
	_rpc_prepare_level_change.rpc()
	
	# 2. Allow in-flight packets a brief window to arrive while the old level is still alive
	for i in range(3):
		await get_tree().physics_frame
		
	# 3. Clean up existing level
	for child in level_container.get_children():
		child.queue_free()

	await get_tree().process_frame
	await get_tree().physics_frame
	spawn_level(scene_path)

@rpc("authority", "call_local", "reliable")
func _rpc_prepare_level_change() -> void:
	for child in level_container.get_children():
		child.set_physics_process(false)
		child.set_process(false)
		for sync in child.find_children("*", "StateSynchronizer", true, false):
			sync.set_process(false)
			sync.set_physics_process(false)
			if "visibility_filter" in sync and sync.visibility_filter:
				sync.visibility_filter.default_visibility = false
				sync.visibility_filter.update_visibility()
		for rollback in child.find_children("*", "RollbackSynchronizer", true, false):
			rollback.process_mode = Node.PROCESS_MODE_DISABLED
			if "visibility_filter" in rollback and rollback.visibility_filter:
				rollback.visibility_filter.default_visibility = false
				rollback.visibility_filter.update_visibility()

		# The MultiplayerSpawner will automatically replicate this 
		# level_instance to all connected clients.
func spawn_level(scene_path):
	var new_scene: PackedScene = load(scene_path)
	if new_scene:
		var level_instance = new_scene.instantiate()
		level_container.add_child(level_instance)
