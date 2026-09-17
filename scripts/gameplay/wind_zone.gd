class_name WindZone
extends Area3D
## HAZ-004: a draught along a corridor. It pushes every racer inside along one world axis,
## whatever surface they are standing on -- wind has no gravity frame.

var push := Vector3.ZERO
var _half: float = CaveBuilder.CHAMBER_HALF
var _bodies: Array[PlayerController] = []


static func create(cell: Vector3i, axis: int, sign: int, half: float = CaveBuilder.CHAMBER_HALF) -> WindZone:
	var zone := WindZone.new()
	zone._half = half
	zone.position = CaveBuilder.cell_to_world(cell)
	zone.push = Vector3(CaveGraph.DIRS[axis]) * float(sign) * AppConfig.WIND_SPEED
	return zone


func _ready() -> void:
	collision_layer = 0
	collision_mask = CaveBuilder.LAYER_RACERS
	add_to_group("wind_zones")
	body_entered.connect(func(b: Node3D) -> void:
		if b is PlayerController and not _bodies.has(b):
			_bodies.append(b))
	body_exited.connect(func(b: Node3D) -> void: _bodies.erase(b))
	var shape := BoxShape3D.new()
	shape.size = Vector3(_half * 2.0, _half - CaveBuilder.FLOOR_Y, _half * 2.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = (_half + CaveBuilder.FLOOR_Y) * 0.5
	add_child(col)

	var streaks := CPUParticles3D.new()
	streaks.amount = 40
	streaks.lifetime = 0.9
	streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var extent := _half - 0.25
	streaks.emission_box_extents = Vector3(extent, (_half - CaveBuilder.FLOOR_Y) * 0.5 - 0.25, extent)
	streaks.position.y = (_half + CaveBuilder.FLOOR_Y) * 0.5
	streaks.direction = push.normalized()
	streaks.spread = 3.0
	streaks.gravity = Vector3.ZERO
	streaks.initial_velocity_min = 9.0
	streaks.initial_velocity_max = 13.0
	streaks.local_coords = false
	var line := BoxMesh.new()
	var along := push.normalized().abs()
	line.size = Vector3(0.04, 0.04, 0.04) + along * 0.9
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.92, 1.0, 0.35)
	line.material = mat
	streaks.mesh = line
	add_child(streaks)

	var hum := AudioStreamPlayer3D.new()
	hum.bus = "SFX"
	hum.stream = AudioManager.get_stream("wind")
	hum.unit_size = 5.0
	hum.max_distance = 26.0
	hum.volume_db = -8.0
	hum.autoplay = hum.stream != null
	add_child(hum)


func _physics_process(_delta: float) -> void:
	for racer in _bodies:
		if is_instance_valid(racer) and not racer.gravity.is_transitioning:
			racer.push_velocity += push
