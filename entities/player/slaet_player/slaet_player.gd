class_name Player
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 600.0
@export var acceleration: float = 4500.0 
@export var friction: float = 4500.0
@export var tex_walk_side: Texture2D
@export var tex_walk_up: Texture2D   
@export var tex_walk_down: Texture2D 

# --- Netfox Synchronized Properties ---
# Both movement and combat intent MUST be exported here and tracked by the RollbackSynchronizer
@export var _input_vector: Vector2 = Vector2.ZERO
@export_file("*.tres") var default_weapon_path: String = ""
# --- Node References ---
@onready var state_chart: StateChart = $StateChart as StateChart
@onready var sprite: Sprite2D = $Visuals/PlayerSprite as Sprite2D
@onready var rollback_sync: RollbackSynchronizer = $RollbackSynchronizer as RollbackSynchronizer
@onready var joystick: VirtualJoystickComponent = $UI/VirtualJoystickComponent as VirtualJoystickComponent
@onready var active_equipment: ActivePlayerEquipment = $ActivePlayerEquipment as ActivePlayerEquipment

# --- Private Movement State ---
var _is_currently_moving: bool = false
	
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		call_deferred("_claim_local_camera", self)
		
	# EVERY machine (Server and Clients) loads the default weapon locally.
	# This completely eliminates the RPC race condition!
	if default_weapon_path != "":
		active_equipment.initialize_default_weapon(default_weapon_path, 0)
	else:
		push_warning("Player spawned without a default_weapon_path assigned in the Inspector.")				
func _process(_delta: float) -> void:
	if is_multiplayer_authority():
		_poll_local_inputs()
	
	_update_sprite_direction()
	_update_animation_state()

func _poll_local_inputs() -> void:
	var keyboard_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var touch_input: Vector2 = Vector2.ZERO
	if joystick != null:
		touch_input = joystick.get_joystick_vector()
	
	var combined_input: Vector2 = keyboard_input + touch_input
	_input_vector = combined_input.normalized() if combined_input.length_squared() > 1.0 else combined_input
	
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	_apply_kinematics(delta)
	# Delegate combat execution to the separated component, passing the synchronized input
	active_equipment.process_weapons(tick, is_fresh)

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
