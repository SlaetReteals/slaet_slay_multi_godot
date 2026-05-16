class_name ActivePlayerEquipment
extends Node2D

# --- Node References ---
@export var _bullet_spawn_point: Node2D

# --- Static Weapon Definitions ---
@export var inventory: Array[WeaponData] = []

# --- Netfox Synchronized State ---
@export var _next_fire_ticks: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]

func _ready() -> void:
	# Pre-allocate the inventory slots with 'null' to match our 8 tick timers
	inventory.resize(_next_fire_ticks.size())

# --- DYNAMIC INVENTORY MANAGEMENT ---

# Called during the Player's _ready() to bypass network latency and race conditions
func initialize_default_weapon(weapon_resource_path: String, slot_index: int) -> void:
	# 1. Every machine loads the resource locally from their own hard drive
	var new_weapon: WeaponData = load(weapon_resource_path) as WeaponData
	
	if new_weapon == null:
		push_error("Failed to load default weapon at path: ", weapon_resource_path)
		return
		
	# 2. Assign it to the static array
	inventory[slot_index] = new_weapon
	
	# 3. ONLY the Server sets the synchronized Netfox timer to maintain authority
	if multiplayer.is_server():
		_next_fire_ticks[slot_index] = NetworkTime.tick + new_weapon.fire_rate_ticks

# Entry Point: Call this ONLY on the Server when a player triggers a pickup mid-match
func grant_weapon(weapon_resource_path: String, slot_index: int) -> void:
	if not multiplayer.is_server():
		push_warning("Only the server can grant weapons!")
		return
		
	# Boundary validation for our 8-slot limit
	if slot_index < 0 or slot_index >= _next_fire_ticks.size():
		push_error("Invalid weapon slot index: ", slot_index)
		return
		
	# Broadcast the validated loadout change to all peers (including the server itself)
	_rpc_equip_weapon.rpc(weapon_resource_path, slot_index)

@rpc("authority", "call_local", "reliable")
func _rpc_equip_weapon(weapon_resource_path: String, slot_index: int) -> void:
	# 1. Load the Resource locally on the client machine
	var new_weapon: WeaponData = load(weapon_resource_path) as WeaponData
	
	if new_weapon == null:
		push_error("Failed to load weapon data at path: ", weapon_resource_path)
		return
		
	# 2. Assign it to the static array
	inventory[slot_index] = new_weapon
	
	# 3. Synchronize the Netfox Determinism Timer
	_next_fire_ticks[slot_index] = NetworkTime.tick + new_weapon.fire_rate_ticks

# --- COMBAT EXECUTION ---

func process_weapons(tick: int, is_fresh: bool) -> void:
	for i in range(inventory.size()):
		var current_weapon: WeaponData = inventory[i]
		
		if current_weapon == null:
			continue
			
		# 1. Deterministic Tick Evaluation
		if tick >= _next_fire_ticks[i]:
				
			# 2. Update the future target tick for this specific slot
			_next_fire_ticks[i] = tick + current_weapon.fire_rate_ticks
			
			# 3. Only the multiplayer authority triggers the spawn
			# 4. Gated by is_fresh to prevent duplicate visual firing during rollback
			if is_multiplayer_authority() and is_fresh:
				_rpc_fire_bullets.rpc(current_weapon.pattern_id)

@rpc("authority", "call_local", "reliable")
func _rpc_fire_bullets(pattern_id: String) -> void:
	# BulletUpHell takes over and handles the optimized rendering locally on all clients
	Spawning.spawn(_bullet_spawn_point, pattern_id)
