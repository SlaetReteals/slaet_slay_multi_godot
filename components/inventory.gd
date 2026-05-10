# TemplateVersion: 1.4.0
extends Node
class_name InventoryComponent

signal inventory_updated(items)
@export var max_capacity: int = 10
var items: Array[String] = []

func add_item(item_id: String) -> bool:
    if not multiplayer.is_server(): return false
    if items.size() < max_capacity:
        items.append(item_id)
        inventory_updated.emit(items)
        return true
    return false