class_name UpgradeManager
extends Node

@export var experience_manager: ExperienceManager
@export var upgrade_screen_scene: PackedScene
@export var upgrade_pool_resources: Array[AbilityUpgrade] = []

var current_upgrades: Dictionary = {}
var upgrade_pool: WeightedTable = WeightedTable.new()

func _ready() -> void:
	for upgrade in upgrade_pool_resources:
		if is_instance_valid(upgrade):
			upgrade_pool.add_item(upgrade, 10)
			
	if is_instance_valid(experience_manager):
		experience_manager.level_up.connect(_on_level_up)

func add_upgrade_to_pool(upgrade: AbilityUpgrade, weight: int = 10) -> void:
	if is_instance_valid(upgrade):
		upgrade_pool.add_item(upgrade, weight)

func apply_upgrade(upgrade: AbilityUpgrade) -> void:
	if not is_instance_valid(upgrade):
		return
	var has_upgrade: bool = current_upgrades.has(upgrade.id)
	if not has_upgrade:
		current_upgrades[upgrade.id] = {
			'resource': upgrade,
			'quantity': 1
		}
	else:
		current_upgrades[upgrade.id]['quantity'] += 1
	
	if upgrade.max_quantity > 0:
		var current_quantity: int = current_upgrades[upgrade.id]['quantity']
		if current_quantity >= upgrade.max_quantity:
			upgrade_pool.remove_item(upgrade)
	
	GameEvents.emit_ability_upgrade_added(upgrade, current_upgrades)
	
func pick_upgrades() -> Array[AbilityUpgrade]:
	var chosen_upgrades: Array[AbilityUpgrade] = []
	
	for i in 2:
		if upgrade_pool.items.size() == chosen_upgrades.size():
			break
		var chosen_upgrade = upgrade_pool.pick_item(chosen_upgrades)
		if chosen_upgrade is AbilityUpgrade:
			chosen_upgrades.append(chosen_upgrade)
	
	return chosen_upgrades

func _on_upgrade_selected(upgrade: AbilityUpgrade) -> void:
	apply_upgrade(upgrade)

func _on_level_up(_current_level: int) -> void:
	if not upgrade_screen_scene:
		return
	var upgrade_screen_instance: Node = upgrade_screen_scene.instantiate()
	add_child(upgrade_screen_instance)
	
	var chosen_upgrades: Array[AbilityUpgrade] = pick_upgrades()
	if upgrade_screen_instance.has_method("set_ability_upgrades"):
		upgrade_screen_instance.set_ability_upgrades(chosen_upgrades)
	
	if upgrade_screen_instance.has_signal("upgrade_selected"):
		upgrade_screen_instance.upgrade_selected.connect(_on_upgrade_selected)
