class_name BaseEnemy
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 200.0
@export var damage: int = 10
@export var damage_type: String = "basic"
@export var death_sprite: PackedScene

enum GemSize { SMALL, MEDIUM, LARGE }
@export var exp_gem: GemSize = GemSize.SMALL
# --- Node References ---
@onready var state_chart: StateChart = $StateChart
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_component: HealthComponent = $HealthComponent
@onready var chase_state: AtomicState = $StateChart/Root/Chase
@onready var attack_state: AtomicState = $StateChart/Root/Attack
@onready var death_state: AtomicState = $StateChart/Root/Death
@onready var hurtbox: Area2D = $HurtboxComponent
@onready var sprite: Sprite2D = $Visuals/EnemySprite

var _target_player: Node2D = null
var _is_dead: bool = false
var _is_chasing: bool = false

# --- Deterministic Throttling Parameters ---
var _last_path_update_tick: int = 0
const PATH_UPDATE_INTERVAL: int = 15

func _ready() -> void:
	if multiplayer.is_server():
		_connect_server_signals()
		
	# Explicitly bind the Netfox deterministic loop execution bridge
	if NetworkTime.has_signal("on_tick"):
		NetworkTime.on_tick.connect(_tick)

func _connect_server_signals() -> void:
	# State entry/exit strictly governs the boolean gate
	chase_state.state_entered.connect(func(): _is_chasing = true)
	chase_state.state_exited.connect(func(): _is_chasing = false)
	
	attack_state.state_entered.connect(_on_attack_state_entered)
	death_state.state_entered.connect(_on_death_state_entered)
	health_component.on_health_depleted.connect(_on_health_depleted)
#	health_component.on_health_changed.connect(_on_health_changed)
# --- Netfox Deterministic Loop ---
func _tick(_delta: float, tick_id: int) -> void:
	if multiplayer == null:
		return
	if not multiplayer.is_server() or _is_dead:
		return
		
	# Route kinematic execution based strictly on active state
	if _is_chasing:
		_apply_server_navigation(tick_id)

#func _on_health_changed(current_health):
	#print(current_health)

# --- Spatial Targeting ---
func _acquire_closest_target() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var closest_dist: float = INF
	_target_player = null
	
	for player in players:
		if is_instance_valid(player) and player is Node2D and not player._is_dead:
			var dist: float = global_position.distance_squared_to(player.global_position)
			if dist < closest_dist:
				closest_dist = dist
				_target_player = player

# --- Navigation & Kinematics ---
func _apply_server_navigation(tick_id: int) -> void:
	_acquire_closest_target()
	
	if not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
		
	if _target_player.global_position.is_zero_approx():
		velocity = Vector2.ZERO
		return
		
	# A* Matrix Throttling Protocol
	if tick_id - _last_path_update_tick >= PATH_UPDATE_INTERVAL:
		nav_agent.target_position = _target_player.global_position
		_last_path_update_tick = tick_id
		
	if nav_agent.is_navigation_finished() or nav_agent.get_current_navigation_path().is_empty():
		velocity = Vector2.ZERO
		return
		
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	
	if next_pos.is_zero_approx() and not global_position.is_zero_approx():
		velocity = Vector2.ZERO
		return
		
	var direction: Vector2 = global_position.direction_to(next_pos)
	velocity = direction * speed
	
	move_and_slide()

# --- Combat Management ---
func _on_attack_state_entered() -> void:
	if not multiplayer.is_server():
		return
		
	velocity = Vector2.ZERO 
#	_resolve_contact_damage()
	
	get_tree().create_timer(0.5).timeout.connect(func():
		if not _is_dead:
			state_chart.send_event("attack_finished")
	)
func apply_damage(base_damage: float) -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(health_component):
		health_component.damage(base_damage)
# --- Lifecycle Management ---
func _on_health_depleted() -> void:
	if not multiplayer.is_server() or _is_dead:
		return
	state_chart.send_event("dead")

func _on_death_state_entered() -> void:
	_is_dead = true
		# 2. ONLY the Server should broadcast the RPC and manage node deletion
	if multiplayer.is_server():
		
		# Tell all clients to hide the body and spawn the 2D Explosion Sprite
		_rpc_execute_death_visuals.rpc()
		
		# (If you are spawning an EXP gem, do it right here!)
		# _spawn_exp_gem()

		# 3. Network Buffer: Give the RPC 0.25 seconds to travel across the internet 
		# before the Server destroys the actual node.
		call_deferred("queue_free")
	
	
	# 1. Turn off core logic and physics immediately (DEFERRED)
	#set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	#$HurtboxComponent.set_deferred("monitorable", false)
	#$HurtboxComponent.set_deferred("monitoring", false)

	#$HurtboxComponent/CollisionShape2D.set_deferred("disabled", true)

@rpc("authority", "call_local", "reliable")
func _rpc_execute_death_visuals() -> void:
	var death_scene: Sprite2D = death_sprite.instantiate() as Sprite2D
	if death_scene != null:
		death_scene.global_position = self.global_position
		get_parent().add_child(death_scene)
