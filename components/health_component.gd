class_name HealthComponent
extends Node

signal on_health_depleted
signal on_health_changed(new_health: float)
signal on_health_decreased(damage_taken: float)

@export var max_health: float = 10.0
@export var current_health: float = 10.0

func _ready() -> void:
	if multiplayer.is_server():
		current_health = max_health

# Inject missing deterministic damage interface
func damage(damage_amount: float) -> void:
	
	if not multiplayer.is_server():
		return
		
	var actual_damage: float = max(damage_amount, 0.0)
	current_health = clamp(current_health - actual_damage, 0.0, max_health)
	
	on_health_changed.emit(current_health)
	if actual_damage > 0.0:
		on_health_decreased.emit(actual_damage)
		
	_check_death()

func heal(heal_amount: float) -> void:
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
