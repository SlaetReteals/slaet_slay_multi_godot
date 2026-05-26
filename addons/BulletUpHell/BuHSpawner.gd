@tool
class_name BulletUpHellManager
extends Node2D

# ---------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------
signal bullet_collided_area(area: Area2D, area_shape_index: int, bullet: Dictionary, local_shape_index: int, shared_area: Area2D)
signal bullet_collided_body(body: Node, body_shape_index: int, bullet: Dictionary, local_shape_index: int, shared_area: Area2D)

# ---------------------------------------------------------
# CONSTANTS & ENUMS
# ---------------------------------------------------------
const STANDARD_BULLET_RADIUS: int = 5
const UNACTIVE_ZONE: Vector2 = Vector2(99999, 99999)
const HOMING_MARGIN: int = 20

const ACTION_SPAWN: int = 0
const ACTION_SHOOT: int = 1
const ACTION_BOTH: int = 2

enum BState { Unactive, Spawning, Spawned, Shooting, Moving, QueuedFree }
enum GROUP_SELECT { Nearest_on_homing, Nearest_on_spawn, Nearest_on_shoot, Nearest_anywhen, Random }
enum SYMTYPE { ClosedShape, Line }
enum CURVE_TYPE { None, LoopFromStart, OnceThenDie, OnceThenStay, LoopFromEnd }
enum LIST_ENDS { Stop, Loop, Reverse }
enum ANIM { TEXTURE, COLLISION, SFX, SCALE, SKEW }

# ---------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------
@export var GROUP_BOUNCE: String = "Slime"

@export_group("Resource Lists")
@export var default_idle: animState
@export var default_spawn: animState
@export var default_shoot: animState
@export var default_waiting: animState
@export var default_delete: animState

# ---------------------------------------------------------
# STATE VARIABLES & DATA STRUCTS
# ---------------------------------------------------------
var arrayProps: Dictionary = {}
var arrayTriggers: Dictionary = {}
var arrayPatterns: Dictionary = {}
var arrayContainers: Dictionary = {}
var arrayInstances: Dictionary = {}
var arrayAnim: Dictionary = {}
var arrayShapes: Dictionary = {} 

var poolBullets: Dictionary = {}
var inactive_pool: Dictionary = {}
var shape_indexes: Dictionary = {}
var shape_rids: Dictionary = {}
var poolQueue: Array = []
var poolTimes: Array = []

var loop_length: float = 9999.0
var time: float = 0.0
var _delta: float = 0.0
var global_reset_counter: int = 0

var RAND: RandomNumberGenerator = RandomNumberGenerator.new()
var expression: Expression = Expression.new()

@onready var textures: SpriteFrames = $ShapeManager.sprite_frames
@onready var viewrect: Rect2 = get_viewport().get_visible_rect()
@onready var phys = PhysicsServer2D
@onready var shared_areas: Node2D = $SharedAreas

# ---------------------------------------------------------
# ENGINE LOOPS
# ---------------------------------------------------------
func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	randomize()
	
	$ShapeManager.hide()
	for s in $ShapeManager.get_children():
		assert(s is CollisionShape2D or s is CollisionPolygon2D)
		if s.shape: arrayShapes[s.name] = [s.shape, s.position, s.rotation]
		s.queue_free()
		
	_initialize_shared_areas()
	$Bouncy.global_position = UNACTIVE_ZONE

	var default_anims: Array[animState] = [default_idle, default_spawn, default_shoot, default_waiting, default_delete]
	for a in default_anims.size():
		default_anims[a].ID = "@" + ["anim_idle", "anim_spawn", "anim_shoot", "anim_waiting", "anim_delete"][a]
		set_anim_states(default_anims[a])

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_delta = delta

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return

	if not poolBullets.is_empty():
		_process_bullet_movement(delta)
		queue_redraw()

	_process_action_queue(delta)

# ---------------------------------------------------------
# REFACTORED PROCESS HELPERS
# ---------------------------------------------------------
func _initialize_shared_areas() -> void:
	for area in shared_areas.get_children():
		if area is Area2D:
			area.area_shape_entered.connect(bullet_collide_area.bind(area))
			area.body_shape_entered.connect(bullet_collide_body.bind(area))
			area.set_meta("ShapeCount", 0)

func _process_bullet_movement(delta: float) -> void:
	bullet_movement(delta)

func _process_action_queue(delta: float) -> void:
	time += delta
	if time >= loop_length: time = 0.0
		
	while not poolQueue.is_empty() and poolTimes[0] < time:
		var next_in_queue = poolQueue[0]
		match next_in_queue[0]:
			ACTION_SPAWN: _spawn(next_in_queue[1])
			ACTION_SHOOT: _shoot(next_in_queue[1])
			ACTION_BOTH: _spawn_and_shoot(next_in_queue[1], next_in_queue[2])
		poolQueue.pop_front()
		poolTimes.pop_front()

func reset(minimal: bool = false):
	global_reset_counter += 1
	reset_bullets()
	inactive_pool.clear()
	shape_rids.clear()
	poolQueue.clear()
	poolTimes.clear()
	time = 0
	_delta = 0
	for a in $SharedAreas.get_children():
		a.set_meta("ShapeCount", 0)
	$Bouncy.global_position = UNACTIVE_ZONE
	if not minimal:
		arrayContainers.clear()
		arrayInstances.clear()
		arrayPatterns.clear()
		arrayTriggers.clear()
		arrayProps.clear()
	else:
		for array in [arrayContainers, arrayInstances, arrayPatterns, arrayProps, arrayTriggers, arrayAnim]:
			for elem in array.keys():
				if elem[0] == "@": continue
				array.erase(elem)

func change_scene_to_file(file: String):
	reset_bullets()
	get_tree().change_scene_to_file(file)

func change_scene_to_packed(scene: PackedScene):
	reset_bullets()
	get_tree().change_scene_to_packed(scene)

func reset_bullets():
	clear_all_bullets()

# =========================================================
# RESOURCE MANAGEMENT
# =========================================================
func new_instance(id: String, instance: Node2D):
	if arrayInstances.has(id):
		push_warning("Warning : New instance ignored. Name " + id + " already exists.")
		return
	arrayInstances[id] = instance

func new_trigger(id: String, t: RichTextEffect):
	if arrayTriggers.has(id):
		push_warning("Warning : New trigger ignored. Name " + id + " already exists.")
		return
	arrayTriggers[id] = t

func new_pattern(id: String, p: Pattern):
	if arrayPatterns.has(id):
		push_warning("Warning : New pattern ignored. Name " + id + " already exists.")
		return
	arrayPatterns[id] = p

func new_bullet(id: String, bullet: Dictionary):
	if arrayProps.has(id):
		push_warning("Warning : New bullet ignored. Name " + id + " already exists.")
		return
	arrayProps[id] = bullet

func new_container(node):
	if arrayContainers.has(node.id):
		push_warning("Warning : New container ignored. Name " + node.id + " already exists.")
		return
	arrayContainers[node.id] = node

func instance(id: String) -> Node2D:
	assert(arrayInstances.has(id), "Trying to get the scene instance named " + id + ", which doesn't exist.")
	return arrayInstances[id]

func trigger(id: String):
	assert(arrayTriggers.has(id), "Trying to get the trigger " + id + ", which doesn't exist.")
	return arrayTriggers[id]

func pattern(id: String):
	assert(arrayPatterns.has(id), "Trying to get the pattern " + id + ", which doesn't exist.")
	return arrayPatterns[id]

