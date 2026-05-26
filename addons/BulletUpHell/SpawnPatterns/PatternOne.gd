@tool
@icon("res://addons/BulletUpHell/Sprites/NodeIcons8.png")
extends Pattern
class_name PatternOne

@export_group("Basic")
@export var symmetric:bool = false
@export var symmetry_type = 0
func _init():
	resource_name = "PatternOne"
