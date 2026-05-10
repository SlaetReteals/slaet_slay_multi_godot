extends Node

## Use ResourceSaver instead of JSON for persistence
const SAVE_PATH: String = "user://server_player_data.tres"

@export var save_data: PlayerSaveData # Custom Resource class

func _ready() -> void:
	_load_save_file()

func save() -> void:
	# SERVER AUTHORITY: Critical game data must only be saved by the Server
	if not multiplayer.is_server():
		return
		
	var error: Error = ResourceSaver.save(save_data, SAVE_PATH)
	if error != OK:
		push_error("SaveManager: Failed to save data.")

func _load_save_file() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		save_data = load(SAVE_PATH) as PlayerSaveData
	else:
		save_data = PlayerSaveData.new() # Create default if missing
