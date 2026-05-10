class_name ProceduralKnobComponent
extends Node

@export var target_sprite: Sprite2D

func _ready() -> void:
	assert(target_sprite != null, "ProceduralKnob: target_sprite is not assigned!")
