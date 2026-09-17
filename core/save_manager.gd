extends Node

# Define a directory to hold all player saves, rather than a single file
const SAVE_DIR: String = "user://player_saves/"

const SAVE_PATH: String = "user://server_player_data.tres"

@export var save_data: PlayerSaveData

func _ready() -> void:
	# Ensure the save directory exists when the game boots
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
	_load_save_file()

func save() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		if not multiplayer.is_server():
			return
			
	if save_data == null:
		save_data = PlayerSaveData.new()
		
	var error: Error = ResourceSaver.save(save_data, SAVE_PATH)
	if error != OK:
		push_error("SaveManager: Failed to save data.")

func _load_save_file() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		save_data = load(SAVE_PATH) as PlayerSaveData
	if save_data == null:
		save_data = PlayerSaveData.new()

# --- SAVE LOGIC ---

func save_player_data(peer_id: int, data: PlayerSaveData) -> void:
	# SERVER AUTHORITY: Critical game data must only be saved by the Server
	if not multiplayer.is_server():
		return
		
	# Dynamically generate the path using the peer_id
	var save_path: String = SAVE_DIR + "player_" + str(peer_id) + ".tres"
	
	# ResourceSaver natively overwrites existing files at the path
	var error: Error = ResourceSaver.save(data, save_path)
	
	if error != OK:
		push_error("SaveManager: Failed to save data for peer ID: " + str(peer_id))

# --- LOAD LOGIC ---

func load_player_data(peer_id: int) -> PlayerSaveData:
	var save_path: String = SAVE_DIR + "player_" + str(peer_id) + ".tres"
	
	# If the file exists, load and return it
	if ResourceLoader.exists(save_path):
		return ResourceLoader.load(save_path) as PlayerSaveData
	
	# If no file exists (e.g., first time joining), generate a fresh data container
	var default_data: PlayerSaveData = PlayerSaveData.new()
	default_data.peer_id = peer_id
	return default_data

# --- BATCH UTILITIES ---

# A helper function to easily trigger saves for everyone before a scene change
func save_all_active_players(players_array: Array[Node]) -> void:
	if not multiplayer.is_server():
		return
		
	for player_node in players_array:
		var player: Player = player_node as Player
		if player == null:
			continue
			
		var peer_id: int = player.get_multiplayer_authority()
		
		# Instantiate a fresh resource and populate it from the player's current state
		var data: PlayerSaveData = PlayerSaveData.new()
		data.peer_id = peer_id
		
		# Populate your specific variables here
		# Example: data.current_health = player.health_component.current_health
		
		save_player_data(peer_id, data)
		LogManager.info('save manager', str(data.peer_id) + ' saved data')
