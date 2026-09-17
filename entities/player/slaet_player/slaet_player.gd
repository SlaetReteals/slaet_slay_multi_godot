class_name Player
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 600.0
@export var acceleration: float = 4500.0 
@export var friction: float = 4500.0
@export var tombstone_sprite: Sprite2D


@onready var default_weapon_path: String = "res://resources/equipment/basic.tres"
#@onready var active_equipment_path: String = "res://resources/equipment/fire_wand.tres"

# --- Netfox Synchronized Properties ---
# Both movement and combat intent MUST be exported here and tracked by the RollbackSynchronizer
@export var _input_vector: Vector2 = Vector2.ZERO

@export_group("Active Ability")
@export var active_spell_scene: PackedScene = preload("res://components/combat/base_projectile.tscn")
@export var active_spell_cooldown: float = 1.0
@export var active_spell_speed: float = 550.0
@export var active_spell_damage: float = 30.0
@export var active_spell_element: String = "physical"

var _last_spell_cast_tick: int = 0

# --- Node References ---
@onready var sprite: Sprite2D = $Visuals/PlayerSprite as Sprite2D
@onready var state_sync: StateSynchronizer = $StateSynchronizer as StateSynchronizer
@onready var rollback_sync: RollbackSynchronizer = $RollbackSynchronizer as RollbackSynchronizer
@onready var joystick: VirtualJoystickComponent = $UI/VirtualJoystickComponent as VirtualJoystickComponent

# COMPONENT DELEGATION: We route all weapon logic to this child node
@onready var equipment_component: ActiveEquipmentComponent = $ActiveEquipmentComponent as ActiveEquipmentComponent
@onready var placement_component: PlacementComponent = get_node_or_null("PlacementComponent") as PlacementComponent
@onready var ability_component: AbilityComponent = get_node_or_null("AbilityComponent") as AbilityComponent

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

var _is_local_authority: bool = false

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
func _ready() -> void:
	add_to_group(&"player_targets")
	_is_local_authority = is_multiplayer_authority()
	# Disable Netfox processing immediately upon spawn
	state_sync.set_process(false)
	state_sync.set_physics_process(false)
	rollback_sync.set_process(false)
	rollback_sync.set_physics_process(false)
	
	if multiplayer.is_server():
		# Start a short timer, or ideally wait for a "Client Loaded" RPC
		_wait_for_clients_to_load()
	if _is_local_authority:
		call_deferred("_claim_local_camera", self)
		var mobile_ui: Node = get_node_or_null("UI/MobileActionBar")
		if mobile_ui and mobile_ui.has_method("setup"):
			mobile_ui.setup(self)
	else:
		if has_node("UI"):
			$UI.queue_free()
	if multiplayer.is_server():
		_connect_server_signals()
	# EVERYONE must grant the weapon so it visually exists on all screens
	if equipment_component != null and not default_weapon_path.is_empty():
		equipment_component.grant_default_weapon(default_weapon_path)

func _connect_server_signals() -> void:
	death_state.state_entered.connect(_on_death_state_entered)
	alive_state.state_entered.connect(_on_alive_state_entered)
	health_component.on_health_depleted.connect(_on_health_depleted)

func _process(_delta: float) -> void:
	if _is_local_authority:
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

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_authority or _is_dead:
		return
		
	if placement_component and not placement_component.available_placeables.is_empty():
		if event.is_action_pressed("hotbar_1") and placement_component.available_placeables.size() > 0:
			placement_component.start_placement(placement_component.available_placeables[0])
		elif event.is_action_pressed("hotbar_2") and placement_component.available_placeables.size() > 1:
			placement_component.start_placement(placement_component.available_placeables[1])
		elif event.is_action_pressed("hotbar_3") and placement_component.available_placeables.size() > 2:
			placement_component.start_placement(placement_component.available_placeables[2])
			
	if placement_component and placement_component.is_placing:
		if event.is_action_pressed("left_click"):
			placement_component.confirm_placement()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("cancel_action"):
			placement_component.cancel_placement()
			get_viewport().set_input_as_handled()
			
	if event.is_action_pressed("ability_cast"):
		_try_cast_active_spell()

func _try_cast_active_spell(slot: int = 0) -> void:
	if not _is_local_authority or _is_dead:
		return
	if ability_component:
		ability_component.cast_ability_slot(slot)
	elif active_spell_scene:
		var cooldown_ticks: int = int(active_spell_cooldown * 60.0)
		if NetworkTime.tick < _last_spell_cast_tick + cooldown_ticks:
			return
		_last_spell_cast_tick = NetworkTime.tick
		var azimuth: float = global_position.angle_to_point(get_global_mouse_position())
		_rpc_cast_spell.rpc(azimuth)

@rpc("any_peer", "call_local", "reliable")
func _rpc_cast_spell(azimuth: float) -> void:
	if active_spell_scene:
		var proj: Node = active_spell_scene.instantiate()
		if proj is Node2D:
			proj.global_position = global_position
			if proj.has_method("setup"):
				proj.setup(Vector2.RIGHT.rotated(azimuth), active_spell_speed, active_spell_damage, active_spell_element)
			elif "direction" in proj:
				proj.direction = Vector2.RIGHT.rotated(azimuth)
		var level: Node = get_tree().get_first_node_in_group(&"current_level")
		var target_parent: Node = level if level else get_tree().current_scene
		target_parent.add_child(proj)

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	if not _is_dead:
		_apply_kinematics(delta)
		equipment_component.process_weapons(tick, is_fresh)
		if ability_component and is_fresh and multiplayer.is_server():
			ability_component.process_auto_abilities(tick)
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
func _rpc_equip_items() -> void:
	equipment_component.grant_active_equipment(default_weapon_path)
	
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
# Runs only on the server, called from _ready()
func _wait_for_clients_to_load() -> void:
	# Wait for 3 to 5 physics frames. 
	# This gives the MultiplayerSpawner a tiny buffer to finish replicating the node.
	for i in range(5):
		await get_tree().physics_frame
	
	# The node now exists on the clients. 
	# It is safe to turn the Server's Netfox synchronizers back on.
	if state_sync:
		state_sync.set_process(true)
		state_sync.set_physics_process(true)
		
	if rollback_sync:
		rollback_sync.set_process(true)
		rollback_sync.set_physics_process(true)
