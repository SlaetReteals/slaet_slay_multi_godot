class_name ActiveEquipmentComponent
extends Node2D

@export var targeting_component: TargetingComponent

# --- Local State ---
var _inventory: Array[BulletProp] = []
var _fire_ticks: Array[int] = []
var _weapon_anchors: Array[Node2D] = [] # Dedicated spatial matrix per weapon

func _ready() -> void:
	if targeting_component == null:
		targeting_component = get_node_or_null("TargetingComponent") as TargetingComponent
		if targeting_component == null:
			targeting_component = TargetingComponent.new()
			targeting_component.name = "TargetingComponent"
			targeting_component.targeting_radius = 450.0
			add_child(targeting_component)

# --- Weapon Management ---
func grant_default_weapon(active_equipment_path: String) -> void:
	_execute_equipment_instantiation(active_equipment_path)

func grant_active_equipment(active_equipment_path: String) -> void:
	if not multiplayer.is_server():
		return
	_rpc_equip_active_equipment.rpc(active_equipment_path)

@rpc("any_peer", "call_local", "reliable")
func _rpc_equip_active_equipment(active_equipment_path: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0:
		push_warning("[SEC_WARN] Unauthorized weapon equip attempt rejected.")
		return

	_execute_equipment_instantiation(active_equipment_path)

func _execute_equipment_instantiation(path: String) -> void:
	var new_equipment: BulletProp = load(path) as BulletProp
	if not new_equipment:
		push_error("[IO_ERR] Failed to load equipment matrix at: ", path)
		return
		
	# Dynamically allocate a dedicated spatial proxy for this weapon
	var anchor: Marker2D = Marker2D.new()
	anchor.name = "WeaponAnchor_" + str(_inventory.size())
	add_child(anchor)
	_inventory.append(new_equipment)
	_fire_ticks.append(NetworkTime.tick + new_equipment.fire_rate_ticks)
	_weapon_anchors.append(anchor)

# --- Combat Execution ---
func process_weapons(tick: int, is_fresh: bool) -> void:
	for i in range(_inventory.size()):
		var weapon: BulletProp = _inventory[i]

		if tick >= _fire_ticks[i]:
			_fire_ticks[i] = tick + weapon.fire_rate_ticks
			
			if is_fresh and multiplayer.is_server():
				var anchor: Node2D = _weapon_anchors[i]
				var azimuth: float = _calculate_interception_azimuth(anchor)
				var shared_area: String = _inventory[i].shared_area
				#print(azimuth)
				# Serialize the array index to identify the correct spatial anchor
				_rpc_fire_bullets.rpc(i, weapon.pattern_id, azimuth, shared_area)

# Pass the specific anchor to calculate azimuth from its exact offset
func _calculate_interception_azimuth(anchor: Node2D) -> float:
	if targeting_component != null:
		var target: Node2D = null
		if targeting_component.has_method("acquire_target"):
			target = targeting_component.acquire_target()
		elif targeting_component.has_method("get_target"):
			target = targeting_component.get_target()
		if is_instance_valid(target):
			return anchor.global_position.angle_to_point(target.global_position)
		return anchor.global_rotation
		
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var closest_dist: float = INF
	var fallback_target: Node2D = null
	
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Node2D:
			var dist: float = anchor.global_position.distance_squared_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				fallback_target = enemy
				
	if is_instance_valid(fallback_target):
		return anchor.global_position.angle_to_point(fallback_target.global_position)
		
	return anchor.global_rotation

@rpc("any_peer", "call_local", "reliable")
func _rpc_fire_bullets(anchor_index: int, _pattern_id: String, azimuth: float, _shared_area: String) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0:
		return
		
	# Validate array bounds before execution
	if anchor_index >= 0 and anchor_index < _weapon_anchors.size():
		var active_anchor: Node2D = _weapon_anchors[anchor_index]
		
		if is_instance_valid(active_anchor):
			active_anchor.global_rotation = azimuth
			
		if anchor_index < _inventory.size():
			var weapon: BulletProp = _inventory[anchor_index]
			if weapon and weapon.projectile_scene:
				var proj: Node = weapon.projectile_scene.instantiate()
				if proj is Node2D:
					proj.global_position = active_anchor.global_position
					if proj.has_method("setup"):
						proj.setup(Vector2.RIGHT.rotated(azimuth), weapon.speed, weapon.base_damage, weapon.damage_type)
					elif "direction" in proj:
						proj.direction = Vector2.RIGHT.rotated(azimuth)
				get_tree().current_scene.add_child(proj)
