class_name SpawnActiveEquipment
extends Area2D

# Export a path so you can drag-and-drop the WeaponData resource in the Inspector
@export_file("*.tres") var equipment_resource_path: String

func _ready() -> void:
	# Connect the signal via code to ensure it's always hooked up
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# STRICT RULE: Server Authority. 
	# The Area2D body_entered signal MUST be gated behind this check.
	if not multiplayer.is_server():
		return
		
	# Check if the body that collided is our Player class
	if body is Player:
		var player: Player = body as Player
		
		if player.equipment_component != null:
			# The server triggers the component, which handles the RPCs to clients
			player.equipment_component.grant_active_equipment.call_deferred(equipment_resource_path)
			
			# The server deletes the pickup. 
			# If this pickup was spawned via MultiplayerSpawner, Godot natively despawns it on all clients.
			queue_free()
