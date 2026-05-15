class_name SpawnPatternComponent
extends Node2D

@export var spawn_pattern_id: String = "1"

@onready var bullet_spawn_point: Node2D = $SpawnPoint

func trigger_attack_sequence() -> void:
	if multiplayer.is_server():
		_rpc_execute_local_spawn.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_execute_local_spawn() -> void:
	Spawning.spawn(bullet_spawn_point, spawn_pattern_id)
