extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Loaded Test")
	print(self.global_position)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	print(self.global_position)
	pass
