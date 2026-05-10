extends Node

# Use strict static typing for all signal parameters
signal experience_vial_collected(number: float)
signal player_damaged

func emit_experience_vial_collected(number: float) -> void:
	experience_vial_collected.emit(number)


func emit_player_damaged() -> void:
	player_damaged.emit()
