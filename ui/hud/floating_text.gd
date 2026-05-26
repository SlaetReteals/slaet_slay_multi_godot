class_name FloatingText
extends Node2D

@onready var label: Label = $Label

func start(payload: String) -> void:
	label.text = payload
	# Instantiate concurrent interpolation matrix
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	
	# Spatial translation vector (ascend 32 pixels over 0.75s)
	var target_position: Vector2 = global_position + (Vector2.UP * 32.0)
	tween.tween_property(self, "global_position", target_position, 0.75) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
		
	# Opacity decay matrix (fade to 0 over 0.75s)
	tween.tween_property(self, "modulate:a", 0.0, 0.75) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUART)
		
	# Scale transient pop effect (1.5x baseline returning to 1.0x over 0.2s)
	scale = Vector2.ONE * 1.5
	tween.tween_property(self, "scale", Vector2.ONE, 0.2) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_BACK)
		
	# Bind synchronous lifecycle termination post-interpolation
	tween.chain().tween_callback(queue_free)
