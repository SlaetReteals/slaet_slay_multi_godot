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
@onready var status_effect_component: StatusEffectComponent = get_node_or_null("StatusEffectComponent") as StatusEffectComponent

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
	var potential_targets: Array[Node] = []
	potential_targets.append_array(get_tree().get_nodes_in_group(&"player_targets"))
	potential_targets.append_array(get_tree().get_nodes_in_group(&"players"))
	
	var closest_dist: float = INF
	_target_player = null
	
	for candidate in potential_targets:
		if not is_instance_valid(candidate) or not (candidate is Node2D) or candidate.is_queued_for_deletion():
			continue
		# Ignore dead players
		if "_is_dead" in candidate and candidate._is_dead:
			continue
		# Ignore dead entities with health components
		var hp: HealthComponent = candidate.get_node_or_null("HealthComponent") as HealthComponent
		if hp and hp.current_health <= 0.0:
			continue
			
		var dist: float = global_position.distance_squared_to((candidate as Node2D).global_position)
		if dist < closest_dist:
			closest_dist = dist
			_target_player = candidate as Node2D

# --- Navigation & Kinematics ---
func _apply_server_navigation(tick_id: int) -> void:
	if is_instance_valid(status_effect_component) and status_effect_component.is_stunned():
		velocity = Vector2.ZERO
		return
		
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
func apply_damage(base_damage: float, element: String = "physical") -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(health_component):
		health_component.damage(base_damage)
	if is_instance_valid(status_effect_component) and element != "physical":
		match element.to_lower():
			"fire":
				status_effect_component.apply_status("burn", 3.0, base_damage * 0.3)
			"ice":
				status_effect_component.apply_status("slow", 2.5, 0.45)
			"stun", "explosive":
				status_effect_component.apply_status("stun", 0.5)
# --- Lifecycle Management ---
func _on_health_depleted() -> void:
	if not multiplayer.is_server() or _is_dead:
		return
	state_chart.send_event("dead")

func _on_death_state_entered() -> void:
	if _is_dead:
		return
	_is_dead = true
	
	# Immediately untarget this enemy from all players, towers, and abilities
	remove_from_group(&"enemy")
	
	# Stop synchronizing state and clear peer visibility so no more state packets are broadcast
	var state_sync: Node = get_node_or_null("StateSynchronizer")
	if state_sync:
		state_sync.process_mode = Node.PROCESS_MODE_DISABLED
		state_sync.set_process(false)
		state_sync.set_physics_process(false)
		if "visibility_filter" in state_sync and state_sync.visibility_filter != null:
			state_sync.visibility_filter.set_visibility_for(0, false)
			state_sync.visibility_filter.update_visibility()
			
	# Disable collisions and hurtbox so it cannot interact or take damage while dying
	collision_layer = 0
	collision_mask = 0
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	var hitbox_col: CollisionShape2D = get_node_or_null("HitBox") as CollisionShape2D
	if hitbox_col:
		hitbox_col.set_deferred("disabled", true)
	if sprite:
		sprite.visible = false
		
	if multiplayer.is_server():
		_rpc_execute_death_visuals.rpc()
		
		# Network Buffer: Keep proxy node alive for 0.6s to cleanly absorb any in-flight ACKs from clients
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)

@rpc("authority", "call_local", "reliable")
func _rpc_execute_death_visuals() -> void:
	var death_scene: Sprite2D = death_sprite.instantiate() as Sprite2D
	if death_scene != null:
		death_scene.global_position = self.global_position
		get_parent().add_child(death_scene)
