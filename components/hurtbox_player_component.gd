class_name HurtboxPlayerComponent
extends Area2D

signal hit

@export var health_component: HealthComponent

func _ready() -> void:
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)

func _on_body_entered(body: Node2D) -> void:
	if not is_instance_valid(health_component):
		return

	var dmg: float = 0.0
	var dmg_type: String = "basic"
	if "damage" in body:
		dmg = float(body.damage)
	if "damage_type" in body:
		dmg_type = str(body.damage_type)

	if dmg <= 0.0:
		return

	_apply_damage_to_player(dmg, dmg_type)

func _on_area_entered(area: Area2D) -> void:
	if not is_instance_valid(health_component):
		return

	if area is HitboxComponent:
		var hitbox: HitboxComponent = area as HitboxComponent
		_apply_damage_to_player(hitbox.damage, hitbox.damage_type)
		hitbox.register_hit(owner)

func _apply_damage_to_player(amount: float, type: String) -> void:
	if owner and owner.has_method("apply_damage"):
		owner.apply_damage(amount, type)
	elif health_component:
		health_component.damage(amount)
	
	_rpc_execute_visual_hit.rpc(amount)
	
@rpc("any_peer", "call_local", "reliable")
func _rpc_execute_visual_hit(damage_amount: float) -> void:
	hit.emit()
	VisualEffectsManager.show_damage(damage_amount, global_position)