func bullet(id: String):
	assert(arrayProps.has(id), "Trying to get the bulletprops " + id + ", which doesn't exist.")
	return arrayProps[id]

func container(id: String):
	assert(arrayContainers.has(id), "Trying to get the trigger container " + id + ", which doesn't exist.")
	return arrayContainers[id]

func set_anim_states(anim_state: animState, prefix: String = "", base_id: String = "") -> String:
	if anim_state.ID == "": 
		anim_state.ID = "@" + base_id + "_" + prefix
	var collision_shape
	var sound_effect
	if anim_state.texture == "": 
		anim_state.texture = arrayAnim["@" + prefix][ANIM.TEXTURE]
	if anim_state.collision == "": 
		collision_shape = arrayAnim["@" + prefix][ANIM.COLLISION]
	else: 
		collision_shape = arrayShapes[anim_state.collision]
	if anim_state.SFX == "": 
		sound_effect = null
	else: 
		sound_effect = $SFX.get_node(anim_state.SFX)

	arrayAnim[anim_state.ID] = [
		anim_state.texture, 
		collision_shape, 
		sound_effect, 
		anim_state.tex_scale, 
		anim_state.tex_skew
	]
	
	return anim_state.ID
# =========================================================
# POOLING
# =========================================================
func create_pool(bullet: String, shared_area: String, amount: int, object: bool = false):
	var properties: Dictionary = arrayProps[bullet]
	if not inactive_pool.has(bullet):
		inactive_pool[bullet] = []
		inactive_pool["__SIZE__" + bullet] = 0

	if object:
		for i in amount:
			inactive_pool[bullet].append(instance(properties["instance_id"]).duplicate())
	else:
		var shared_rid: RID = get_shared_area_rid(shared_area)
		var count: int = phys.area_get_shape_count(shared_rid)
		var new_rid: RID
		var shared_area_node = _ensure_shared_area(shared_area)		
		for i in amount:
			new_rid = create_shape(shared_rid, arrayAnim[properties["anim_spawn"]][ANIM.COLLISION], true, count + i)
			_update_shape_indexes(new_rid, count + i, shared_area)
			inactive_pool[bullet].append([new_rid, shared_area])
	inactive_pool["__SIZE__" + bullet] += amount

func wake_from_pool(bullet: String, queued_instance: Dictionary, shared_area: String, object: bool = false):
	# 1. Initialize the pool if it doesn't exist or is completely empty
	if not inactive_pool.has(bullet):
		create_pool(bullet, shared_area, 50, object)
	elif inactive_pool[bullet].is_empty():
		create_pool(bullet, shared_area, max(inactive_pool["__SIZE__" + bullet] / 10, 50), object)

	if inactive_pool[bullet][0] is Array:
		var i: int = 0
		var found: bool = false
		
		# 2. Safely search the pool for a bullet mapped to our specific shared_area
		while i < inactive_pool[bullet].size():
			if inactive_pool[bullet][i][1] == shared_area:
				found = true
				break
			i += 1
			
		# 3. If we searched the whole pool and found nothing, create a batch for this specific area!
		if not found:
			create_pool(bullet, shared_area, 50, object)
			# Point our index to the first newly created bullet (which was appended to the end)
			i = inactive_pool[bullet].size() - 50 
			
		# 4. Pop the valid bullet from the pool and assign it
		var bID = inactive_pool[bullet].pop_at(i)[0]
		poolBullets[bID] = queued_instance
		return bID
	else:
		return inactive_pool[bullet].pop_at(0)

func back_to_grave(bullet: String, bID):
	inactive_pool[bullet].append([bID, poolBullets[bID]["shared_area"].name])
	poolBullets[bID]["state"] = BState.QueuedFree
	if bID is Node2D: bID.get_parent().remove_child(bID)

func create_shape(shared_rid: RID, ColID: Array, init: bool = false, count: int = 0) -> RID:
	var new_shape: RID
	var template_shape = ColID[0]
	if template_shape is CircleShape2D:
		new_shape = phys.circle_shape_create()
		phys.shape_set_data(new_shape, template_shape.radius)
	elif template_shape is CapsuleShape2D:
		new_shape = phys.capsule_shape_create()
		phys.shape_set_data(new_shape, [template_shape.radius, template_shape.height])
	elif template_shape is ConcavePolygonShape2D:
		new_shape = phys.concave_polygon_shape_create()
		phys.shape_set_data(new_shape, template_shape.segments)
	elif template_shape is ConvexPolygonShape2D:
		new_shape = phys.convex_polygon_shape_create()
		phys.shape_set_data(new_shape, template_shape.points)
	elif template_shape is WorldBoundaryShape2D:
		new_shape = phys.line_shape_create()
		phys.shape_set_data(new_shape, [template_shape.d, template_shape.normal])
	elif template_shape is SeparationRayShape2D:
		new_shape = phys.separation_ray_shape_create()
		phys.shape_set_data(new_shape, [template_shape.length, template_shape.slide_on_slope])
	elif template_shape is RectangleShape2D:
		new_shape = phys.rectangle_shape_create()
		phys.shape_set_data(new_shape, template_shape.extents)
	elif template_shape is SegmentShape2D:
		new_shape = phys.segment_shape_create()
		phys.shape_set_data(new_shape, [template_shape.a, template_shape.bullet])

	phys.area_add_shape(shared_rid, new_shape, Transform2D(ColID[2], ColID[1] + (UNACTIVE_ZONE * int(init))))
	if count == 0: count = phys.area_get_shape_count(shared_rid)
	phys.area_set_shape_disabled(shared_rid, count - 1, true)
	return new_shape

# =========================================================
# SPAWN
# =========================================================
func set_angle(pattern: Pattern, pos: Vector2, queued_instance: Dictionary):
	if pattern.forced_target != NodePath() and is_instance_valid(pattern.node_target):
		if pattern.forced_pattern_lookat: queued_instance["rotation"] = pos.angle_to_point(pattern.node_target.global_position)
		else: queued_instance["rotation"] = (pos + queued_instance["spawn_pos"]).angle_to_point(pattern.node_target.global_position)
	elif pattern.forced_lookat_mouse:
		if pattern.forced_pattern_lookat: queued_instance["rotation"] = pos.angle_to_point(get_global_mouse_position())
		else: queued_instance["rotation"] = (pos + queued_instance["spawn_pos"]).angle_to_point(get_global_mouse_position())
	elif pattern.forced_angle != 0.0:
		queued_instance["rotation"] = pattern.forced_angle

func create_bullet_instance_dict(queued_instance: Dictionary, bullet_props: Dictionary, pattern: Pattern):
	queued_instance["shape_disabled"] = true
	queued_instance["speed"] = bullet_props.speed
	queued_instance["vel"] = Vector2()
	if bullet_props.has("groups"): queued_instance["groups"] = bullet_props.get("groups")
	return queued_instance
