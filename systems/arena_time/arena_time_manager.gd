extends Node
class_name ArenaTimeManager

signal arena_difficulty_increased(arena_difficulty: int)

# Strictly typed constant
const DIFFICULTY_INTERVAL: int = 5

@export var end_screen_scene: PackedScene
@onready var timer: Timer = $Timer as Timer

# Strictly typed variables
var arena_difficulty: int = 0
var previous_time: float = 0.0

func _ready() -> void:
	previous_time = timer.wait_time
	# Use standard internal callback naming
	timer.timeout.connect(_on_timer_timeout)

# Prefix delta with '_' to resolve the warning, and strictly type it
func _process(_delta: float) -> void:
	var next_time_target: float = timer.wait_time - ((arena_difficulty + 1) * DIFFICULTY_INTERVAL)
	
	if timer.time_left <= next_time_target:
		arena_difficulty += 1
		arena_difficulty_increased.emit(arena_difficulty)

func get_time_elapsed() -> float:
	return timer.wait_time - timer.time_left

# Prefix with '_' since it's an internal signal receiver
func _on_timer_timeout() -> void:
	var end_screen_instance: Node = end_screen_scene.instantiate()
	add_child(end_screen_instance)
	
	# Assuming play_jingle is a method on your EndScreen script
	if end_screen_instance.has_method("play_jingle"):
		end_screen_instance.play_jingle()
		
	SaveManager.save()
