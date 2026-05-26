class_name HurtboxPlayerComponent
extends Area2D

signal hit

@export var health_component: HealthComponent

func _ready() -> void:
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: CharacterBody2D) -> void:
	var damage: int = body.damage
	var damage_type: String = body.damage_type
	var modified_damage: int = 0
	if not is_instance_valid(health_component):
		return

	## Execute discrete routing via native string namespace matching
	if damage_type == "basic":
		modified_damage = 1 * damage
			
	if owner and owner.has_method("apply_damage"):
		owner.apply_damage(modified_damage)
	
	if modified_damage == null:
		return
	_rpc_execute_visual_hit.rpc(modified_damage)
	
@rpc("any_peer", "call_local", "reliable")
func _rpc_execute_visual_hit(damage_amount: float) -> void:
	hit.emit()
	VisualEffectsManager.show_damage(damage_amount, global_position)
