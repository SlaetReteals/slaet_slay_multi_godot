extends Node

func _ready() -> void:
	GameEvents.experience_vial_collected.connect(_on_experience_collected)

func add_meta_upgrade(upgrade: MetaUpgrade) -> void:
	# SERVER AUTHORITY: Critical progression is server-side [cite: 55]
	if not multiplayer.is_server():
		return
		
	var meta: Dictionary = SaveManager.save_data.meta_upgrades
	if not meta.has(upgrade.id):
		meta[upgrade.id] = { "quantity": 0 }
	
	meta[upgrade.id]["quantity"] += 1
	SaveManager.save()

func get_upgrade_count(upgrade_id: String) -> int:
	var meta: Dictionary = SaveManager.save_data.meta_upgrades
	if not meta.has(upgrade_id): 
		return 0
	return meta[upgrade_id]["quantity"] as int

func _on_experience_collected(number: float) -> void:
	if multiplayer.is_server():
		SaveManager.save_data.meta_upgrade_currency += number
