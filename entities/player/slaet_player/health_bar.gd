# health_bar.gd
extends ProgressBar # or TextureProgressBar

@export var player_health_component: HealthComponent # Assign your player node in the inspector

func _ready() -> void:
	if player_health_component:
		# Initialize the bar's max and current values
		max_value = player_health_component.max_health
		value = player_health_component.current_health
		
		# Connect to the player's signal
		player_health_component.on_health_changed.connect(_on_player_health_changed)

func _on_player_health_changed(new_health: int) -> void:
	# Create a smooth animation (tween) to the new health value
	var tween = create_tween()
	
	# Animate the "value" property over 0.25 seconds using an ease-out transition
	tween.tween_property(self, "value", new_health, 0.25)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
