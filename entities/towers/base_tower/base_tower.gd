# TemplateVersion: 1.4.0
class_name BaseTower
extends StaticBody2D

@export var fire_rate: float = 1.0 
var enemies_in_range: Array[Node2D] = []
var fire_timer: float = 0.0

func _physics_process(delta: float) -> void:
    if not multiplayer.is_server(): return
    fire_timer -= delta
    enemies_in_range = enemies_in_range.filter(func(e): return is_instance_valid(e))
    if enemies_in_range.size() > 0 and fire_timer <= 0:
        print("Tower firing at ", enemies_in_range[0].name)
        fire_timer = 1.0 / fire_rate

func _on_range_body_entered(body: Node2D) -> void:
    if body is BaseEnemy: enemies_in_range.append(body)

func _on_range_body_exited(body: Node2D) -> void:
    if body in enemies_in_range: enemies_in_range.erase(body)