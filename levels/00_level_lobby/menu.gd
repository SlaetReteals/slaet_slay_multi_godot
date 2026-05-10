extends CanvasLayer

@export var slide_panel: Panel 
@export var pull_button: Button 

var _is_open: bool = false
var _menu_tween: Tween

func _ready() -> void:
	# Connect the button dynamically
	pull_button.pressed.connect(_on_button_pressed)
	
	# Initialize the menu perfectly hidden off-screen at the bottom
	var vp_y: float = get_viewport().get_visible_rect().size.y
	slide_panel.position.y = vp_y

func _on_button_pressed() -> void:
	_is_open = not _is_open
	_execute_slide_animation()

func _execute_slide_animation() -> void:
	# Kill the current tween if the user mashes the button rapidly
	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()
		
	# TRANS_BACK gives the menu a slight, satisfying "bounce" when it stops
	_menu_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Calculate target: Slide up exactly the height of the panel, or hide entirely
	var target_y: float = vp_size.y - slide_panel.size.y if _is_open else vp_size.y
	
	_menu_tween.tween_property(slide_panel, "position:y", target_y, 0.5)
