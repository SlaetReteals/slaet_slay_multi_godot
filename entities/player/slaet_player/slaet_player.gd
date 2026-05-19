class_name Player
extends CharacterBody2D

# --- Exported State Variables ---
@export var speed: float = 600.0
@export var acceleration: float = 4500.0 
@export var friction: float = 4500.0

@onready var default_weapon_path: String = "res://systems/active_equipment_manager/default_mushroom/default_mushroom.tres"

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

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		call_deferred("_claim_local_camera", self)
	
	# ONLY the Server acts as the authority to initialize loadouts
	if equipment_component != null:
			equipment_component.grant_default_weapon(default_weapon_path)

func _process(_delta: float) -> void:
	if is_multiplayer_authority():
		_poll_local_inputs()
	
	_update_sprite_direction()

func _poll_local_inputs() -> void:
	var keyboard_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var touch_input: Vector2 = Vector2.ZERO
	if joystick != null:
		touch_input = joystick.get_joystick_vector()
	
	var combined_input: Vector2 = keyboard_input + touch_input
	_input_vector = combined_input.normalized() if combined_input.length_squared() > 1.0 else combined_input
	
func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	_apply_kinematics(delta)
	
	# Delegate combat execution to the separated component
	equipment_component.process_weapons(tick, is_fresh)

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

func _claim_local_camera(target_node: Node2D) -> void:
	var pc_cam: PhantomCamera2D = get_tree().get_first_node_in_group(&"player_camera") as PhantomCamera2D
	if pc_cam != null:
		ScreenTransition._execute_fade_in_transition()
		pc_cam.set_follow_target(target_node)
		pc_cam.set_priority(10)
