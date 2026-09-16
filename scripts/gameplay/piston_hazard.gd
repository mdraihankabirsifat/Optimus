class_name PistonHazard
extends Node3D
## HAZ-003: a stone ram that slams from the ceiling to the floor on a fixed cycle.
## It glows and shudders before every slam, and covers only the middle of the corridor,
## so it is a timing test, never a wall.

const FOOTPRINT := 3.0
const WARN := 0.7
const SLAM := 0.14
const HOLD := 0.35
const RETRACT := 0.9

var hazard_id: int = 0
var _phase_offset: float = 0.0
var _time: float = 0.0
var _head: MeshInstance3D
var _rod: MeshInstance3D
var _glow: StandardMaterial3D
var _area: Area3D
var _bodies: Array[PlayerController] = []
var _slammed := false


static func create(id: int, cell: Vector3i, phase: int) -> PistonHazard:
	var piston := PistonHazard.new()
	piston.hazard_id = id
	piston._phase_offset = float(phase) * AppConfig.PISTON_CYCLE * 0.25
	piston.position = CaveBuilder.cell_to_world(cell)
	return piston


func _ready() -> void:
	add_to_group("hazards")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.36, 0.33, 0.31)
	stone.roughness = 1.0
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(0.3, 0.1, 0.05)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.3, 0.08)
	_glow.emission_energy_multiplier = 0.2

	_head = MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(FOOTPRINT, 1.2, FOOTPRINT)
	_head.mesh = block
	_head.material_override = stone
	add_child(_head)
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(FOOTPRINT + 0.1, 0.25, FOOTPRINT + 0.1)
	band.mesh = band_mesh
	band.material_override = _glow
	band.position.y = -0.45
	_head.add_child(band)

	_rod = MeshInstance3D.new()
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.35
	rod_mesh.bottom_radius = 0.35
	rod_mesh.height = 1.0
	_rod.mesh = rod_mesh
	_rod.material_override = stone
	add_child(_rod)

	# A scorched square on the floor marks the danger zone even while the ram is up.
	var mark := MeshInstance3D.new()
	var mark_mesh := BoxMesh.new()
	mark_mesh.size = Vector3(FOOTPRINT, 0.03, FOOTPRINT)
	mark.mesh = mark_mesh
	var mark_mat := StandardMaterial3D.new()
	mark_mat.albedo_color = Color(0.12, 0.08, 0.07)
	mark.material_override = mark_mat
	mark.position.y = -CaveBuilder.CELL_SIZE * 0.5 + CaveBuilder.WALL_THICKNESS * 0.5 + 0.02
	add_child(mark)

	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = CaveBuilder.LAYER_RACERS
	var shape := BoxShape3D.new()
	shape.size = Vector3(FOOTPRINT, CaveBuilder.CELL_SIZE - 1.0, FOOTPRINT)
	var col := CollisionShape3D.new()
	col.shape = shape
	_area.add_child(col)
	add_child(_area)
	_area.body_entered.connect(func(b: Node3D) -> void:
		if b is PlayerController and not _bodies.has(b):
			_bodies.append(b))
	_area.body_exited.connect(func(b: Node3D) -> void: _bodies.erase(b))
	_pose(0.0)


## Online: pistons run on the server's race clock so every machine sees the same slam.
func net_sync_time(server_time: float) -> void:
	if absf(server_time - _time) > 0.15:
		_time = server_time


func _process(delta: float) -> void:
	_time += delta
	var t := fmod(_time + _phase_offset, AppConfig.PISTON_CYCLE)
	var idle := AppConfig.PISTON_CYCLE - WARN - SLAM - HOLD - RETRACT
	var extension := 0.0
	var shake := 0.0
	var danger := false
	if t < idle:
		_glow.emission_energy_multiplier = 0.2
		_slammed = false
	elif t < idle + WARN:
		var w := (t - idle) / WARN
		_glow.emission_energy_multiplier = 0.2 + 3.0 * w
		shake = 0.05 * w
		extension = 0.04 * w
	elif t < idle + WARN + SLAM:
		extension = (t - idle - WARN) / SLAM
		danger = true
	elif t < idle + WARN + SLAM + HOLD:
		extension = 1.0
		danger = true
		if not _slammed:
			_slammed = true
			AudioManager.play_sfx_3d("piston", global_position + Vector3(0, -3, 0), 2.0)
			_near_miss_check()
	else:
		extension = 1.0 - (t - idle - WARN - SLAM - HOLD) / RETRACT
		_glow.emission_energy_multiplier = 0.2
	_pose(extension)
	_head.position.x = randf_range(-shake, shake)
	if danger:
		for racer in _bodies:
			if is_instance_valid(racer):
				racer.health.apply_damage(AppConfig.DAMAGE_PISTON, "piston_%d" % hazard_id, 1.2)


## FEEL-008: the local racer standing just outside the footprint hears it go past.
func _near_miss_check() -> void:
	var local := WorldScope.first(self, "local_player") as PlayerController
	if local == null or _bodies.has(local):
		return
	var rel := local.global_position - global_position
	var flat := Vector2(rel.x, rel.z).length()
	if flat < FOOTPRINT * 0.5 + 1.8 and absf(rel.y) < CaveBuilder.CELL_SIZE * 0.5:
		NearMiss.trigger(local)


## 0 is tucked against the ceiling, 1 is resting on the floor.
func _pose(extension: float) -> void:
	var top := CaveBuilder.CELL_SIZE * 0.5 - CaveBuilder.WALL_THICKNESS * 0.5
	var bottom := -CaveBuilder.CELL_SIZE * 0.5 + CaveBuilder.WALL_THICKNESS * 0.5
	var head_top := lerpf(top, bottom + 1.2, extension)
	_head.position.y = head_top - 0.6
	var rod_len := maxf(0.05, top - head_top)
	_rod.scale = Vector3(1.0, rod_len, 1.0)
	_rod.position.y = head_top + rod_len * 0.5
