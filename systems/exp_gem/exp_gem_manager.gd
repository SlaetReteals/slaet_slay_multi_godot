# TemplateVersion: 1.4.0
extends Node

@export var gem_scene: PackedScene

func _ready() -> void:
	if multiplayer.is_server(): pass

func _spawn_gem_at_location(pos: Vector2) -> void:
	if gem_scene == null: return
	var gem = gem_scene.instantiate()
	gem.global_position = pos
	call_deferred("add_child", gem)
