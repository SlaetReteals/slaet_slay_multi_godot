class_name HealthComponent
extends Node

# --- Signals ---
# Updated names to match the BaseEnemy connection we established earlier
signal on_health_depleted
signal on_health_changed(new_health: float)
signal on_health_decreased(damage_taken: float)

# --- Exported State Variables ---
@export var max_health: float = 10.0

# CRITICAL: This MUST be exported so Netfox's StateSynchronizer can replicate it
@export var current_health: float = 10.0

func _ready() -> void:
	# Only the server should establish the canonical starting health
	if multiplayer.is_server():
		current_health = max_health

func damage(damage_amount: float) -> void:
	# SECURITY: Only the Server validates hits and modifies health
	if not multiplayer.is_server():
		return
		
	var actual_damage: float = max(damage_amount, 0.0)
	current_health = clamp(current_health - actual_damage, 0.0, max_health)
	
	on_health_changed.emit(current_health)
	
	if actual_damage > 0.0:
		on_health_decreased.emit(actual_damage)
		
	_check_death()

func heal(heal_amount: float) -> void:
	# SECURITY: Only the Server validates healing
	if not multiplayer.is_server():
		return
		
	var actual_heal: float = max(heal_amount, 0.0)
	current_health = clamp(current_health + actual_heal, 0.0, max_health)
	on_health_changed.emit(current_health)

func get_health_percent() -> float:
	if max_health <= 0.0: 
		return 0.0
	return clamp(current_health / max_health, 0.0, 1.0)

func _check_death() -> void:
	if current_health <= 0.0:
		on_health_depleted.emit()
		# STOP! Do NOT call `owner.queue_free()` here.
		# The root BaseEnemy script must listen to this signal, 
		# send the "die" event to the State Chart, and let the State Chart handle visuals and cleanup.
