class_name BaseTower
extends StaticBody2D

@export var attack_cooldown: float = 1.0
@export var projectile_scene: PackedScene = preload("res://components/combat/base_projectile.tscn")
@export var projectile_speed: float = 450.0
@export var damage: float = 20.0
@export var damage_type: String = "physical"

@onready var targeting_component: TargetingComponent = get_node_or_null("TargetingComponent")
@onready var health_component: HealthComponent = get_node_or_null("HealthComponent")
@onready var hurtbox_component: HurtboxComponent = get_node_or_null("HurtboxComponent")
@onready var shoot_timer: Timer = get_node_or_null("ShootTimer")

func _ready() -> void:
	add_to_group(&"towers")
	add_to_group(&"player_targets")
	
	if health_component and multiplayer.is_server():
		health_component.on_health_depleted.connect(_on_health_depleted)
		
	if shoot_timer and multiplayer.is_server():
		shoot_timer.wait_time = attack_cooldown
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)
		shoot_timer.start()

func _on_shoot_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
		
	var target: Node2D = null
	if targeting_component:
		target = targeting_component.acquire_target()
	if not is_instance_valid(target):
		target = _find_closest_enemy()
	if not is_instance_valid(target):
		return
		
	var azimuth: float = global_position.angle_to_point(target.global_position)
	_rpc_fire.rpc(azimuth)

func _find_closest_enemy() -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	var closest: Node2D = null
	var max_range: float = targeting_component.targeting_radius if targeting_component else 350.0
	var min_dist_sq: float = max_range * max_range
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Node2D:
			var d_sq: float = global_position.distance_squared_to(enemy.global_position)
			if d_sq <= min_dist_sq:
				min_dist_sq = d_sq
				closest = enemy
	return closest

@rpc("any_peer", "call_local", "reliable")
func _rpc_fire(azimuth: float) -> void:
	if projectile_scene:
		var proj: Node = projectile_scene.instantiate()
		if proj is Node2D:
			proj.global_position = global_position
			if proj.has_method("setup"):
				proj.setup(Vector2.RIGHT.rotated(azimuth), projectile_speed, damage, damage_type)
			elif "direction" in proj:
				proj.direction = Vector2.RIGHT.rotated(azimuth)
		var level: Node = get_tree().get_first_node_in_group(&"current_level")
		var target_parent: Node = level if level else get_tree().current_scene
		target_parent.add_child(proj)

func apply_damage(amount: float, _type: String = "physical") -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(health_component):
		health_component.damage(amount)

func _on_health_depleted() -> void:
	if not multiplayer.is_server():
		return
	_rpc_destroy.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_destroy() -> void:
	VisualEffectsManager.show_damage(0.0, global_position)
	queue_free()
