class_name WeightedTable
extends RefCounted

var items: Array[Dictionary] = []
var weight_sum: int = 0

func add_item(item: Variant, weight: int) -> void:
	items.append({ "item": item, "weight": weight })
	weight_sum += weight

func pick_item(exclude: Array = []) -> Variant:
	var adjusted_items: Array[Dictionary] = []
	var adjusted_weight_sum: int = 0
	
	for item in items:
		if item["item"] in exclude:
			continue
		adjusted_items.append(item)
		adjusted_weight_sum += item["weight"] as int
		
	if adjusted_weight_sum <= 0: return null
	
	var chosen_weight: int = randi_range(1, adjusted_weight_sum)
	var iteration_sum: int = 0
	
	for item in adjusted_items:
		iteration_sum += item["weight"] as int
		if chosen_weight <= iteration_sum:
			return item["item"]
	return null
# Use Variant for the item since it could be an AbilityUpgrade, String, or Node
func remove_item(item_to_remove: Variant) -> void:
	# Loop backward through the array so removing items doesn't break the index
	for i in range(items.size() - 1, -1, -1):
		var current_item: Dictionary = items[i]
		
		if current_item["item"] == item_to_remove:
			# Subtract the weight from your total pool to keep the math accurate
			weight_sum -= current_item["weight"] as int
			
			# Remove the item from the array
			items.remove_at(i)
			
			# Break out of the loop since we found and removed it
			break
