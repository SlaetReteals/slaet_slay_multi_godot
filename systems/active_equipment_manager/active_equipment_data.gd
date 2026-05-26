@tool
class_name BulletProp
extends Resource

const EQUIPMENT_LIBRARY_PATH := "res://systems/active_equipment_library.tscn"

# 1. Native Export: Guarantees disk serialization and persistent state
@export var pattern_id: String = ""
# ticks are 1/60th of a second
@export var fire_rate_ticks: int = 120
@export var shared_area: String = "0"

# 2. Validation Override: Mutates the UI rendering of the natively exported variable
func _validate_property(property: Dictionary) -> void:
	if property.name == "pattern_id":
		var identifiers: PackedStringArray = _fetch_scene_identifiers()
		# Only convert to Enum dropdown if valid identifiers are harvested
		if not identifiers.is_empty():
			property.hint = PROPERTY_HINT_ENUM
			property.hint_string = ",".join(identifiers)

# 3. Extracted Topological Scan Matrix
func _fetch_scene_identifiers() -> PackedStringArray:
	var scene: PackedScene = ResourceLoader.load(EQUIPMENT_LIBRARY_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	if not scene:
		return []
		
	var identifiers: PackedStringArray = []
	var state: SceneState = scene.get_state()
	var target_base_path: String = ""

	# Pass 1: Resolve structural root node path
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == "SpawnPattern":
			target_base_path = str(state.get_node_path(i))
			break

	if target_base_path.is_empty():
		return []
		
	var subtree_prefix: String = target_base_path + "/"

	# Pass 2: Extract target IDs via sub-tree prefix matching
	for i in range(state.get_node_count()):
		var current_path: String = str(state.get_node_path(i))
		
		# Validation allows infinite nested depth under target parent

		if current_path.begins_with(subtree_prefix):
			for p in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p) == "id":
					var exported_id = state.get_node_property_value(i, p)
					if exported_id.begins_with("bullet"):
						pass
					elif typeof(exported_id) == TYPE_STRING and not exported_id.is_empty():
						identifiers.append(exported_id)
					break # Optimal early exit on property hit
					
	return identifiers
