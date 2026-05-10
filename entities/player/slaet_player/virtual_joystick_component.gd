class_name VirtualJoystickComponent
extends Control

@export var max_drag_radius: float = 50.0
@export var knob: CanvasItem
@export var joystick_background: Sprite2D

var _output_vector: Vector2 = Vector2.ZERO
var _touch_center: Vector2 = Vector2.ZERO
var _is_active: bool = false

func _ready() -> void:
	assert(knob != null, "VirtualJoystickComponent: 'knob' node is not assigned!")
	knob.hide() # Keep the knob invisible until the screen is touched
	joystick_background.hide()
	
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and _is_active:
		_handle_drag()

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_is_active = true
		_touch_center = get_local_mouse_position()
		knob.position = _touch_center
		knob.show()
		joystick_background.position = _touch_center
		joystick_background.show()
	else:
		_is_active = false
		knob.hide()
		joystick_background.hide()
		_output_vector = Vector2.ZERO

func _handle_drag() -> void:
	var current_pos: Vector2 = get_local_mouse_position()
	var drag_vector: Vector2 = current_pos - _touch_center
	var distance: float = drag_vector.length()
	
	# Clamp the knob's visual position to the maximum radius
	if distance > max_drag_radius:
		drag_vector = drag_vector.normalized() * max_drag_radius
		
	knob.position = _touch_center + drag_vector
	_output_vector = drag_vector / max_drag_radius

func get_joystick_vector() -> Vector2:
	return _output_vector
