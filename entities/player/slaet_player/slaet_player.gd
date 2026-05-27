class_name Player
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 600.0
@export var acceleration: float = 4500.0 
@export var friction: float = 4500.0
@export var tombstone_sprite: Sprite2D


@onready var default_weapon_path: String = "res://entities/active_equipment/default.tres"
#@onready var active_equipment_path: String = "res://entities/active_equipment/default2.tres"

# --- Netfox Synchronized Properties ---
# Both movement and combat intent MUST be exported here and tracked by the RollbackSynchronizer
@export var _input_vector: Vector2 = Vector2.ZERO

# --- Node References ---
@onready var sprite: Sprite2D = $Visuals/PlayerSprite as Sprite2D

@onready var rollback_sync: RollbackSynchronizer = $RollbackSynchronizer as RollbackSynchronizer
@onready var joystick: VirtualJoystickComponent = $UI/VirtualJoystickComponent as VirtualJoystickComponent

# COMPONENT DELEGATION: We route all weapon logic to this child node
@onready var equipment_component: ActiveEquipmentComponent = $ActiveEquipmentComponent as ActiveEquipmentComponent

# Textures
@onready var tex_walk_side: Texture2D = load("res://assets/textures/player/MushWalk.png")
@onready var tex_walk_up: Texture2D = load("res://assets/textures/player/MushWalkUp.png")
@onready var tex_walk_down: Texture2D = load("res://assets/textures/player/MushIdle.png")

# State Chart
@onready var state_chart: StateChart = $StateChart
@onready var health_component: Node = $HealthComponent
@onready var death_state: AtomicState = $StateChart/Root/Death

@onready var _is_dead: bool = false

@onready var revive_component: ReviveComponent = $ReviveComponent as ReviveComponent
@onready var alive_state: CompoundState = $StateChart/Root/Alive
@onready var multi_id = str(self.name)

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
func _ready() -> void:
	if is_multiplayer_authority():
		call_deferred("_claim_local_camera", self)
	if multiplayer.is_server():
		_connect_server_signals()
	# EVERYONE must grant the weapon so it visually exists on all screens
	if equipment_component != null:
		equipment_component.grant_default_weapon(default_weapon_path)
#		equipment_component.grant_active_equipment(active_equipment_path)

func _connect_server_signals() -> void:
	death_state.state_entered.connect(_on_death_state_entered)
	alive_state.state_entered.connect(_on_alive_state_entered)
	health_component.on_health_depleted.connect(_on_health_depleted)

func _process(_delta: float) -> void:
	if is_multiplayer_authority():
		_poll_local_inputs()
	
	_update_sprite_direction()

func _on_health_depleted() -> void:
	if _is_dead:
		return
	state_chart.send_event("dead")
	print('Player Died ID# '+ multi_id)
	
func _on_death_state_entered() -> void:
	LogManager.info('player', 'Death state entered for ' + multi_id + '. is_server: ' + str(multiplayer.is_server()))
	
	# Force EVERYONE (including the server) to update their local death state
	_rpc_sync_death_state.rpc(true)

	var session_manager: Node = get_tree().get_first_node_in_group(&"session_manager")
	if session_manager != null and session_manager.has_method("check_game_over_condition"):
		session_manager.check_game_over_condition()

func _on_alive_state_entered() -> void:
	# Force EVERYONE to update their local alive state
	_rpc_sync_death_state.rpc(false)
func _poll_local_inputs() -> void:
	if _is_dead:
		_input_vector = Vector2.ZERO
		return
	var keyboard_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var touch_input: Vector2 = Vector2.ZERO
	if joystick != null:
		touch_input = joystick.get_joystick_vector()
	
	var combined_input: Vector2 = keyboard_input + touch_input
	_input_vector = combined_input.normalized() if combined_input.length_squared() > 1.0 else combined_input
	
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	if not _is_dead:
		_apply_kinematics(delta)
		equipment_component.process_weapons(tick, is_fresh)
	# Process revive logic continuously while dead
	if is_fresh:
		revive_component.process_revive_tick(delta)

func _apply_kinematics(delta: float) -> void:
	var target_velocity: Vector2 = _input_vector * speed
	
	if _input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()
func execute_server_revive() -> void:
	if not multiplayer.is_server():
		return
		
	var revive_health: float = health_component.max_health * 0.5 # Revive at 50% health
	health_component.current_health = revive_health
	# Force client UI updates
	_rpc_update_client_health.rpc(revive_health)
	
	# Send the event to the State Chart to transition out of Death
	state_chart.send_event("revive")
func _update_sprite_direction() -> void:
	if velocity.length_squared() == 0.0:
		return
		
	if abs(velocity.x) > abs(velocity.y):
		sprite.texture = tex_walk_side
		sprite.flip_h = velocity.x < 0.0 
	else:
		sprite.flip_h = false
		sprite.texture = tex_walk_down if velocity.y > 0.0 else tex_walk_up

func _claim_local_camera(target_node: Node2D) -> void:
	var pc_cam: PhantomCamera2D = get_tree().get_first_node_in_group(&"player_camera") as PhantomCamera2D
	if pc_cam != null:
		ScreenTransition._execute_fade_in_transition()
		pc_cam.set_follow_target(target_node)
		pc_cam.set_priority(10)
func apply_damage(base_amount: float, element: String = "physical") -> void:
	if not multiplayer.is_server():
		return
		
	var final_damage: float = base_amount
	
	match element:
		#"fire": final_damage *= 1.5 
		"earth": final_damage *= 0.5
			
	# 2. Server applies damage to its authoritative state
	if is_instance_valid(health_component):
		health_component.damage(final_damage)
		# 3. Server TELLS all clients to update their local UI/Visuals
		_rpc_update_client_health.rpc(health_component.current_health) # Adjust 'current_health' to whatever your variable is named

# 4. Create the RPC that runs on all clients
@rpc("any_peer", "call_local", "reliable")
func _rpc_update_client_health(new_health: float) -> void:
	if is_instance_valid(health_component):
		# 1. Update the client's local health variable
		health_component.current_health = new_health 
				# 2. Force the client's component to announce the change to the UI
		health_component.on_health_changed.emit(new_health)

@rpc("any_peer", "call_local", "reliable")
func _rpc_execute_death_visuals() -> void:
	if has_node("Visuals/AnimationPlayer"):
#		var anim: AnimationPlayer = get_node("Visuals/AnimationPlayer")
#		anim.play("death_explode")
		pass
@rpc("any_peer", "call_local", "reliable")
func _rpc_set_tombstone_state(is_enabled: bool) -> void:
	if is_instance_valid(revive_component):
		if is_enabled:
			revive_component.enable_tombstone()
		else:
			revive_component.disable_tombstone()
@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_death_state(is_dead: bool) -> void:
	# 1. Force the local client to know its dead/alive status
	_is_dead = is_dead
	
	if is_dead:
		_input_vector = Vector2.ZERO
		
		# Disable physics ghosting locally
		set_collision_layer_value(1, false)
		set_collision_mask_value(1, false)
		
		if is_instance_valid(revive_component):
			revive_component.enable_tombstone()
	else:
		# Re-enable physics ghosting locally
		set_collision_layer_value(1, true)
		set_collision_mask_value(1, true)
		
		if is_instance_valid(revive_component):
			revive_component.disable_tombstone()
