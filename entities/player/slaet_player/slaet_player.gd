class_name Player
extends CharacterBody2D

# --- INVENTORY & WEAPON STATE ---
# Add your WeaponData resources into this array in the Godot Inspector
@export var inventory: Array[WeaponData] = []
@export var active_weapon_index: int = 0


# Netfox synchronizes this array to rollback all 8 slots perfectly
@export var weapon_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# --- Exported State Variables ---
@export var speed: float = 600.0
@export var acceleration: float = 4500.0 
@export var friction: float = 4500.0
@export var tex_walk_side: Texture2D
@export var tex_walk_up: Texture2D   
@export var tex_walk_down: Texture2D 
# The maximum time between shots (0.25 seconds = 4 shots per second)
@export var fire_rate_seconds: float = 0.25 

# The actual active timer that counts down to zero
@export var _current_fire_cooldown: float = 0.0
# --- Netfox Synchronized Properties ---
@export var _input_vector: Vector2 = Vector2.ZERO
@export var _is_firing: bool = true 

# --- Node References ---
@onready var state_chart: StateChart = $StateChart as StateChart
@onready var sprite: Sprite2D = $Visuals/PlayerSprite as Sprite2D
@onready var rollback_sync: RollbackSynchronizer = $RollbackSynchronizer as RollbackSynchronizer
@onready var joystick: VirtualJoystickComponent = $UI/VirtualJoystickComponent as VirtualJoystickComponent
@onready var attack_state: AtomicState = $StateChart/Root/Combat/FireState as AtomicState
@onready var bullet_spawn_point: Node2D = $WeaponsContainer

# --- Private Movement State ---
var _is_currently_moving: bool = false

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	# Example: Create pools for the weapons currently in your inventory
	# You will eventually want a system that loops through the inventory and creates pools dynamically!
	Spawning.create_pool("onez", "0", 100)
	
	if is_multiplayer_authority():
		call_deferred("_claim_local_camera", self)
func _process(_delta: float) -> void:
	if is_multiplayer_authority():
		_poll_local_inputs()
	
	_update_sprite_direction()
	_update_animation_state() # Ensure this is actually called!

func _poll_local_inputs() -> void:
	var keyboard_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Safely get joystick input if it exists
	var touch_input: Vector2 = Vector2.ZERO
	if joystick != null:
		touch_input = joystick.get_joystick_vector()
	
	var combined_input: Vector2 = keyboard_input + touch_input
	_input_vector = combined_input.normalized() if combined_input.length_squared() > 1.0 else combined_input
	
	# Capture combat intent dynamically instead of hardcoding to true

func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	_apply_kinematics(delta)
	_process_auto_weapons(delta, is_fresh)
func _apply_kinematics(delta: float) -> void:
	var target_velocity: Vector2 = _input_vector * speed
	
	if _input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		
	move_and_slide()

func _update_sprite_direction() -> void:
	if velocity.length_squared() == 0.0:
		return
		
	if abs(velocity.x) > abs(velocity.y):
		sprite.texture = tex_walk_side
		sprite.flip_h = velocity.x < 0.0 
	else:
		sprite.flip_h = false
		sprite.texture = tex_walk_down if velocity.y > 0.0 else tex_walk_up

func _update_animation_state() -> void:
	var moving: bool = velocity.length_squared() > 0.0
	
	if moving != _is_currently_moving:
		_is_currently_moving = moving
		if _is_currently_moving:
			state_chart.send_event("move")
		else:
			state_chart.send_event("idle")
			
func _claim_local_camera(target_node: Node2D) -> void:
	var pc_cam: PhantomCamera2D = get_tree().get_first_node_in_group(&"player_camera") as PhantomCamera2D
	
	if pc_cam != null:
		ScreenTransition._execute_fade_in_transition()
		pc_cam.set_follow_target(target_node)
		pc_cam.set_priority(10)

# --- LAN BULLET SYNCHRONIZATION ---

func _on_fire_state_entered() -> void:
	# Only the local player dictates WHEN they shoot, but tells the network to render it locally
	if is_multiplayer_authority():
		_rpc_fire_bullets.rpc()
		# Immediately return to idle to await the next shot
		state_chart.send_event("fire_finished")


func _process_auto_weapons(delta: float, is_fresh: bool) -> void:
	# Loop through every slot in the inventory
	for i in range(inventory.size()):
		var current_weapon: WeaponData = inventory[i]
		
		# Skip empty inventory slots
		if current_weapon == null:
			continue
			
		# 1. Tick down this specific weapon's cooldown
		if weapon_cooldowns[i] > 0.0:
			weapon_cooldowns[i] -= delta
			
		# 2. Check if this weapon is ready to fire
		if weapon_cooldowns[i] <= 0.0:
			
			# 3. Only the authority sends the network trigger, and ONLY on fresh frames
			if is_multiplayer_authority() and is_fresh:
				_rpc_fire_bullets.rpc(current_weapon.pattern_id)
				
			# 4. Reset the cooldown for this specific slot
			# Note: We use '+=' instead of '=' to carry over fractional delta time
			weapon_cooldowns[i] += current_weapon.fire_rate_seconds
			
@rpc("authority", "call_local", "reliable")
func _rpc_fire_bullets(pattern_id: String) -> void:
	# BulletUpHell executes the specific weapon pattern locally
	Spawning.spawn(bullet_spawn_point, pattern_id)
