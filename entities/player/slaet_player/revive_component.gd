class_name ReviveComponent
extends Area2D

# --- Exported State Variables ---
@export var revive_duration: float = 5.0
@export var player_node: Player

# Sync this variable via Netfox (StateSynchronizer) so clients can draw a progress bar!
@export var current_progress: float = 0.0 

@onready var tombstone_sprite: Sprite2D = $"../Visuals/TombstoneSprite"
var _overlapping_saviors: int = 0
var _is_active: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	monitoring = false # Tombstone is off by default

func enable_tombstone() -> void:
	_is_active = true
	monitoring = true
	current_progress = 0.0
	tombstone_sprite.visible = true
	
func disable_tombstone() -> void:
	_is_active = false
	monitoring = false
	current_progress = 0.0
	_overlapping_saviors = 0
	tombstone_sprite.visible = false

func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
		
	var other_player: Player = body as Player
	# Ensure the body is a player, is NOT ourselves, and is currently alive
	if other_player != null and other_player != player_node and not other_player._is_dead:
		_overlapping_saviors += 1

func _on_body_exited(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
		
	var other_player: Player = body as Player
	if other_player != null and other_player != player_node:
		_overlapping_saviors = maxi(0, _overlapping_saviors - 1)

# Delegated from the Player's Netfox _rollback_tick
func process_revive_tick(delta: float) -> void:
	if not multiplayer.is_server() or not _is_active:
		return

	if _overlapping_saviors > 0:
		current_progress += delta
		if current_progress >= revive_duration:
			_execute_revive()
	else:
		# Timer decays quickly if the savior steps off the tombstone
		current_progress = maxf(0.0, current_progress - (delta * 2.0))

func _execute_revive() -> void:
	disable_tombstone()
	player_node.execute_server_revive()
