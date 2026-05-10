class_name Player
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 300.0
@export var acceleration: float = 4500.0 
@export var friction: float = 3000.0
@export var tex_walk_side: Texture2D
@export var tex_walk_up: Texture2D   
@export var tex_walk_down: Texture2D 

# --- Netfox Synchronized Properties ---
@export var _input_vector: Vector2 = Vector2.ZERO

# --- Node References ---
@onready var state_chart: StateChart = $StateChart as StateChart
@onready var sprite: Sprite2D = $Visuals/PlayerSprite as Sprite2D
@onready var rollback_sync: RollbackSynchronizer = $RollbackSynchronizer as RollbackSynchronizer
@onready var joystick: VirtualJoystickComponent = $UI/VirtualJoystickComponent as VirtualJoystickComponent

# --- Private Movement State ---
var _is_currently_moving: bool = false

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		call_deferred("_claim_local_camera", self)

func _process(_delta: float) -> void:
	# 1. Authority Check ONLY wraps the hardware input polling
	if is_multiplayer_authority():
		_poll_local_inputs()
		
	# 2. Universal Execution: ALL peers must update sprite rotation
	_update_sprite_direction()

func _poll_local_inputs() -> void:
	var keyboard_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var touch_input: Vector2 = joystick.get_joystick_vector()
	
	var combined_input: Vector2 = keyboard_input + touch_input
	
	if combined_input.length_squared() > 1.0:
		_input_vector = combined_input.normalized()
	else:
		_input_vector = combined_input

func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	var target_velocity: Vector2 = _input_vector * speed
	
	if _input_vector != Vector2.ZERO:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		
	move_and_slide()
	
	# 3. Only send events to the State Chart on fresh ticks to avoid rollback spam
	if is_fresh:
		_update_animation_state()

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
