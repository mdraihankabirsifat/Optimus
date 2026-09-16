class_name SpiderEnemy
extends Node3D
## ENEMY-001: a cave spider on a straight corridor, three cells long. It patrols the world
## floor, lunges at racers close to it, bites once, then backs off -- it can never pin
## anyone in place. No nav mesh: nav meshes assume a world up vector, and this game does not
## have one. A racer walking the ceiling is simply out of its reach.

enum State { PATROL, LUNGE, RETREAT }

var spider_id: int = 0
var _axis := Vector3.RIGHT
var _lateral := Vector3.BACK
var _centre := Vector3.ZERO
var _state := State.PATROL
var _state_timer := 0.0
var _dir := 1.0
var _target: PlayerController
var _legs: Array[Node3D] = []
var _time := 0.0
var _hiss_cooldown := 0.0

const REACH := 1.4
const HALF_WIDTH := 2.6

var _half_length := CaveBuilder.CELL_SIZE * 1.4


## `span` straight cells long, centred on `cell` shifted half a cell by `shift` for span 2.
static func create(id: int, cell: Vector3i, axis: int, span: int = 3, shift: int = 0) -> SpiderEnemy:
	var spider := SpiderEnemy.new()
	spider.spider_id = id
	spider._axis = Vector3(CaveGraph.DIRS[axis])
	spider._half_length = CaveBuilder.CELL_SIZE * float(span) * 0.5 - 1.2
	# The spider lives on the world floor and has no gravity frame of its own, so world up
	# is genuinely its up. Racers are the ones with personal gravity.
	spider._lateral = Vector3.UP.cross(spider._axis).normalized()
	spider._centre = CaveBuilder.cell_to_world(cell) \
		+ Vector3(0.0, -CaveBuilder.CELL_SIZE * 0.5 + CaveBuilder.WALL_THICKNESS * 0.5 + 0.45, 0.0) \
		+ spider._axis * float(shift) * CaveBuilder.CELL_SIZE * 0.5
	spider.position = spider._centre
	return spider


func _ready() -> void:
	add_to_group("hazards")
	add_to_group("spiders")
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.12, 0.1, 0.1)
	shell.roughness = 0.6
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1.0, 0.1, 0.05)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.15, 0.05)
	eye.emission_energy_multiplier = 3.0

	var body := MeshInstance3D.new()
	var abdomen := SphereMesh.new()
	abdomen.radius = 0.55
	abdomen.height = 0.8
	body.mesh = abdomen
	body.material_override = shell
	body.position = Vector3(0, 0.25, 0.45)
	add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.32
	head_mesh.height = 0.5
	head.mesh = head_mesh
	head.material_override = shell
	head.position = Vector3(0, 0.2, -0.25)
	add_child(head)
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.07
		em.height = 0.14
		e.mesh = em
		e.material_override = eye
		e.position = Vector3(0.12 * side, 0.3, -0.52)
		add_child(e)
	for i in 8:
		var pivot := Node3D.new()
		var side := -1.0 if i < 4 else 1.0
		pivot.position = Vector3(0.25 * side, 0.2, -0.3 + 0.22 * float(i % 4))
		pivot.rotation.y = side * (PI * 0.5) + (float(i % 4) - 1.5) * 0.35 * -side
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.035
		lm.bottom_radius = 0.05
		lm.height = 1.0
		lm.radial_segments = 5
		leg.mesh = lm
		leg.material_override = shell
		leg.position = Vector3(0.0, -0.1, -0.45)
		leg.rotation = Vector3(-0.9, 0.0, 0.0)
		pivot.add_child(leg)
		add_child(pivot)
		_legs.append(pivot)


func _physics_process(delta: float) -> void:
	_time += delta
	_hiss_cooldown -= delta
	var speed := AppConfig.SPIDER_PATROL_SPEED
	var move := _axis * _dir

	match _state:
		State.PATROL:
			var along := (global_position - _centre).dot(_axis)
			if absf(along) > _half_length - 0.5:
				_dir = -signf(along)
			move = _axis * _dir
			_target = _find_prey()
			if _target != null:
				_state = State.LUNGE
				_state_timer = 2.5
				if _hiss_cooldown <= 0.0:
					_hiss_cooldown = 3.0
					AudioManager.play_sfx_3d("spider", global_position, 2.0)
		State.LUNGE:
			_state_timer -= delta
			if _target == null or not is_instance_valid(_target) or _state_timer <= 0.0 \
					or not _is_prey(_target):
				if _target != null and is_instance_valid(_target) and _target.is_local_player \
						and _target.global_position.distance_to(global_position) < 3.0:
					NearMiss.trigger(_target)
				_begin_retreat()
			else:
				var to := _target.global_position - global_position
				to.y = 0.0
				speed = AppConfig.SPIDER_LUNGE_SPEED
				move = to.normalized()
				if to.length() < REACH:
					_target.health.apply_damage(AppConfig.DAMAGE_SPIDER, "spider_%d" % spider_id, 1.5)
					_begin_retreat()
		State.RETREAT:
			_state_timer -= delta
			speed = AppConfig.SPIDER_PATROL_SPEED * 1.4
			if _state_timer <= 0.0:
				_state = State.PATROL

	var next := global_position + move * speed * delta
	# Clamp to the corridor so the spider can never walk into rock.
	var rel := next - _centre
	var a := clampf(rel.dot(_axis), -_half_length, _half_length)
	var l := clampf(rel.dot(_lateral), -HALF_WIDTH, HALF_WIDTH)
	global_position = _centre + _axis * a + _lateral * l
	if move.length_squared() > 0.01:
		var face := Basis.looking_at(move.normalized(), Vector3.UP)
		global_basis = global_basis.slerp(face, 1.0 - exp(-10.0 * delta))
	var gait := speed * 3.2
	for i in _legs.size():
		_legs[i].rotation.x = sin(_time * gait + float(i) * PI * 0.5) * 0.35


func _begin_retreat() -> void:
	_state = State.RETREAT
	_state_timer = AppConfig.SPIDER_RETREAT_TIME
	if _target != null and is_instance_valid(_target):
		var away := global_position - _target.global_position
		_dir = signf(away.dot(_axis)) if absf(away.dot(_axis)) > 0.1 else -_dir
	_target = null


func _find_prey() -> PlayerController:
	var best: PlayerController = null
	var best_d := AppConfig.SPIDER_SENSE_RANGE
	for node in get_tree().get_nodes_in_group("racers"):
		var racer := node as PlayerController
		if racer == null or not _is_prey(racer):
			continue
		var d := racer.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = racer
	return best


## Only racers down on the world floor near its corridor. The ceiling is safe.
func _is_prey(racer: PlayerController) -> bool:
	if racer.health.is_eliminated or not racer.input_enabled:
		return false
	var rel := racer.global_position - _centre
	return absf(rel.y) < 2.2 and absf(rel.dot(_axis)) < _half_length + 1.0 \
		and absf(rel.dot(_lateral)) < CaveBuilder.CELL_SIZE * 0.5
