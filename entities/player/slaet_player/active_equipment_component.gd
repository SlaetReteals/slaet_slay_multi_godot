class_name ActiveEquipmentComponent
extends Node2D

# --- Local State ---
var _inventory: Array[WeaponData] = []
var _fire_ticks: Array[int] = []

@onready var _spawn_point: Node2D = $BulletSpawn
func grant_default_weapon(weapon_path: String) -> void:
	var new_weapon: WeaponData = load(weapon_path) as WeaponData
	if new_weapon == null:
		push_error("Failed to load weapon data at: ", weapon_path)
		return
		
	_inventory.append(new_weapon)
	
	# Sync Netfox deterministic timer
	_fire_ticks.append(NetworkTime.tick + new_weapon.fire_rate_ticks)

# --- Weapon Management ---
func grant_weapon(weapon_path: String) -> void:
	if not multiplayer.is_server():
		return
	_rpc_equip_weapon.rpc(weapon_path)

# CHANGED: "authority" to "any_peer" so the Server can send this to the Client owner
@rpc("any_peer", "call_local", "reliable")
func _rpc_equip_weapon(weapon_path: String) -> void:
	# SECURITY: Only trust this command if it came from the Server (ID 1) or local execution (ID 0)
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0:
		push_warning("Cheat detected: Unauthorized weapon equip attempt.")
		return

	var new_weapon: WeaponData = load(weapon_path) as WeaponData
	if new_weapon == null:
		push_error("Failed to load weapon data at: ", weapon_path)
		return
		
	_inventory.append(new_weapon)
	
	# Sync Netfox deterministic timer
	_fire_ticks.append(NetworkTime.tick + new_weapon.fire_rate_ticks)
	
# --- Combat Execution ---
func process_weapons(tick: int, is_fresh: bool) -> void:
	for i in range(_inventory.size()):
		var weapon: WeaponData = _inventory[i]
		
		if tick >= _fire_ticks[i]:
			_fire_ticks[i] = tick + weapon.fire_rate_ticks
			
			# Server decides WHEN to fire, relying on RPC for local visual execution
			if is_fresh and multiplayer.is_server():
				_rpc_fire_bullets.rpc(weapon.pattern_id)

# CHANGED: "authority" to "any_peer" so the Server can send this to the Client owner
@rpc("any_peer", "call_local", "reliable")
func _rpc_fire_bullets(pattern_id: String) -> void:
	# SECURITY: Only trust this command if it came from the Server (ID 1) or local execution (ID 0)
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0:
		return
	print(pattern_id)
	# Executed locally on all clients without syncing raw bullet data
	if _spawn_point != null:
		Spawning.spawn(_spawn_point, pattern_id)
