extends Node

const PLAYER_CLASSES: Dictionary = {
	"mushroom": "res://entities/player/classes/mushroom.tres"
}

var _active_player_class: PlayerClass

func load_class_into_memory(file_path: String) -> void:
	# 1. Load the file
	# 2. Cast it as your specific custom resource type
	_active_player_class = load(file_path) as PlayerClass
	
	# Always good practice to check if the cast failed!
	if _active_player_class == null:
		printerr("ClassManager: Failed to load or cast to PlayerClass from ", file_path)
