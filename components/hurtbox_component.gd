class_name HurtboxComponent
extends Area2D

signal hit

@export var health_component: HealthComponent

func _ready() -> void:
	if multiplayer.is_server():
		area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if not is_instance_valid(health_component):
		return
	_resolve_shared_area_payload(area.name)

func _resolve_shared_area_payload(shared_area: String) -> void:
	var base_damage: float = 0.0
	
	# Execute discrete routing via native string namespace matching
	if "basic" in shared_area:
		base_damage = 15.0
	elif "bullet_ice" in shared_area:
		base_damage = 12.0
	elif "bullet_earth" in shared_area:
		base_damage = 30.0
	elif "bullet_bomb" in shared_area:
		base_damage = 50.0
		
	else:
		base_damage = 10
	if owner and owner.has_method("apply_damage"):
		owner.apply_damage(base_damage)
		_rpc_execute_visual_hit.rpc(base_damage)

@rpc("authority", "call_local", "reliable")
func _rpc_execute_visual_hit(damage_amount: float) -> void:
	hit.emit()
	VisualEffectsManager.show_damage(damage_amount, global_position)
