extends Sprite2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	# Connect the completion signal to a cleanup subroutine
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play("death_scene")

func _on_animation_finished(anim_name: StringName) -> void:
	# Logic executed exactly once upon completion
	print("Animation ", anim_name, " terminated successfully.")
	
	# Optional: Self-destruct logic for transient effects
	queue_free()
