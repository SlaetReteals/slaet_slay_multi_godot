class_name BaseEnemy
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 250.0

# --- Node References ---
@onready var state_chart: StateChart = $StateChart
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_component: HealthComponent = $HealthComponent
@onready var attack_state: AtomicState = $StateChart/Root/Attack
@onready var death_state: AtomicState = $StateChart/Root/Death

var _target_player: Node2D = null
var _is_dead: bool = false
var _is_chasing: bool = false

func _ready() -> void:
	if multiplayer.is_server():
		_connect_server_signals()

func _connect_server_signals() -> void:
	# Only the server listens to state chart signals for logical execution
	attack_state.state_entered.connect(_on_attack_state_entered)
	death_state.state_entered.connect(_on_death_state_entered)
	health_component.on_health_depleted.connect(_on_health_depleted)

# --- Netfox Deterministic Loop ---
func _tick(_delta: float, _tick_id: int) -> void:
	if not multiplayer.is_server() or _is_dead:
		return
		
	# Clients passively receive coordinates via StateSynchronizer
	_apply_server_navigation()

func _apply_server_navigation() -> void:
	if _target_player == null or not _is_chasing:
		return
		
	nav_agent.target_position = _target_player.global_position
	
	if not nav_agent.is_navigation_finished():
		var next_pos: Vector2 = nav_agent.get_next_path_position()
		var direction: Vector2 = global_position.direction_to(next_pos)
		velocity = direction * speed
		move_and_slide()

# --- Combat & State Management ---
func _on_attack_state_entered() -> void:
	if not multiplayer.is_server():
		return
		
	_is_chasing = false
	_rpc_trigger_bullet_pattern.rpc("spread_shot")
	
	# Send event to chart to resume chasing after attack completes
	state_chart.send_event("attack_finished")

@rpc("authority", "call_local", "reliable")
func _rpc_trigger_bullet_pattern(pattern_id: String) -> void:
	# BulletUpHell localized execution for all clients
	if has_node("SpawnPatternComponent"):
		var spawner: Node = get_node("SpawnPatternComponent")
		spawner.trigger_pattern(pattern_id)

func _on_health_depleted() -> void:
	if not multiplayer.is_server() or _is_dead:
		return
	state_chart.send_event("die")

func _on_death_state_entered() -> void:
	_is_dead = true
	_rpc_execute_death_visuals.rpc()
	
	# Server queues free after a brief timeout to allow local VFX to play
	get_tree().create_timer(1.5).timeout.connect(queue_free)

@rpc("authority", "call_local", "reliable")
func _rpc_execute_death_visuals() -> void:
	# Disable collisions immediately on all clients
	$HitboxComponent.set_deferred("monitorable", false)
	$HitboxComponent.set_deferred("monitoring", false)
	
	if has_node("Visuals/AnimationPlayer"):
		var anim: AnimationPlayer = get_node("Visuals/AnimationPlayer")
		anim.play("death_explode")
