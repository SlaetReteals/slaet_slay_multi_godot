extends Node

@export var spawn_interval_ticks: int = 60 
@export var enemy_roster: Array[PackedScene] = [] # Put all your enemy scenes here

@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner

var _next_spawn_tick: int = 0

func _ready() -> void:
	if not NetworkTime.on_tick.is_connected(_tick):
			NetworkTime.on_tick.connect(_tick)
	# Programmatically register all enemy scenes so clients know how to build them
	for scene: PackedScene in enemy_roster:
		enemy_spawner.add_spawnable_scene(scene.resource_path)

func _tick(_delta: float, tick: int) -> void:
	if not multiplayer.is_server(): 
		return
	if tick >= _next_spawn_tick:
		_spawn_enemy_staggered()
		_next_spawn_tick = tick + spawn_interval_ticks

func _spawn_enemy_staggered() -> void:
	# Safety check in case the array is empty
	if enemy_roster.is_empty():
		LogManager.error("WaveManager", "Enemy roster is empty!")
		return
		
	# Pick a random enemy from the roster for this example
	var random_enemy_scene: PackedScene = enemy_roster.pick_random()
	var enemy: Node2D = random_enemy_scene.instantiate() as Node2D
	
	enemy.global_position = Vector2(0,0)
	
	#enemy.global_position = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 1000
	
	# Adding it as a child triggers the automatic MultiplayerSpawner replication
	add_child(enemy, true)
