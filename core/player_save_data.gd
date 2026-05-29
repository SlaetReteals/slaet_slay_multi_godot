extends Resource
class_name PlayerSaveData

# --- IDENTIFICATION ---
@export var peer_id: int = 0

# --- PROGRESSION & META-DATA ---
# Critical game data (e.g., progression, total currency, wave completion) MUST only be saved by the Server to prevent cheating.
@export var highest_wave_completed: int = 0
@export var total_currency: int = 0

# --- CURRENT SESSION STATE ---
@export var current_health: int = 100
@export var current_experience: int = 0
@export var current_level: int = 1

# --- TOWER DEFENSE DATA ---
# Arrays can easily be exported to save unlocked items or loadouts
@export var unlocked_towers: Array[String] = []

# You can also add constructor parameters if you want to initialize data cleanly
func _init(p_peer_id: int = 0) -> void:
	peer_id = p_peer_id
