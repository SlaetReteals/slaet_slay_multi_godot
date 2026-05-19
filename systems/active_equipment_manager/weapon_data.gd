@tool
class_name WeaponData
extends Resource

const EQUIPMENT_LIBRARY_PATH := "res://systems/active_equipment_library.tscn"
var pattern_id: String = ""
@export var fire_rate_ticks: int = 15

func _get_property_list() -> Array[Dictionary]:
	var scene: PackedScene = ResourceLoader.load(EQUIPMENT_LIBRARY_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	if not scene:
		return []

	var identifiers: PackedStringArray = []
	var state: SceneState = scene.get_state()
	var target_base_path: String = ""

	# Pass 1: Resolve the topological path of the target parent node
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == "SpawnPattern":
			target_base_path = str(state.get_node_path(i))
			break

	if target_base_path.is_empty():
		return []

	var expected_depth: int = target_base_path.count("/") + 1
	
	# Pass 2: Extract child nodes and parse their serialized property arrays
	for i in range(state.get_node_count()):
		var current_path := str(state.get_node_path(i))
		
		if current_path.begins_with(target_base_path + "/") and current_path.count("/") == expected_depth:
			# Pass 3: Iterate the property schema for the specific node index
			for p in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p) == "id":
					var exported_id = state.get_node_property_value(i, p)
					if exported_id is String and not exported_id.is_empty():
						identifiers.append(exported_id)
					break # Halt property iteration once target is resolved

	if identifiers.is_empty():
		return []

	return [{
		"name": "pattern_id",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(identifiers)
	}]
