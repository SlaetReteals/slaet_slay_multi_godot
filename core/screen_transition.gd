extends CanvasLayer

# Creates the "Eyelids" and triggers the blink sequence
func _execute_fade_in_transition() -> void:
	var fade_layer: CanvasLayer = CanvasLayer.new()
	fade_layer.layer = 100
	
	# Add the CanvasLayer directly to the Singleton so it persists through scene changes
	add_child(fade_layer)
	
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var half_y: float = vp_size.y / 2.0
	
	var top_lid: ColorRect = _create_eyelid(vp_size.x, half_y, 0.0)
	var bot_lid: ColorRect = _create_eyelid(vp_size.x, half_y, half_y)
	
	fade_layer.add_child(top_lid)
	fade_layer.add_child(bot_lid)
	
	_animate_blinks(top_lid, bot_lid, half_y, vp_size.y, fade_layer)

# Handles the sequencing of the double blink
func _animate_blinks(top: ColorRect, bot: ColorRect, half_y: float, full_y: float, transition_layer: CanvasLayer) -> void:
	# 1. Rename 'layer' to 'transition_layer' to fix the GDScript 2.0 shadowing warning
	var tween: Tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	var q_y: float = half_y / 2.0 
	
	# 2. Open Halfway -> Close
	tween.tween_interval(0.5)    
	tween.tween_property(top, "position:y", -q_y, 0.75)
	tween.parallel().tween_property(bot, "position:y", half_y + q_y, 0.75)
	tween.tween_property(top, "position:y", 0.0, 0.25)
	tween.parallel().tween_property(bot, "position:y", half_y, 0.25)
	
	# 3. Open All The Way
	tween.tween_property(top, "position:y", -half_y, 0.5)
	tween.parallel().tween_property(bot, "position:y", full_y, 0.5)
	
	# 4. Safely delete the UI layer at the end of the animation sequence
	tween.tween_callback(transition_layer.queue_free)
# Creates the "Eyelids" off-screen and slams them shut
func _execute_fade_out_transition() -> void:
	var fade_layer: CanvasLayer = CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var half_y: float = vp_size.y / 2.0
	
	# Spawn the lids completely off-screen
	var top_lid: ColorRect = _create_eyelid(vp_size.x, half_y, -half_y)
	var bot_lid: ColorRect = _create_eyelid(vp_size.x, half_y, vp_size.y)
	
	fade_layer.add_child(top_lid)
	fade_layer.add_child(bot_lid)
	
	_animate_shut(top_lid, bot_lid, half_y)

# Handles the closing animation
func _animate_shut(top: ColorRect, bot: ColorRect, half_y: float) -> void:
	# EASE_IN makes it start slow and accelerate into a violent slam
	var tween: Tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	
	tween.tween_property(top, "position:y", 0.0, 0.4)
	tween.parallel().tween_property(bot, "position:y", half_y, 0.4)

# Helper component to construct the ColorRects
func _create_eyelid(width: float, height: float, y_pos: float) -> ColorRect:
	var lid: ColorRect = ColorRect.new()
	lid.color = Color.BLACK
	lid.size = Vector2(width, height)
	lid.position = Vector2(0.0, y_pos)
	return lid
