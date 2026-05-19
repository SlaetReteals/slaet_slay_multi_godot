extends Node

# Export the default pool size so you can adjust it in the Inspector
@export var default_pool_size: int = 200

# We track initialized IDs to prevent creating duplicate pools 
# (since BulletPattern and SpawnPattern nodes often share the same ID string)
var _initialized_pools: Array[String] = []

func _ready() -> void:
	# Defer to ensure the Spawning autoload is completely ready
	call_deferred("_initialize_bullet_pools")

func _initialize_bullet_pools() -> void:
	# Start the recursive scan from the root of this Autoload
	_scan_and_pool($BulletPatterns)
	print("ProjectileLibrary: All dynamic BulletUpHell pools successfully initialized.")

func _scan_and_pool(parent_node: Node) -> void:
	for child in parent_node.get_children():
		
		# 1. Duck Typing: Check if the node has an 'id' variable
		if "id" in child:
			var raw_id: Variant = child.get("id")
			
			# 2. Validate it's a valid String
			if raw_id is String and raw_id != "":
				var pattern_id: String = raw_id as String
				
				# 3. Create the pool if we haven't already
				if not _initialized_pools.has(pattern_id):
					Spawning.create_pool(pattern_id, "0", default_pool_size)
					_initialized_pools.append(pattern_id)
					print("ProjectileLibrary: Auto-created pool for ID -> ", pattern_id)
		
		# 4. Recursion: If this child has its own children, scan them too!
		if child.get_child_count() > 0:
			_scan_and_pool(child)
