class_name WeaponComponent
extends Node2D

# --- Node References ---
@export var spawn_point: Node2D 

# --- BulletUpHell Configuration ---
@export var pattern_id: String = ""
@export var bullet_id: String = ""

# --- Combat Stats ---
@export var fire_rate: float = 0.5
var _cooldown_timer: float = 0.0

func _tick(delta: float, _tick_id: int) -> void:
	if not multiplayer.is_server():
		return
		
	_process_cooldown(delta)

func _process_cooldown(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

func trigger_attack() -> void:
	# The parent (e.g., the Player's State Chart) calls this function.
	# The component only validates its own cooldown before firing.
	if multiplayer.is_server() and _cooldown_timer <= 0.0:
		_cooldown_timer = fire_rate
		_rpc_execute_local_spawn.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_execute_local_spawn() -> void:
	# Safely passes the explicit Pattern and Bullet IDs to the singleton
	Spawning.spawn(spawn_point, pattern_id, bullet_id)
