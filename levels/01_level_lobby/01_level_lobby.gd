extends BaseLevel

func _init() -> void:
	_level_name = "Lobby"

@onready var level_template_area: Area2D = $SpawnLevelTemplate

func _level_ready() -> void:
	if level_template_area:
		level_template_area.body_entered.connect(_on_area_level_template_entered)

func _on_area_level_template_entered(_body: Node) -> void:
	print("area entered")
	var main_node: Main = get_tree().get_first_node_in_group(&"main") as Main
	if not main_node and get_tree().root.has_node("Main"):
		main_node = get_tree().root.get_node("Main") as Main
	if main_node:
		main_node.change_level("res://levels/02_level_treestump/02_level_treestump.tscn")
