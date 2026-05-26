@tool
extends Path2D

@export var id:String = ""
@export var pattern:Pattern
@export var preview_spawn:bool = false
@export var preview_shoot:bool = false : set = set_pre_shoot

var preview_bullet:BulletProps

func _ready():
	if not Engine.is_editor_hint() and pattern:
		if pattern.forced_target: pattern.node_target = get_node(pattern.forced_target)
		if pattern.resource_name in ["PatternCustomShape","PatternCustomPoints"]:
			pattern.shape = curve
		if pattern.resource_name == "PatternCustomShape":
			if pattern.closed_shape: pattern.symmetry_type = 0
			
			var follow = PathFollow2D.new()
			add_child(follow)
			var length = curve.get_baked_length()
			for b in pattern.nbr:
				var pos_on_curve
				if pattern.closed_shape: pos_on_curve = length/pattern.nbr*b
				else: pos_on_curve = length/(pattern.nbr-1)*b
				follow.h_offset = pos_on_curve
				pattern.pos.append(pattern.shape.sample_baked(pos_on_curve).rotated(pattern.pattern_angle)-pattern.center_pos)
				pattern.angles.append(follow.rotation-PI/2)
			remove_child(follow)
			
		elif pattern.resource_name == "PatternCustomPoints":
			var point_count = curve.get_point_count()
			pattern.nbr = point_count
			pattern.shape = curve
			var angle;
			for point in point_count:
				var pos = curve.get_point_position(point)
				if pattern.calculate_angles == pattern.ANGLE_TYPE.FromTangeant:
					if point == point_count-1:
						angle = pos.angle_to_point(curve.get_point_position(point-1))+PI/2
					elif point == 0: angle = curve.get_point_position(point+1).angle_to_point(pos)+PI/2
					else: angle = curve.get_point_position(point+1).angle_to_point(curve.get_point_position(point-1))+PI/2
				elif pattern.calculate_angles == pattern.ANGLE_TYPE.FromCenter:
					angle = pattern.center_pos.angle_to_point(pos)+PI
				pattern.pos.append(pos-pattern.center_pos)
				if pattern.calculate_angles != pattern.ANGLE_TYPE.Custom: pattern.angles.append(angle+(PI*int(pattern.reversed_angle)))
		
		elif pattern.resource_name == "PatternCustomArea":
			curve_to_polygon()
			if pattern.grid_spawning == Vector2(0,0): area_pooling()
			else: grid_spawning()
		Spawning.new_pattern(id, pattern)
		queue_free()

func _process(delta):
	if preview_spawn and Engine.is_editor_hint():
		queue_redraw()
func set_pre_shoot(value):
	preview_shoot = value

func _draw():
	if not preview_spawn or pattern == null: return
	if pattern.resource_name in ["PatternCustomShape"]:
		var length = curve.get_baked_length()
		var follow
		if preview_shoot:
			follow = PathFollow2D.new()
			add_child(follow)
			
		draw_circle(pattern.center_pos, 10, Color.YELLOW)
		for b in pattern.nbr:
			var pos_on_curve
			if pattern.closed_shape: pos_on_curve = length/pattern.nbr*b
			else: pos_on_curve = length/(pattern.nbr-1)*b
			var pos = curve.sample_baked(pos_on_curve)
			draw_circle(pos, 10, Color.RED)
			
			if preview_shoot:
				follow.h_offset = pos_on_curve
				draw_line(pos, pos+Vector2(32,0).rotated(follow.rotation-PI/2),Color.YELLOW,3)
		if preview_shoot:
			remove_child(follow)
	elif pattern.resource_name in ["PatternCustomPoints"]:
		draw_circle(pattern.center_pos, 10, Color.YELLOW)

func area_pooling():
	var can_loop = false
	var maybe_pos; var tries:int
	for i in pattern.pooling:
		pattern.pos.append([])
		for j in pattern.nbr:
			maybe_pos = Vector2(randf_range(pattern.limit_rect.position.x,pattern.limit_rect.size.x),\
								randf_range(pattern.limit_rect.position.y,pattern.limit_rect.size.y))
			tries = pattern.tries_max
			while tries > 0 and not Geometry2D.is_point_in_polygon(maybe_pos, pattern.polygon):
				tries -= 1
				maybe_pos = Vector2(randf_range(pattern.limit_rect.position.x,pattern.limit_rect.size.x),\
									randf_range(pattern.limit_rect.position.y,pattern.limit_rect.size.y))
			pattern.pos[i].append(maybe_pos-pattern.center_pos)

func grid_spawning():
	pattern.pos.append([])
	var maybe_pos
	for x in (pattern.limit_rect.size.x-pattern.limit_rect.position.x)/pattern.grid_spawning.x:
		for y in (pattern.limit_rect.size.y-pattern.limit_rect.position.y)/pattern.grid_spawning.y:
			maybe_pos = pattern.limit_rect.position+Vector2(pattern.grid_spawning.x*x,pattern.grid_spawning.y*y)
			if Geometry2D.is_point_in_polygon(maybe_pos, pattern.polygon):
				pattern.pos[0].append(maybe_pos-pattern.center_pos)
	pattern.nbr = pattern.pos[0].size()
	pattern.pooling = 1

func curve_to_polygon():
	var point:Vector2; var poly:Array
	for p in curve.get_point_count():
		point = curve.get_point_position(p)
		poly.append(point)
		if point.x < pattern.limit_rect.position.x: pattern.limit_rect.position.x = point.x
		if point.x > pattern.limit_rect.size.x: pattern.limit_rect.size.x = point.x
		if point.y < pattern.limit_rect.position.y: pattern.limit_rect.position.y = point.y
		if point.y > pattern.limit_rect.size.y: pattern.limit_rect.size.y = point.y
	pattern.polygon = PackedVector2Array(poly)
