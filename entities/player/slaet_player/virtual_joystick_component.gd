class_name VirtualJoystickComponent
extends Control

@export var max_drag_radius: float = 75.0
@export var deadzone: float = 10.0
@export var knob: CanvasItem
@export var joystick_background: CanvasItem

var _output_vector: Vector2 = Vector2.ZERO
var _touch_center: Vector2 = Vector2.ZERO
var _is_active: bool = false
var _touch_index: int = -1

func _ready() -> void:
	assert(knob != null, "VirtualJoystickComponent: 'knob' node is not assigned!")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_joystick()

func _unhandled_input(event: InputEvent) -> void:
	# Starts joystick anywhere the player touches or clicks, unless consumed by an interactive UI control
	if event is InputEventScreenTouch:
		if event.pressed and not _is_active:
			_start_joystick(event.index, event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _is_active:
			_start_joystick(-1, event.position)
	elif event is InputEventScreenDrag:
		if not _is_active:
			_start_joystick(event.index, event.position - event.relative)
			_update_drag(event.position)

func _input(event: InputEvent) -> void:
	# When active, track drags and release globally so sliding across screen elements doesn't interrupt movement
	if not _is_active:
		return
		
	if event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_drag(event.position)
	elif event is InputEventScreenTouch:
		if not event.pressed and event.index == _touch_index:
			_reset_joystick()
	elif event is InputEventMouseMotion:
		if _touch_index == -1:
			_update_drag(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _touch_index == -1 or _touch_index == 0:
				_reset_joystick()

func _start_joystick(index: int, pos: Vector2) -> void:
	_is_active = true
	_touch_index = index
	_touch_center = pos
	_output_vector = Vector2.ZERO
	
	if joystick_background:
		joystick_background.global_position = _touch_center
		joystick_background.show()
	if knob:
		knob.global_position = _touch_center
		knob.show()

func _update_drag(pos: Vector2) -> void:
	var drag_vector: Vector2 = pos - _touch_center
	var distance: float = drag_vector.length()
	
	if distance < deadzone:
		_output_vector = Vector2.ZERO
		if knob:
			knob.global_position = _touch_center
		return
		
	if distance > max_drag_radius:
		drag_vector = drag_vector.normalized() * max_drag_radius
		
	if knob:
		knob.global_position = _touch_center + drag_vector
		
	_output_vector = drag_vector / max_drag_radius

func _reset_joystick() -> void:
	_is_active = false
	_touch_index = -1
	_output_vector = Vector2.ZERO
	if knob:
		knob.hide()
	if joystick_background:
		joystick_background.hide()

func get_joystick_vector() -> Vector2:
	return _output_vector
