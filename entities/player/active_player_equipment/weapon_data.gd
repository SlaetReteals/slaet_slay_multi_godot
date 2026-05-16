class_name WeaponData
extends Resource

# The BulletUpHell pattern identifier string (e.g., "onez", "spread_shot")
@export var pattern_id: String = ""

# The deterministic cooldown measured in Netfox network ticks (e.g., 60 ticks = 1 second)
@export var fire_rate_ticks: int = 15
