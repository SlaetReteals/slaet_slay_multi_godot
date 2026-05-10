extends AudioStreamPlayer

# Use descriptive names and strict static typing
@onready var _rest_timer: Timer = $Timer as Timer 

func _ready() -> void:
	# Use explicit return types and connect signals safely
	finished.connect(_on_finished)
	
	# Check for null to prevent the crash you experienced
	if _rest_timer:
		_rest_timer.timeout.connect(_on_timer_timeout)
	else:
		push_error("MusicPlayer Error: Timer node not found in scene tree.")

func _on_finished() -> void:
	# Keep functions short and typed
	_rest_timer.start()

func _on_timer_timeout() -> void:
	play()