func _ensure_shared_area(area_name: String) -> Area2D:
	# 1. If it already exists, just return it
	if $SharedAreas.has_node(area_name):
		return $SharedAreas.get_node(area_name) as Area2D
		
	# 2. If it doesn't exist, create it!
	var new_area = Area2D.new()
	new_area.name = area_name
	$SharedAreas.add_child(new_area)
	
	# 3. Connect the critical BulletUpHell collision signals
	new_area.area_shape_entered.connect(bullet_collide_area.bind(new_area))
	new_area.body_shape_entered.connect(bullet_collide_body.bind(new_area))
	new_area.set_meta("ShapeCount", 0)
	
	# ==========================================
	# 4. ASSIGN COLLISION LAYERS BASED ON NAME
	# ==========================================
	
	# First, set the MASK so the bullets know what to hit. 
	# (e.g., if enemies are on Layer 3, mask is 1 << 2)
	new_area.collision_mask = (1 << 8)#9
	
	# Then, set the LAYER based on the string name to match your HurtboxComponent!
	match area_name:
		"bullet_ice":
			new_area.collision_layer = (1 << 10) # Godot Layer 11
		"bullet_earth":
			new_area.collision_layer = (1 << 11) # Godot Layer 12
		"basic":
			new_area.collision_layer = (1 << 9)  # Godot Layer 10
		_:
			# Default fallback if you send a name that isn't in the list
			new_area.collision_layer = (1 << 9)
			
	print("[BuHSpawner] Auto-created Shared Area: ", area_name, " | Layer: ", new_area.collision_layer)
	return new_area
func set_spawn_data(queued_instance: Dictionary, bullet_props: Dictionary, pattern: Pattern, i: int, ori_angle: float):
	var angle: float
	match pattern.resource_name:
		"PatternCircle":
			angle = (pattern.angle_total / pattern.nbr) * i + pattern.angle_decal
			queued_instance["spawn_pos"] = Vector2(cos(angle) * pattern.radius, sin(angle) * pattern.radius).rotated(pattern.pattern_angle)
			queued_instance["rotation"] = angle + bullet_props.angle + ori_angle
		"PatternLine":
			queued_instance["spawn_pos"] = Vector2(pattern.offset.x * (-abs(pattern.center - i - 1)) - pattern.nbr / 2 * pattern.offset.x, pattern.offset.y * i - pattern.nbr / 2 * pattern.offset.y).rotated(pattern.pattern_angle)
			queued_instance["rotation"] = bullet_props.angle + pattern.pattern_angle + ori_angle
		"PatternOne":
			queued_instance["spawn_pos"] = Vector2()
			queued_instance["rotation"] = bullet_props.angle + ori_angle
		"PatternCustomShape", "PatternCustomPoints":
			queued_instance["spawn_pos"] = pattern.pos[i]
			queued_instance["rotation"] = bullet_props.angle + pattern.angles[i] + ori_angle
		"PatternCustomArea":
			queued_instance["spawn_pos"] = pattern.pos[randi() % pattern.pooling][i]
			queued_instance["rotation"] = bullet_props.angle + ori_angle

func spawn(spawner, id: String, shared_area: String = "0"):
	assert(arrayPatterns.has(id))
	var local_reset_counter: int = global_reset_counter
	var bullets: Array
	var pattern: Pattern = arrayPatterns[id]
	var iter: int = pattern.iterations
	var shared_area_node = _ensure_shared_area(shared_area)
	var pos: Vector2; var ori_angle: float;
	var bullet_props: Dictionary; var queued_instance: Dictionary; 
	var bID; var is_object: bool; var is_bullet_node: bool
	var tw_endpos: Vector2;

	while iter != 0:
		if spawner == null: return
		if spawner is Node2D:
			ori_angle = spawner.rotation
			pos = spawner.global_position
		elif spawner is Dictionary:
			pos = spawner["position"]
			ori_angle = spawner["rotation"]
		else: push_error("spawner isn't a Node2D or a bullet RID")
		
		bullet_props = arrayProps[pattern.bullet]
		if bullet_props.get("has_random", false): bullet_props = create_random_props(bullet_props)

		is_object = bullet_props.has("instance_id")
		is_bullet_node = (is_object and bullet_props.has("speed"))
		
		for i in pattern.nbr:
			queued_instance = {}
			queued_instance["shared_area"] = shared_area_node
			queued_instance["properties"] = bullet_props
			queued_instance["source_node"] = spawner
			queued_instance["state"] = BState.Unactive
			if not is_object:
				queued_instance["anim"] = arrayAnim[bullet_props["anim_idle"]]
				queued_instance["colID"] = queued_instance["anim"][ANIM.COLLISION]
				queued_instance = create_bullet_instance_dict(queued_instance, bullet_props, pattern)
			elif is_bullet_node: queued_instance = create_bullet_instance_dict(queued_instance, bullet_props, pattern)

			set_spawn_data(queued_instance, bullet_props, pattern, i, ori_angle)

			if not bullet_props.get("fixed_rotation", false):
				set_angle(pattern, pos, queued_instance)
			else: queued_instance["rotation"] = 0

			if pattern.wait_tween_momentum > 0:
				tw_endpos = queued_instance["spawn_pos"] + pos + Vector2(pattern.wait_tween_length, 0).rotated(PI + queued_instance["rotation"])
				queued_instance["momentum_data"] = [pattern.wait_tween_momentum - 1, tw_endpos, pattern.wait_tween_time]

			bID = wake_from_pool(pattern.bullet, queued_instance, shared_area, is_object)
			bullets.append(bID)
			poolBullets[bID] = queued_instance

			if is_object:
				if is_bullet_node: bID.bullet = queued_instance
				if bullet_props.has("overwrite_groups"):
					for g in bID.get_groups():
						bID.remove_group(g)
				for g in bullet_props.get("groups", []):
					bID.add_to_group(g)

		_plan_spawning(pattern, bullets)

		if iter > 0: iter -= 1
		await get_tree().create_timer(pattern.cooldown_spawn).timeout
		if local_reset_counter != global_reset_counter: return

