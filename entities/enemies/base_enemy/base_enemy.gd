# TemplateVersion: 1.4.0
class_name BaseEnemy
extends CharacterBody2D

@export var speed: float = 100.0
var target_node: Node2D = null

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server(): return
	if target_node == null or not is_instance_valid(target_node):
		var players = get_tree().get_nodes_in_group("players")
		if players.size() > 0: target_node = players[0] 
		return
	var direction = (target_node.global_position - global_position).normalized()
	rotation = direction.angle()
	velocity = direction * speed
	move_and_slide()
