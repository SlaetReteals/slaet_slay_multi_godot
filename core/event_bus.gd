extends Node

@warning_ignore("unused_signal")
signal enemy_died(enemy_position: Vector2)
@warning_ignore("unused_signal")
signal player_took_damage(player_id: int, new_health: float)
@warning_ignore("unused_signal")
signal exp_gem_collected(amount: int, player_id: int)
@warning_ignore("unused_signal")
signal wave_completed(wave_number: int)
