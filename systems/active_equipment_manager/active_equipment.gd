extends Node2D

# --- Node References ---

# --- Static Weapon Definitions ---
var inventory: Array[WeaponData] = []

# --- Netfox Synchronized State ---
var _next_fire_ticks: Array[int] = []

func _ready() -> void:
	pass

# --- DYNAMIC INVENTORY MANAGEMENT ---

# Called during the Player's _ready() to bypass network latency and race conditions
#func initialize_default_weapon(weapon_resource_path: String, slot_index: int) -> void:
	## 1. Every machine loads the resource locally from their own hard drive
	#var new_weapon: WeaponData = load(weapon_resource_path) as WeaponData
	#if new_weapon == null:
		#push_error("Failed to load default weapon at path: ", weapon_resource_path)
		#return
	#if not inventory.has(new_weapon):
		#print(inventory)
		#var target_pattern_id: String = new_weapon.pattern_id
		## 2. Assign it to the static array
		#inventory[slot_index] = new_weapon
		#print(inventory)
		#print(target_pattern_id)
		#Spawning.create_pool(target_pattern_id,'0',200)
		## 3. ONLY the Server sets the synchronized Netfox timer to maintain authority
		#if multiplayer.is_server():
			#_next_fire_ticks[slot_index] = NetworkTime.tick + new_weapon.fire_rate_ticks
		##Spawning.spawn(self,target_pattern_id,"0")
	##spawn(spawner, id:String, shared_area:String="0"):

# Entry Point: Call this ONLY on the Server when a player triggers a pickup mid-match
func grant_weapon(weapon_resource_path: String, slot_index: int) -> void:
	#if not multiplayer.is_server():
	#	push_warning("Only the server can grant weapons!")
	#	return
		
	# Boundary validation for our 8-slot limit
	if slot_index < 0:
		push_error("Invalid weapon slot index: ", slot_index)
		return
		
	# Broadcast the validated loadout change to all peers (including the server itself)
#	inventory.append(slot_index)


	_rpc_equip_weapon(weapon_resource_path, slot_index)

func _rpc_equip_weapon(weapon_resource_path: String, _slot_index: int) -> void:
	# 1. Load the Resource locally on the client machine
	var new_weapon: WeaponData = load(weapon_resource_path) as WeaponData
	print("equiped weapon")
	if new_weapon == null:
		push_error("Failed toq load weapon data at path: ", weapon_resource_path)
		return

	if not inventory.has(new_weapon):
			inventory.append(new_weapon)
			var target_pattern_id: String = new_weapon.pattern_id
			Spawning.create_pool(target_pattern_id,'0',200)	
	# 2. Assign it to the static array
	#inventory[slot_index] = new_weapon
	
		# 3. Synchronize the Netfox Determinism Timer
			_next_fire_ticks.append(NetworkTime.tick + new_weapon.fire_rate_ticks)

# --- COMBAT EXECUTION ---

func process_weapons(tick: int, is_fresh: bool, bullet_spawn_point: Node2D) -> void:
	for i in range(inventory.size()):
		var current_weapon: WeaponData = inventory[i]
		if current_weapon == null:
			continue
# 1. Deterministic Tick Evaluation (Calculated simultaneously on all peers)
		if tick >= _next_fire_ticks[i]:
			print(_next_fire_ticks[i])
			# 2. Update the future target tick for this specific slot
			_next_fire_ticks[i] = tick + current_weapon.fire_rate_ticks
			
			# 3. Trigger Locally on ALL machines! 
			# Gated by is_fresh to prevent duplicate visual firing during network rollback resimulations.
			if is_fresh:
				print(tick)
				if is_multiplayer_authority():
					print('server pew')
					Spawning.spawn(bullet_spawn_point, current_weapon.pattern_id)
