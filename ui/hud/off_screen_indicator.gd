class_name OffScreenIndicator
extends CanvasLayer

@export var margin: float = 8.0 
@export var indicator_opacity: float = 0.6 
# NEW: How fast the arrow catches up to the target (higher = faster snap)
@export var lerp_speed: float = 15.0 

@onready var arrow: TextureRect = $Arrow
var target_player: Node2D = null

func _process(delta: float) -> void:
	if not is_instance_valid(target_player):
		arrow.hide()
		return

	var camera: Camera2D = get_viewport().get_camera_2d()
	var target_screen_pos: Vector2 = target_player.get_global_transform_with_canvas().origin

	if get_viewport().get_visible_rect().has_point(target_screen_pos) or not camera:
		arrow.hide()
	else:
		# Pass delta down so we can calculate time-based movement
		_update_offscreen_arrow(camera, target_screen_pos, delta)

func _update_offscreen_arrow(camera: Camera2D, screen_pos: Vector2, delta: float) -> void:
	arrow.show()
	arrow.self_modulate = Color(1.0, 1.0, 1.0, indicator_opacity)
	
	# 1. Smooth Rotation (CRITICAL: Use lerp_angle, not standard lerp)
	var world_dir: Vector2 = (target_player.global_position - camera.global_position).normalized()
	var target_rot: float = world_dir.angle() + (PI / 2.0)
	arrow.rotation = lerp_angle(arrow.rotation, target_rot, lerp_speed * delta)
	
	# 2. Smooth Position
	var target_pos: Vector2 = _get_clamped_position(screen_pos)
	arrow.global_position = arrow.global_position.lerp(target_pos, lerp_speed * delta)

# Refactored to return the Vector2 instead of setting it directly
func _get_clamped_position(screen_pos: Vector2) -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_size: Vector2 = arrow.size / 2.0
	
	var clamped_x: float = clamp(screen_pos.x, margin + half_size.x, viewport_size.x - margin - half_size.x)
	var clamped_y: float = clamp(screen_pos.y, margin - 10 + half_size.y, viewport_size.y - margin + 10 - half_size.y)
	
	return Vector2(clamped_x, clamped_y)