func _plan_spawning(pattern: Pattern, bullets: Array):
	# ==========================================
	# BRANCH 1: Synchronous (Instant) Spawning
	# ==========================================
	if pattern.cooldown_next_spawn == 0:
		_spawn(bullets) # Materialize all projectiles into the scene tree simultaneously
		if pattern.cooldown_stasis: return # Abort further logic if projectiles are flagged as static hazards

		var to_shoot = bullets.duplicate() # Decouple array reference to prevent mutation faults during iteration

		# Sub-Branch 1A: Synchronous Firing
		if pattern.cooldown_next_shoot == 0:
			if pattern.cooldown_shoot == 0: 
				_shoot(to_shoot) # Zero-delay immediate trigger for the entire array
			else: 
				plan_shoot(to_shoot, pattern.cooldown_shoot) # Apply global uniform delay before firing the entire array
		
		# Sub-Branch 1B: Asynchronous (Staggered) Firing
		else:
			for bullet in to_shoot:
				var sz = to_shoot.size()
				for idx in range(sz):
					var b = to_shoot[idx] # Retrieve the sequential index of the current projectile
					if pattern.symmetric:
						match pattern.symmetry_type:
							# Linear topology: Firing delay scales by absolute distance from the pattern's conceptual center
							SYMTYPE.Line: plan_shoot([bullet], pattern.cooldown_shoot + (abs(pattern.center - idx)) * pattern.cooldown_next_shoot)
							# Radial/Closed topology: Firing delay scales by the shortest bidirectional path to the origin
							SYMTYPE.ClosedShape: plan_shoot([bullet], pattern.cooldown_shoot + (min(idx - pattern.center, to_shoot.size() - (idx - pattern.center))) * pattern.cooldown_next_shoot)
					# Asymmetric topology: Firing delay scales linearly based purely on array sequence
					else: plan_shoot([bullet], pattern.cooldown_shoot + idx * pattern.cooldown_next_shoot)

	# ==========================================
	# BRANCH 2: Asynchronous (Staggered) Spawning
	# ==========================================
	else:
		var idx
		unactive_spawn(bullets) # Pre-allocate objects into memory but defer active physics/rendering states
		var to_spawn = bullets.duplicate()
		
		# Phase 1: Schedule Spawning Offsets
		for bullet in to_spawn:
			idx = to_spawn.find(bullet)
			if pattern.symmetric:
				match pattern.symmetry_type:
					SYMTYPE.Line: plan_spawn([bullet], abs(pattern.center - idx) * pattern.cooldown_next_spawn)
					SYMTYPE.ClosedShape: plan_spawn([bullet], min(idx - pattern.center, to_spawn.size() - (idx - pattern.center)) * pattern.cooldown_next_spawn)
			else: plan_spawn([bullet], idx * pattern.cooldown_next_spawn)

		if pattern.cooldown_stasis: return # Halt execution for static hazards

		# Phase 2: Schedule Firing Offsets (Relative to deferred spawning completion)
		
		# Case A: Simultaneous fire, triggered only after the entire array finishes staggering its spawns
		if pattern.cooldown_next_shoot == 0 and pattern.cooldown_shoot > 0:
			plan_shoot(to_spawn, pattern.cooldown_next_spawn * (to_spawn.size()) + pattern.cooldown_shoot)
		
		# Case Bullets: Simultaneous fire with zero global delay, cascading immediately after individual spawns
		elif pattern.cooldown_next_shoot == 0:
			for bullet in to_spawn:
				idx = to_spawn.find(bullet)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: plan_shoot([bullet], pattern.cooldown_shoot + (abs(pattern.center - idx)) * pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: plan_shoot([bullet], pattern.cooldown_shoot + (min(idx - pattern.center, to_spawn.size() - (idx - pattern.center))) * pattern.cooldown_next_shoot)
				else: plan_shoot([bullet], idx * pattern.cooldown_next_spawn) 
		
		# Case C: Staggered fire with zero global shoot delay
		elif pattern.cooldown_shoot == 0:
			for bullet in to_spawn:
				idx = to_spawn.find(bullet)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: plan_shoot([bullet], pattern.cooldown_shoot + (abs(pattern.center - idx)) * pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: plan_shoot([bullet], pattern.cooldown_shoot + (min(idx - pattern.center, to_spawn.size() - (idx - pattern.center))) * pattern.cooldown_next_shoot)
				else: plan_shoot([bullet], idx * (pattern.cooldown_next_shoot + pattern.cooldown_next_spawn)) # Aggregate spawn delta + shoot delta
		
		# Case D: Staggered fire with global shoot delay offset
		else:
			for bullet in to_spawn:
				idx = to_spawn.find(bullet)
				if pattern.symmetric:
					match pattern.symmetry_type:
						SYMTYPE.Line: plan_shoot([bullet], pattern.cooldown_shoot + (abs(pattern.center - idx)) * pattern.cooldown_next_shoot)
						SYMTYPE.ClosedShape: plan_shoot([bullet], pattern.cooldown_shoot + (min(idx - pattern.center, to_spawn.size() - (idx - pattern.center))) * pattern.cooldown_next_shoot)
				# Calculates maximum offset: Total array spawn duration + global uniform delay + localized iterative delay
				else: plan_shoot([bullet], pattern.cooldown_next_spawn * (to_spawn.size()) + pattern.cooldown_shoot + idx * pattern.cooldown_next_shoot)

	# ==========================================
	# CLEANUP
	# ==========================================
	bullets.clear() # Flush the original array pointer to release references and prevent dual-state memory modifications

func plan_spawn(bullets: Array, spawn_delay: float = 0):
	var timestamp = getKeyTime(spawn_delay)
	var insert_index = poolTimes.bsearch(timestamp)
	poolTimes.insert(insert_index, timestamp)
	poolQueue.insert(insert_index, [ACTION_SPAWN, bullets])

func plan_shoot(bullets: Array, shoot_delay: float = 0):
	for bullet in bullets:
		if (not bullet is RID and not poolBullets[bullet]["properties"].has("speed")): bullets.erase(bullet)
	var timestamp = getKeyTime(shoot_delay)
	var insert_index = poolTimes.bsearch(timestamp)
	poolTimes.insert(insert_index, timestamp)
	poolQueue.insert(insert_index, [ACTION_SHOOT, bullets])

func getKeyTime(delay):
	if loop_length < time + delay: return delay - (loop_length - time)
	else: return time + delay

func _spawn_and_shoot(to_spawn: Array, to_shoot: Array):
	_spawn(to_spawn)
	_shoot(to_shoot)

func unactive_spawn(bullets: Array):
	var Bullets: Dictionary
	for bullet in bullets:
		assert(poolBullets.has(bullet))
		Bullets = poolBullets[bullet]
		if Bullets["state"] >= BState.Moving: continue
		if Bullets["source_node"] is RID: Bullets["position"] = Bullets["spawn_pos"] + poolBullets[Bullets["source_node"]]["position"]
		elif Bullets["source_node"] is Dictionary: Bullets["position"] = Bullets["spawn_pos"] + Bullets["source_node"]["position"]
		else: Bullets["position"] = Bullets["spawn_pos"] + Bullets["source_node"].global_position

func _spawn(bullets: Array):
	var Bullets: Dictionary
	var properties: Dictionary
	for bullet in bullets:
		if not poolBullets.has(bullet):
			push_error("Warning: Bullet of ID " + str(bullet) + " is missing.")
			continue
		Bullets = poolBullets[bullet]
		if Bullets["state"] >= BState.Moving: continue
		if Bullets["source_node"] is Dictionary: Bullets["position"] = Bullets["spawn_pos"] + Bullets["source_node"]["position"]
		else: Bullets["position"] = Bullets["spawn_pos"] + Bullets["source_node"].global_position

		if bullet is Node2D: 
			_spawn_object(bullet, Bullets)

		properties = Bullets["properties"]
		if bullet is RID or properties.has("speed"):
			if not change_animation(Bullets, "spawn", bullet): Bullets["state"] = BState.Spawning
			else: Bullets["state"] = BState.Spawned
			if arrayAnim[properties["anim_spawn"]][ANIM.SFX]: arrayAnim[properties["anim_spawn"]][ANIM.SFX].play()

			init_special_variables(Bullets, bullet)
			if properties.get("homing_select_in_group", -1) == GROUP_SELECT.Nearest_on_spawn:
				target_from_options(Bullets)
		else: poolBullets.erase(bullet)

func _spawn_object(bullet: Node2D, Bullets: Dictionary):
	if bullet is CollisionObject2D:
		bullet.collision_layer = Bullets["shared_area"].collision_layer
		bullet.collision_mask = Bullets["shared_area"].collision_mask
	if Bullets["source_node"] is Dictionary:
		Bullets["source_node"]["source_node"].call_deferred("add_child", bullet)
		bullet.global_position = Bullets["source_node"]["position"] - Bullets["source_node"]["source_node"].position
		bullet.rotation += Bullets["source_node"]["rotation"]
	else:
		bullet.global_position = Bullets["spawn_pos"]
		bullet.rotation += Bullets["rotation"]
		Bullets["source_node"].call_deferred("add_child", bullet)

func use_momentum(pos: Vector2, Bullets: Dictionary):
	Bullets["position"] = pos

func _shoot(bullets: Array):
	var Bullets: Dictionary
	var properties: Dictionary
	for bullet in bullets:
		if not poolBullets.has(bullet): continue
		Bullets = poolBullets[bullet]
		properties = Bullets["properties"]
		if (not bullet is RID and not properties.has("speed")):
			poolBullets.erase(bullet)
			continue

		if Bullets.has("momentum_data"):
			var tween = get_tree().create_tween()
			tween.tween_method(use_momentum.bind(Bullets), Bullets["position"], Bullets["momentum_data"][1], Bullets["momentum_data"][2]).set_trans(Bullets["momentum_data"][0])

		Bullets["state"] = BState.Moving

		if not properties.has("curve"): Bullets.erase("spawn_pos")
		else: Bullets["spawn_pos"] = Bullets["position"]

		if properties.has("homing_target") or properties.has("node_homing"):
			if properties.get("homing_time_start", 0) > 0:
				print("starting Timer")
				get_tree().create_timer(properties["homing_time_start"]).connect("timeout", Callable(self, "_on_Homing_timeout").bind(Bullets, true))
			else: _on_Homing_timeout(Bullets, true)
		if properties.get("homing_select_in_group", -1) == GROUP_SELECT.Nearest_on_shoot:
			print('homing target')
			target_from_options(Bullets)

		if not change_animation(Bullets, "shoot", bullet): Bullets["state"] = BState.Shooting
		if arrayAnim[properties["anim_shoot"]][ANIM.SFX]: arrayAnim[properties["anim_shoot"]][ANIM.SFX].play()

func init_special_variables(bullet: Dictionary, rid):
	var bp = bullet["properties"]
	if bp.has("a_speed_multi_iterations"):
		bullet['speed_multi_iter'] = bp["a_speed_multi_iterations"]
		bullet['speed_interpolate'] = float(0)
	if bp.has("scale_multi_iterations"):
		bullet['scale_multi_iter'] = bp["scale_multi_iterations"]
		bullet['scale_interpolate'] = float(0)
	if bp.has("spec_bounces"):
		bullet['bounces'] = bp["spec_bounces"]
	if bp.has("a_direction_equation"):
		bullet['curve'] = float(0)
		bullet['curveDir_index'] = float(0)
	if bp.has("spec_modulate_loop"): bullet["modulate_index"] = float(0)
	if bp.has("spec_rotating_speed"): bullet["rot_index"] = float(0)
	if bp.has("spec_trail_length"):
		bullet["trail"] = [bullet["position"], bullet["position"], bullet["position"], bullet["position"]]
		bullet["trail_counter"] = float(0.0)
	if bp.has("homing_list"):
		bullet["homing_counter"] = int(0)
	if bp.has("curve"):
		bullet["curve_counter"] = float(0.0)
		if bp["a_curve_movement"] in [CURVE_TYPE.LoopFromStart, CURVE_TYPE.LoopFromEnd]:
			bullet["curve_start"] = bp["curve"].get_point_position(0)
	if bp.has("death_after_time"): bullet["death_counter"] = float(0.0)
	if bp.has("trigger_container"):
		bullet['trig_container'] = container(bp["trigger_container"])
		bullet["trigger_counter"] = int(0)
		var trig_types = bullet['trig_container'].getCurrentTriggers(bullet, rid)
		bullet['trig_types'] = trig_types
		bullet['trig_iter'] = {}
		if trig_types.has("TrigCol"): bullet["trig_collider"] = null
		if trig_types.has("TrigSig"): bullet["trig_signal"] = null
		if trig_types.has("TrigTime"): bullet["trig_timeout"] = false

# =========================================================
# MOVEMENT
# =========================================================
func move_scale(Bullets: Dictionary, properties, delta: float):
	if Bullets.get("scale_multi_iter", 0) == 0: return
	Bullets["scale_interpolate"] += delta
	var _scale = properties["scale"] * properties["scale_multiplier"].sample(Bullets["scale_interpolate"] / properties["scale_multi_scale"])
	Bullets["scale"] = Vector2(_scale, _scale)
	if Bullets["scale_interpolate"] / properties["scale_multi_scale"] >= 1 and properties["scale_multi_iterations"] != -1:
		Bullets["scale_multi_iter"] -= 1

func move_trail(Bullets: Dictionary, properties):
	if not Bullets.has("trail_counter"): return
	Bullets["trail_counter"] += _delta
	if Bullets["trail_counter"] >= properties["spec_trail_length"]:
		Bullets["trail_counter"] = 0
		Bullets["trail"].remove_at(3)
		Bullets["trail"].insert(0, Bullets["position"])

func move_speed(Bullets: Dictionary, properties, delta: float):
	if Bullets.get("speed_multi_iter", 0) == 0: return
	Bullets["speed_interpolate"] += delta
	Bullets["speed"] = properties["a_speed_multiplier"].sample(Bullets["speed_interpolate"] / properties["a_speed_multi_scale"])
	if Bullets["speed_interpolate"] / properties["a_speed_multi_scale"] >= 1 and properties["a_speed_multi_iterations"] != -1:
		Bullets["speed_multi_iter"] -= 1
		Bullets["speed_interpolate"] = 0

func move_equation(Bullets: Dictionary, properties):
	if properties.get("a_direction_equation", "") == "": return
	if expression.parse(properties["a_direction_equation"], ["x"]) != OK:
		push_error(expression.get_error_text())
		return
	Bullets["curveDir_index"] += 0.05
	Bullets["curve"] = expression.execute([Bullets["curveDir_index"]]) * 100

func move_homing(Bullets: Dictionary, properties, delta: float):
	if not Bullets.get("homing_target", null): return

	var target_pos: Vector2

	# 1. Godot 4 Safe Type Checking
	if Bullets["homing_target"] is Node2D:
		if not is_instance_valid(Bullets["homing_target"]):
			Bullets["homing_target"] = null
			return
		target_pos = Bullets["homing_target"].global_position
	elif typeof(Bullets["homing_target"]) == TYPE_VECTOR2:
		target_pos = Bullets["homing_target"]
	else:
		return # Fail-safe if it grabbed something unexpected

	# 2. Homing Margin (Drop target if it gets too close)
	if Bullets["position"].distance_to(target_pos) < HOMING_MARGIN:
		if properties.has("homing_list"):
			if Bullets["homing_counter"] < properties["homing_list"].size() - 1:
				Bullets["homing_counter"] += 1
				target_from_list(Bullets)
			else:
				match properties.get("homing_when_list_ends"):
					LIST_ENDS.Loop: Bullets["homing_counter"] = 0
					LIST_ENDS.Reverse:
						Bullets["homing_counter"] = 0
						properties["homing_list"].reverse()
					LIST_ENDS.Stop:
						Bullets["homing_target"] = null
		else: 
			Bullets["homing_target"] = null

	# If the margin check cleared the target, bail out this frame
	if not Bullets.get("homing_target", null): return

	# 3. Direct Angular Steering (The Math Fix)
	var target_angle: float = (target_pos - Bullets["position"]).angle()
	var current_angle: float = Bullets["rotation"]
	var angle_diff: float = angle_difference(current_angle, target_angle)

	# properties["homing_steer"] dictates Turn Speed (Radians per Second)
	var turn_amount: float = sign(angle_diff) * min(abs(angle_diff), properties["homing_steer"] * delta)

	Bullets["rotation"] += turn_amount
		
func move_curve(Bullets: Dictionary, properties, delta: float, bullet):
	Bullets["position"] = Bullets["spawn_pos"] + (properties["curve"].sample_baked(Bullets["curve_counter"] * Bullets["speed"]) - Bullets["curve_start"]).rotated(Bullets["rotation"])
	Bullets["curve_counter"] += delta
	if Bullets["curve_counter"] * Bullets["speed"] < properties["curve"].get_baked_length(): return
	match properties["a_curve_movement"]:
		CURVE_TYPE.LoopFromStart: Bullets["curve_counter"] = 0
		CURVE_TYPE.LoopFromEnd:
			Bullets["curve_counter"] = 0
			Bullets["spawn_pos"] = Bullets["position"]
		CURVE_TYPE.OnceThenDie: delete_bullet(bullet)
		CURVE_TYPE.OnceThenStay: Bullets["speed"] = 0

func bullet_movement(delta: float):
	var Bullets: Dictionary; var properties: Dictionary;
	for bullet in poolBullets.keys():
		Bullets = poolBullets[bullet]
		if Bullets["state"] == BState.Unactive: continue
		properties = Bullets["properties"]
		if Bullets["state"] == BState.QueuedFree:
			_apply_movement(Bullets, bullet, properties)
			continue

		if Bullets.has("death_counter"):
			Bullets["death_counter"] += delta
			if Bullets["death_counter"] >= properties["death_after_time"]:
				delete_bullet(bullet)
				_apply_movement(Bullets, bullet, properties)
				continue
				
		if Bullets.has("rot_index"): Bullets["rot_index"] += properties["spec_rotating_speed"]
		move_scale(Bullets, properties, delta)

		if Bullets["state"] == BState.Spawned:
			if Bullets["source_node"] is Dictionary: Bullets["position"] = Bullets["spawn_pos"] + Bullets["source_node"]["position"]
			else: Bullets["position"] = Bullets["source_node"].global_position + Bullets["spawn_pos"]
		elif Bullets["state"] == BState.Moving:
			move_trail(Bullets, properties)
			move_speed(Bullets, properties, delta)
			move_equation(Bullets, properties)
			move_homing(Bullets, properties, delta)
			if properties.get("curve"): move_curve(Bullets, properties, delta, bullet)
			else:
				Bullets["vel"] = Vector2(Bullets["speed"], Bullets.get("curve", 0)).rotated(Bullets["rotation"])
				Bullets["position"] += Bullets["vel"] * delta
			if Bullets.has("spawn_pos") and not properties.has("curve"): Bullets["position"] += Bullets["spawn_pos"]

			if Bullets.has("trig_container") and Bullets["trig_types"].has("TrigPos") and (Bullets["state"] == BState.Moving or not properties["trigger_wait_for_shot"]):
				Bullets["trig_container"].checkTriggers(Bullets, bullet)

		if properties.get("homing_select_in_group", -1) == GROUP_SELECT.Nearest_anywhen:
			target_from_options(Bullets)

		if not bullet is RID:
			if bullet.base_scale == null: bullet.base_scale = bullet.scale
			bullet.global_position = Bullets["position"]
			bullet.rotation = Bullets["rotation"] + Bullets.get("rot_index", 0)
			bullet.scale = bullet.base_scale * Bullets.get("scale", Vector2(properties["scale"], properties["scale"]))
			continue
		else:
			_apply_movement(Bullets, bullet, properties)

func _apply_movement(Bullets: Dictionary, bullet: RID, properties: Dictionary):
	if Bullets.get("state", BState.Unactive) == BState.Unactive or Bullets.is_empty(): return
	var shared_rid: RID = Bullets["shared_area"].get_rid()
	var bullet_index: int = shape_indexes.get(bullet, -1)
	if bullet_index == -1: return

	if Bullets["state"] == BState.QueuedFree:
		phys.area_set_shape_disabled(shared_rid, bullet_index, true)
		poolBullets.erase(bullet)
		return

	if not properties.get("spec_no_collision", false):
		phys.area_set_shape_transform(shared_rid, bullet_index, Transform2D(Bullets["rotation"] + Bullets.get("rot_index", 0), Bullets.get("scale", Vector2(properties["scale"], properties["scale"])), properties.get("skew", 0), Bullets["position"]))

	if Bullets["shape_disabled"]:
		if not properties.get("spec_no_collision", false):
			phys.area_set_shape_disabled(shared_rid, shape_indexes[bullet], false)
		Bullets["shape_disabled"] = false

func _calculate_bullets_index(from_index: int = -1):
	var shared_rid: RID; var Brid: RID; var Bullets: Dictionary;
	if from_index == -1:
		for area in $SharedAreas.get_children():
			shared_rid = area.get_rid()
			for b_index in area.get_meta("ShapeCount"):
				Brid = get_RID_from_index(shared_rid, b_index)
				_update_shape_indexes(Brid, b_index, Bullets["shared_area"].name)

func _update_shape_indexes(rid, index: int, area: String):
	shape_indexes[rid] = index
	if not shape_rids.has(area):
		shape_rids[area] = {}
	shape_rids[area][index] = rid

# =========================================================
# DRAW BULLETS
# =========================================================
func get_texture_frame(bullet: Dictionary, Bullets, spriteframes: SpriteFrames = textures):
	if not bullet.has("anim_frame"): return spriteframes.get_frame_texture(bullet["anim"][ANIM.TEXTURE], 0)
	else:
		bullet["anim_counter"] += _delta
		if bullet["anim_counter"] >= 1 / bullet["anim_speed"]:
			bullet["anim_counter"] = 0
			bullet["anim_frame"] += 1
			if bullet["anim_frame"] >= bullet["anim_length"]:
				if bullet["anim_loop"]:
					bullet["anim_frame"] = 0
				elif bullet["state"] == BState.Shooting:
					bullet["state"] = BState.Moving
					change_animation(bullet, "idle", Bullets)
				elif bullet["state"] == BState.Spawning:
					bullet["state"] = BState.Spawned
					change_animation(bullet, "waiting", Bullets)
		return spriteframes.get_frame_texture(bullet["anim"][ANIM.TEXTURE], bullet["anim_frame"])

func modulate_bullet(bullet: Dictionary, texture: Texture):
	if bullet["properties"].has("spec_modulate_loop"):
		draw_texture(texture, -texture.get_size() / 2, bullet["properties"]["spec_modulate"].sample(bullet["modulate_index"]))
		bullet["modulate_index"] = bullet["modulate_index"] + (_delta / bullet["properties"]["spec_modulate_loop"])
		if bullet["modulate_index"] >= 1: bullet["modulate_index"] = 0
	else: draw_texture(texture, -texture.get_size() / 2, bullet["properties"]["spec_modulate"].get_color(0))

func _draw() -> void:
	if Engine.is_editor_hint(): return
	var canvas_transform: Transform2D = get_canvas_transform()
	var canvas_scale: Vector2 = canvas_transform.get_scale()
	var view_origin: Vector2 = -canvas_transform.get_origin() / canvas_scale
	var view_size: Vector2 = get_viewport_rect().size / canvas_scale
	viewrect = Rect2(view_origin, view_size).grow(100.0)

	var texture: Texture2D; var bullet: Dictionary
	for Bullets in poolBullets.keys():
		bullet = poolBullets[Bullets]
		if Bullets is Node2D:
			if bullet["properties"].has("speed"): Bullets.queue_redraw()
			if bullet.has("trail"):
				draw_set_transform(bullet["position"], bullet["rotation"] + bullet.get("rot_index", 0), bullet.get("scale", Vector2(bullet["properties"]["scale"], bullet["properties"]["scale"])))
				for l in 3:
					draw_line(bullet["trail"][l], bullet["trail"][l + 1], bullet["properties"]["spec_trail_modulate"], bullet["properties"]["spec_trail_width"])
			continue
		elif bullet.has("trail"):
			for l in 3:
				draw_line(bullet["trail"][l], bullet["trail"][l + 1], bullet["properties"]["spec_trail_modulate"], bullet["properties"]["spec_trail_width"])

		if (not (bullet["state"] >= BState.Spawning and viewrect.has_point(bullet["position"]))) or (bullet["properties"].has("spec_modulate") and bullet["properties"].has("spec_modulate_loop") and bullet["properties"]["spec_modulate"].get_color(0).a == 0):
			continue

		texture = get_texture_frame(bullet, Bullets)
		draw_set_transform_matrix(Transform2D(bullet["rotation"] + bullet.get("rot_index", 0), bullet.get("scale", Vector2(bullet["properties"]["scale"] * bullet["anim"][ANIM.SCALE], bullet["properties"]["scale"] * bullet["anim"][ANIM.SCALE])), bullet["anim"][ANIM.SKEW], bullet["position"]))

		if bullet["properties"].has("spec_modulate"):
			modulate_bullet(bullet, texture)
		else: draw_texture(texture, -texture.get_size() / 2)

func change_animation(bullet: Dictionary, type: String, Bullets):
	if Bullets is Node2D: return true
	var instantly: bool = false
	var anim_state: Array
	if type in ["spawn", "shoot", "idle", "waiting", "delete"]:
		anim_state = arrayAnim.get(bullet["properties"].get("anim_" + type, ""), [])
		if bullet["properties"]["anim_" + type] == bullet["properties"]["anim_idle"]:
			instantly = true
	else: anim_state = arrayAnim[type]

	var anim_id: String = anim_state[ANIM.TEXTURE]
	bullet["anim"] = anim_state
	var frame_count: int = textures.get_frame_count(anim_id)
	if frame_count > 1:
		bullet["anim_length"] = frame_count
		bullet["anim_counter"] = 0
		bullet["anim_frame"] = 0
		bullet["anim_loop"] = textures.get_animation_loop(anim_id)
		bullet["anim_speed"] = textures.get_animation_speed(anim_id)
	elif bullet.has("anim_frame"):
		bullet.erase("anim_length")
		bullet.erase("anim_counter")
		bullet.erase("anim_frame")
		bullet.erase("anim_loop")
		bullet.erase("anim_speed")
		instantly = true

	var col_id: Array = anim_state[ANIM.COLLISION]
	if not col_id.is_empty() and col_id != bullet["colID"]:
		bullet["colID"] = col_id
		var new_rid: RID = create_shape(bullet["shared_area"].get_rid(), bullet["colID"])
		poolBullets[new_rid] = bullet
		_update_shape_indexes(new_rid, phys.area_get_shape_count(bullet["shared_area"].get_rid()) - 1, bullet["shared_area"].name)
		back_to_grave(bullet["properties"]["__ID__"], Bullets)

	return instantly

# =========================================================
# USEFUL FUNCTIONS / API
# =========================================================
func clear_all_bullets():
	for bullet in poolBullets.keys(): delete_bullet(bullet)

func clear_bullets_within_dist(target_pos, radius: float = STANDARD_BULLET_RADIUS):
	for bullet in poolBullets.keys():
		if poolBullets[bullet]["position"].distance_to(target_pos) < radius:
			delete_bullet(bullet)

func delete_bullet(bullet):
	if not poolBullets.has(bullet): return
	var Bullets = poolBullets[bullet]
	if arrayAnim[Bullets["properties"]["anim_delete"]][ANIM.SFX]: arrayAnim[Bullets["properties"]["anim_delete"]][ANIM.SFX].play()
	back_to_grave(Bullets["properties"]["__ID__"], bullet)

func get_bullets_in_radius(origin: Vector2, radius: float):
	var result: Array
	for bullet in poolBullets.keys():
		if poolBullets[bullet]["position"].distance_to(origin) < radius:
			result.append(bullet)
	return result

func get_random_bullet():
	return poolBullets[randi() % poolBullets.size()]

func add_group_to_bullet(bullet: Dictionary, group: String):
	if bullet.has("groups"): bullet["groups"].append(group)
	else: bullet["groups"] = [group]

func remove_group_from_bullet(bullet: Dictionary, group: String):
	if not bullet.has("groups"): return
	bullet["groups"].erase(group)

func clear_groups_from_bullet(bullet: Dictionary):
	bullet.erase("groups")

func is_bullet_in_group(bullet: Dictionary, group: String):
	if not bullet.has("groups"): return false
	return bullet["groups"].has(group)

func is_bullet_in_grouptype(bullet: Dictionary, grouptype: String):
	if not bullet.has("groups"): return false
	for g in bullet["groups"]:
		if not grouptype in g: continue
		return true

func get_shared_area_rid(shared_area_name: String):
	return _ensure_shared_area(shared_area_name).get_rid()
func get_shared_area(shared_area_name: String):
	return _ensure_shared_area(shared_area_name)
func change_shared_area(bullet: Dictionary, rid: RID, idx: int, new_area: Area2D):
	phys.area_remove_shape(bullet["shared_area"].get_rid(), idx)
	phys.area_add_shape(new_area.get_rid(), rid)
	bullet["shared_area"] = new_area
	_calculate_bullets_index()

func rid_to_bullet(rid):
	return poolBullets[rid]

func get_RID_from_index(source_area: RID, index: int) -> RID:
	return phys.area_get_shape(source_area, index)

func change_property(type: String, id: String, prop: String, new_value):
	var result = call(type, id)
	match type:
		"pattern", "container", "trigger": result.set(prop, new_value)
		"bullet": result[prop] = new_value

func switch_property_of_bullet(bullet: Dictionary, new_props_id: String):
	bullet["properties"] = bullet(new_props_id)

func switch_property_of_all(replaceby_id: String, replaced_id: String = "__ALL__"):
	for bullet in poolBullets.values():
		if not (replaced_id == "__ALL__" or bullet["properties"].hash() == bullet(replaced_id).hash()): continue
		bullet["properties"] = bullet(replaceby_id)

func random_remove(id: String, prop: String):
	var result = bullet(id)
	result.remove_at(prop)

func random_change(type: String, id: String, prop: String, new_value):
	var result = call_deferred(type, id)
	match type:
		"pattern": result.set(prop, new_value)
		"bullet": result[prop] = new_value

func random_set(type: String, id: String, value: bool):
	var result = call_deferred(type, id)
	match type:
		"pattern": result.has_random = value
		"bullet": result["has_random"] = value

func get_variation(mean: float, variance: float, limit_down = 0, limit_up = 0):
	if limit_down != 0 and limit_up != 0:
		return min(max(RAND.randfn(mean, variance), limit_down), limit_up)
	elif limit_down != 0: return max(RAND.randfn(mean, variance), limit_down)
	elif limit_up != 0: return min(RAND.randfn(mean, variance), limit_up)
	else: return RAND.randfn(mean, variance)

func get_choice_string(list: String):
	var result: Array = list.split(";", false)
	return result[randi() % result.size()]

func get_choice_array(list: Array):
	return list[randi() % list.size()]

func edit_special_target(var_name: String, path: Node2D):
	set_meta("ST_" + var_name, path)

func get_special_target(var_name: String):
	return get_meta("ST_" + var_name)

# =========================================================
# HOMING & COLLISIONS
# =========================================================
func _on_Homing_timeout(Bullets: Dictionary, start: bool):
	if start:
		var properties = Bullets["properties"]
		if not properties.has("homing_mouse"):
			# FIX 1: Safely retrieve whichever property is actually populated
			if properties.has("homing_target") or properties.has("node_homing"): 
				Bullets["homing_target"] = properties.get("node_homing", properties.get("homing_target"))
			else: 
				Bullets["homing_target"] = properties.get("homing_position", Vector2())
				
		if properties["homing_duration"] > 0:
			get_tree().create_timer(properties["homing_duration"]).connect("timeout", Callable(self, "_on_Homing_timeout").bind(Bullets, false))
		if properties.get("homing_select_in_group", -1) == GROUP_SELECT.Nearest_on_homing:
			target_from_options(Bullets)
		elif properties.get("homing_select_in_group", -1) == GROUP_SELECT.Random:
			target_from_options(Bullets, true)
		elif not Bullets["properties"].get("homing_list", []).is_empty(): 
			target_from_list(Bullets)
	else:
		Bullets["homing_target"] = null

func target_from_options(Bullets: Dictionary, random: bool = false):
	if Bullets["properties"].has("homing_group"): target_from_group(Bullets, random)
	elif Bullets["properties"].has("homing_surface"): target_from_segments(Bullets, random)
	elif Bullets["properties"].has("homing_mouse"): Bullets["homing_target"] = get_global_mouse_position()

#func target_from_group(Bullets: Dictionary, random: bool = false):
	## Execute scene tree query to aggregate all valid entity references into an array.
	#var all_nodes = get_tree().get_nodes_in_group(Bullets["properties"]["homing_group"])
	## Branch 1: Stochastic targeting. Assigns a randomized index from the aggregated array.
	#if random:
		#Bullets["homing_target"] = all_nodes[randi() % all_nodes.size()]
		#return
	## Branch 2: Deterministic nearest-neighbor targeting algorithm initialization.
	#var result: Node2D; var smaller_dist = INF; var curr_dist;
	#for node in all_nodes:
		#curr_dist = Bullets["position"].distance_to(node.global_position)
		#if curr_dist < smaller_dist:
			#smaller_dist = curr_dist
			#result = node
	## Mutate the source dictionary, injecting the computed optimal target reference.
	#Bullets["homing_target"] = result

func target_from_group(Bullets: Dictionary, random: bool = false):
	var all_nodes = get_tree().get_nodes_in_group(Bullets["properties"]["homing_group"])
	if random:
		Bullets["homing_target"] = all_nodes[randi() % all_nodes.size()]
		return
		
	var result: Node2D
	var smaller_dist_sq = INF 
	var curr_dist_sq: float
	var origin: Vector2 = Bullets["position"]
	
	for node in all_nodes:
		# Compute squared magnitude to bypass sqrt() overhead
		curr_dist_sq = origin.distance_squared_to(node.global_position)
		
		if curr_dist_sq < smaller_dist_sq:
			smaller_dist_sq = curr_dist_sq
			result = node
			
	Bullets["homing_target"] = result
	print(result)
func target_from_segments(Bullets: Dictionary, random: bool = false):
	var dist: float = INF; var result: Vector2; var new_res: Vector2; var new_dist: float
	for p in Bullets["homing_surface"].size():
		new_res = Geometry2D.get_closest_point_to_segment(Bullets["position"], Bullets["homing_surface"][p], Bullets["homing_surface"][(p + 1) % Bullets["homing_surface"].size()])
		new_dist = Bullets["position"].distance_to(new_res)
		if new_dist < dist or (random and randi() % 2 == 0):
			dist = new_dist
			result = new_res
	Bullets["homing_target"] = result

func target_from_list(Bullets: Dictionary, do: bool = true):
	if not do: return
	Bullets["homing_target"] = Bullets["properties"]["homing_list"][Bullets["homing_counter"]]

func trig_timeout(bullet, rid):
	if bullet is Node: bullet.trigger_timeout = true
	else: bullet["trig_timeout"] = true
	bullet.get("trig_container").checkTriggers(bullet, rid)

func bullet_collide_area(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int, shared_area: Area2D) -> void:
	var rid = shape_rids.get(shared_area.name, {}).get(local_shape_index)
	if not poolBullets.has(rid):
		rid = shared_area
		if not poolBullets.has(rid): return
	var Bullets = poolBullets[rid]
	if Bullets["properties"]["death_from_collision"]:
		delete_bullet(rid)
func bullet_collide_body(body_rid: RID, body: Node, body_shape_index: int, local_shape_index: int, shared_area: Area2D) -> void:
	var rid = shape_rids.get(shared_area.name, {}).get(local_shape_index)
	if not poolBullets.has(rid):
		rid = shared_area
		if not poolBullets.has(rid): return
	var Bullets = poolBullets[rid]
	bullet_collided_body.emit(body, body_shape_index, Bullets, local_shape_index, shared_area)

	if Bullets.get("bounces", 0) > 0:
		bounce(Bullets, shared_area)
		Bullets["bounces"] = max(0, Bullets["bounces"] - 1)
	elif body.is_in_group(GROUP_BOUNCE):
		bounce(Bullets, shared_area)

	if Bullets.get("trig_types", []).has("TrigCol"):
		Bullets["trig_collider"] = body
		Bullets["trig_container"].checkTriggers(Bullets, rid)

	if body.is_in_group("Player"):
		delete_bullet(rid)
	elif Bullets["properties"]["death_from_collision"]:
		delete_bullet(rid)

func bounce(Bullets: Dictionary, shared_area: Area2D):
	if not Bullets.has("colID"): return
	$Bouncy/CollisionShape2D.set_deferred("shape", Bullets["colID"][0])
	$Bouncy.collision_layer = shared_area.collision_layer
	$Bouncy.collision_mask = shared_area.collision_mask
	$Bouncy.global_position = Bullets["position"]
	var collision = $Bouncy.move_and_collide(Vector2(0, 0))
	if collision:
		Bullets["vel"] = Bullets["vel"].bounce(collision.get_normal())
		Bullets["rotation"] = Bullets["vel"].angle()
	$Bouncy/CollisionShape2D.shape = null
	$Bouncy.global_position = UNACTIVE_ZONE

func create_random_props(original: Dictionary) -> Dictionary:
	var r_name: String; var result: Dictionary = original;
	var choice: Array; var variation: Vector3;
	for p in original.keys():
		r_name = match_rand_prop(p)
		if original.has(r_name + "_choice"):
			choice = original[r_name + "_choice"]
			variation = original.get(r_name + "_variation", Vector3(0, 0, 0))
			result[p] = get_variation(choice[randi() % choice.size()].to_float(), variation.x, variation.y, variation.z)
		elif original.has(r_name + "_variation"):
			variation = original.get(r_name + "_variation", Vector3(0, 0, 0))
			result[p] = get_variation(original[p], variation.x, variation.y, variation.z)
		elif original.has(r_name + "_chance"):
			result[p] = randf_range(0, 1) < original[r_name + "_chance"]
	return result

func match_rand_prop(original: String) -> String:
	match original:
		"speed": return "r_speed"
		"scale": return "r_scale"
		"angle": return "r_angle"
		"groups": return "r_groups"
		"death_after_time": return "r_death_after"
		"anim_idle_texture": return "r_"
		"a_direction_equation": return "r_dir_equation"
		"curve": return "r_curve"
		"a_speed_multiplier": return "r_speed_multi_curve"
		"a_speed_multi_iterations": return "r_speed_multi_iter"
		"spec_bounces": return "r_bounce"
		"spec_modulate": return "r_modulate"
		"spec_rotating_speed": return "r_rotating"
		"trigger_container": return "r_trigger"
		"homing_target": return "r_homing_target"
		"homing_special_target": return "r_special_target"
		"homing_group": return "r_group_target"
		"homing_position": return "r_pos_target"
		"homing_steer": return "r_steer"
		"homing_duration": return "r_homing_dur"
		"homing_time_start": return "r_homing_delay"
		"scale_multiplier": return "r_scale_multi_curve"
		"scale_multi_iterations": return "r_scale_multi_iter"
		"": return "r_"
	return ""
