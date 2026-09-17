extends Resource
class_name PlayerClass

@export var id: String
@export var max_level: int = 10
@export var experience_cost: int = 10
@export var default_equipment: Resource

@export var title: String
@export var combat: PackedScene
@export_multiline var description: String

var texture_path_folder: String
var texture_idle: String
var texture_tombstone: String
var texture_walk_down: String
var texture_walk_up: String

func _init() -> void:
	texture_path_folder = "res://assets/textures/player/" + id
	texture_idle = texture_path_folder + "idle.png"
	texture_tombstone = texture_path_folder + "tombstone.png"
	texture_walk_down = texture_path_folder + "walk_down.png"
	texture_walk_up = texture_path_folder + "walk_up.png"
