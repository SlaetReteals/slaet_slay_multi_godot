class_name HitboxComponent
extends Area2D

func _ready() -> void:
	# Enforce deterministic hit registration strictly on the host peer
	if multiplayer.is_server():
		area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	# Duck-type validation: Interrogate the physics node for BuH metadata
	if "props" in area and area.props is Dictionary:
		var bullet_id: String = area.props.get("__ID__", "")
		_resolve_bullet_payload(bullet_id, area)

func _resolve_bullet_payload(bullet_id: String, bullet_node: Area2D) -> void:
	# Baseline kinematic payload
	var base_damage: float = 10.0
	var element: String = "physical"
	
	# Execute discrete routing based on the BuH serialization ID
	match bullet_id:
		"bullet_fire":
			base_damage = 15.0
			element = "fire"
		"bullet_ice":
			base_damage = 12.0
			element = "ice"
		"bullet_earth":
			base_damage = 30.0
			element = "earth"
		"bullet_bomb":
			base_damage = 50.0
			element = "explosive"
			
	# Transmit the payload matrix upward to the BaseEnemy facade
	if owner and owner.has_method("apply_damage"):
		owner.apply_damage(base_damage, element)
		
	# Synchronous garbage collection of the projectile
	if bullet_node.has_method("queue_free"):
		bullet_node.queue_free()
