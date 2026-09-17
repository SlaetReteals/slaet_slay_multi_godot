class_name HitboxComponent
extends Area2D

signal hit_registered(target: Node)

@export var damage: float = 10.0
@export var damage_type: String = "physical"
@export var knockback_force: float = 0.0
@export var destroys_on_hit: bool = true
@export var pierce_count: int = 1 # 1 = single hit, >1 = pierces N targets, -1 = infinite pierce

var hits_remaining: int = 1

func _ready() -> void:
	hits_remaining = pierce_count

func register_hit(target: Node) -> void:
	hit_registered.emit(target)
	if pierce_count > 0:
		hits_remaining -= 1
		if hits_remaining <= 0 and destroys_on_hit:
			if owner:
				owner.queue_free()
			else:
				queue_free()
