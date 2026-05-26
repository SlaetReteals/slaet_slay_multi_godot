extends Node

# Preload your effect scenes so they are ready to be instantiated instantly
var floating_text_scene: PackedScene = preload("res://ui/hud/floating_text.tscn")

func _ready() -> void:
	pass

## API for other components to trigger damage numbers
func show_damage(amount: float, position: Vector2) -> void:
	var floating_text = floating_text_scene.instantiate()
	
	# 2. Check if the layer is a CanvasLayer (UI) or Node2D (World)
	var jitter = Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
	floating_text = floating_text_scene.instantiate()
	floating_text.global_position = position + jitter
	add_child(floating_text)
	
	# Format and start the effect
	var format_string: String = "%.0f" if round(amount) == amount else "%.1f"
	floating_text.start(format_string % amount)
