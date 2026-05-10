# TemplateVersion: 1.4.0
extends Node

func roll_for_loot(enemy_type: String) -> String:
    var roll = randf()
    if roll > 0.95: return "rare_weapon"
    elif roll > 0.8: return "health_potion"
    else: return "none"