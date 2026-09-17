extends Node
## AXIS-007 — gravity frame verification.
## Run: godot --headless res://tests/test_gravity.tscn
##
## Asserts every 90 and 180 shift from every cardinal orientation produces a valid,
## right-handed, orthonormal basis with local_up matching -gravity_dir, that chained
## rotations do not accumulate drift, and that charges deduct exactly once.

const CARDINALS := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
	Vector3.DOWN, Vector3.BACK, Vector3.FORWARD,
]
const EPSILON := 0.0005

var _player: CharacterBody3D
var _gc: GravityController
var _passed := 0
var _failed := 0
var _denied := false


func _on_shift_denied(_reason: String) -> void:
	_denied = true


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	_player = scene.instantiate()
	_player.is_local_player = false
	add_child(_player)
	await get_tree().process_frame
	_gc = _player.get_node("GravityController")

	_test_snap_to_cardinal()
	_test_all_orientations()
	_test_no_roll_on_inversion()
	_test_chained_drift()
	_test_charge_accounting()
	await _test_protected_vacuum()
	_test_current_frame_axes()
	await _test_current_frame_walking()

	print("")
	print("==================================================")
	print("  AXIS-007   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


# --- Tests --------------------------------------------------------------------

func _test_snap_to_cardinal() -> void:
	_section("snap_to_cardinal")
	_check("slightly off -Y snaps to -Y",
		GravityController.snap_to_cardinal(Vector3(0.1, -0.9, 0.05)) == Vector3.DOWN)
	_check("diagonal favouring +X snaps to +X",
		GravityController.snap_to_cardinal(Vector3(0.8, 0.3, 0.3)) == Vector3.RIGHT)
	_check("exact -Z snaps to -Z",
		GravityController.snap_to_cardinal(Vector3(0, 0, -1)) == Vector3.FORWARD)
	for axis: Vector3 in CARDINALS:
		_check("cardinal %s is its own snap" % axis,
			GravityController.snap_to_cardinal(axis) == axis)


func _test_all_orientations() -> void:
	_section("every shift from every orientation")
	for start: Vector3 in CARDINALS:
		for target: Vector3 in CARDINALS:
			if target == start:
				continue
			_reset_to(start)
			_gc.charges = 5
			_gc.request_shift(target)
			_complete_transition()

			var label := "%s -> %s" % [_name_of(start), _name_of(target)]
			_check("%s: gravity_dir correct" % label,
				_gc.gravity_dir.is_equal_approx(target))
			_check("%s: local_up matches body basis Y" % label,
				_gc.local_up().is_equal_approx(_player.global_basis.y))
			_check("%s: up_direction synced" % label,
				_player.up_direction.is_equal_approx(-target))
			_check("%s: basis orthonormal right-handed" % label,
				_is_valid_basis(_player.global_basis))


func _test_no_roll_on_inversion() -> void:
	_section("180 inversion preserves forward (no camera roll)")
	for start: Vector3 in CARDINALS:
		_reset_to(start)
		_gc.charges = 5
		var before := -_player.global_basis.z
		_gc.request_inversion()
		_complete_transition()
		var after := -_player.global_basis.z
		_check("%s: forward unchanged through inversion" % _name_of(start),
			before.is_equal_approx(after))
		_check("%s: gravity inverted" % _name_of(start),
			_gc.gravity_dir.is_equal_approx(-start))


func _test_chained_drift() -> void:
	_section("chained rotations do not accumulate drift")
	_reset_to(Vector3.DOWN)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 40:
		_gc.charges = 5
		if i % 4 == 3:
			_gc.request_inversion()
		else:
			_gc.request_shift(CARDINALS[rng.randi_range(0, 5)])
		_complete_transition()
		if not _is_valid_basis(_player.global_basis):
			_check("basis still valid after %d chained shifts" % (i + 1), false)
			return
	_check("basis still valid after 40 chained shifts", true)
	_check("gravity still cardinal after 40 shifts",
		CARDINALS.any(func(c: Vector3) -> bool: return c.is_equal_approx(_gc.gravity_dir)))


func _test_charge_accounting() -> void:
	_section("charge accounting")
	_reset_to(Vector3.DOWN)
	_gc.charges = 5

	_gc.request_shift(Vector3.FORWARD)
	_complete_transition()
	_check("one shift costs exactly one charge", _gc.charges == 4)

	# GDScript lambdas capture locals by value, so the flag must live on the instance.
	_gc.shift_denied.connect(_on_shift_denied)

	_denied = false
	_gc.request_shift(_gc.gravity_dir)
	_check("shifting to the current direction is denied", _denied)
	_check("denied shift costs no charge", _gc.charges == 4)

	_gc.charges = 0
	_denied = false
	_gc.request_shift(Vector3.RIGHT)
	_check("shift at zero charges is denied", _denied)
	_check("gravity unchanged when denied", _gc.gravity_dir.is_equal_approx(Vector3.FORWARD))
	_check("charges cannot go negative", _gc.charges == 0)

	_gc.add_charges(99)
	_check("refill clamps to MOVE_CHARGES_MAX", _gc.charges == AppConfig.MOVE_CHARGES_MAX)


## Prompt 2, change #1: movement is interpreted from the CURRENT frame -- current gravity,
## current camera -- in every orientation and after any chain of shifts.
func _test_current_frame_axes() -> void:
	_section("current-frame movement axes")
	var yaws := [0.0, 0.7, -1.9, 2.8]
	for g: Vector3 in CARDINALS:
		for yaw: float in yaws:
			_reset_to(g)
			_player.rotate_object_local(Vector3.UP, yaw)
			_player.head.rotation.x = -0.45
			_check_axes("%s yaw %.1f" % [_name_of(g), yaw])
	# Looking straight along local up must not collapse the axes.
	_reset_to(Vector3.RIGHT)
	_player.head.rotation.x = -AppConfig.PITCH_LIMIT
	_check_axes("+X looking straight down")
	_player.head.rotation.x = AppConfig.PITCH_LIMIT
	_check_axes("+X looking straight up")
	_player.head.rotation.x = 0.0

	# A long chain of shifts: after each, the axes live in the new plane, never the spawn one.
	_reset_to(Vector3.DOWN)
	var spawn_forward: Vector3 = _player.movement_axes()["forward"]
	var chain := [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, Vector3.LEFT, Vector3.BACK,
		Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]
	var left_spawn_plane := 0
	for i in chain.size():
		_gc.charges = 5
		_player.rotate_object_local(Vector3.UP, 0.4 * float(i + 1))
		_player.head.rotation.x = 0.3 - 0.1 * float(i % 5)
		_gc.request_shift(chain[i])
		_complete_transition()
		var label := "chain step %d (%s)" % [i + 1, _name_of(_gc.gravity_dir)]
		_check_axes(label)
		var axes: Dictionary = _player.movement_axes()
		_check("%s: forward has no component along current gravity" % label,
			absf((axes["forward"] as Vector3).dot(_gc.gravity_dir)) < EPSILON)
		if absf(spawn_forward.dot(_gc.gravity_dir)) > 0.5:
			left_spawn_plane += 1
			_check("%s: spawn forward is no longer a movement direction" % label,
				absf((axes["forward"] as Vector3).dot(spawn_forward)) < 0.5 + EPSILON)
	_check("the chain really left the spawn plane", left_spawn_plane > 0)


func _check_axes(label: String) -> void:
	var axes: Dictionary = _player.movement_axes()
	var f: Vector3 = axes["forward"]
	var r: Vector3 = axes["right"]
	var u: Vector3 = axes["up"]
	_check("%s: up is minus current gravity" % label, u.is_equal_approx(-_gc.gravity_dir))
	_check("%s: forward, right unit and in the walk plane" % label,
		absf(f.length() - 1.0) < EPSILON and absf(r.length() - 1.0) < EPSILON
		and absf(f.dot(u)) < EPSILON and absf(r.dot(u)) < EPSILON and absf(f.dot(r)) < EPSILON)
	_check("%s: right is forward x up" % label, r.is_equal_approx(f.cross(u).normalized()))
	var cam: Vector3 = -(_player.head.global_basis.z as Vector3)
	var projected: Vector3 = cam - u * cam.dot(u)
	if projected.length() > 0.05:
		_check("%s: forward is the camera's forward projected" % label,
			f.is_equal_approx(projected.normalized()))


## Real physics: in a sealed room, stand on each of the six surfaces in turn, press W and D,
## then jump. Movement must follow the camera across that surface and the jump must leave it.
func _test_current_frame_walking() -> void:
	_section("current-frame walking on floor, four walls and ceiling")
	var room := StaticBody3D.new()
	room.collision_layer = 1
	add_child(room)
	var half := 7.0
	for axis: Vector3 in CARDINALS:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(16, 16, 16) - axis.abs() * 15.0
		shape.shape = box
		shape.position = axis * (half + 0.5)
		room.add_child(shape)
	# Well inside AppConfig.WORLD_BOUNDS, or out-of-bounds recovery fires every frame.
	room.global_position = Vector3(60, 20, 60)

	var racer: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	racer.is_local_player = false
	add_child(racer)
	await get_tree().physics_frame
	for g: Vector3 in CARDINALS:
		racer.global_position = room.global_position
		racer.velocity = Vector3.ZERO
		racer.gravity._align_body_to_gravity(g)
		racer.rotate_object_local(Vector3.UP, 0.6)
		racer.head.rotation.x = -0.35
		for i in 45:
			await get_tree().physics_frame
		var label := "on the %s surface" % _name_of(g)
		_check("%s: landed" % label, racer.is_on_floor())
		var axes: Dictionary = racer.movement_axes()
		var start := racer.global_position
		racer.move_input = Vector2(0, -1)
		for i in 30:
			await get_tree().physics_frame
		racer.move_input = Vector2.ZERO
		var moved := racer.global_position - start
		_check("%s: W moves along the current camera forward (%.2f)" % [label, moved.dot(axes["forward"])],
			moved.dot(axes["forward"]) > 1.5 and absf(moved.dot(axes["right"])) < 0.4)
		_check("%s: W never pushes off the surface" % label, absf(moved.dot(axes["up"])) < 0.3)
		start = racer.global_position
		racer.move_input = Vector2(1, 0)
		for i in 30:
			await get_tree().physics_frame
		racer.move_input = Vector2.ZERO
		moved = racer.global_position - start
		_check("%s: D moves along the current right" % label,
			moved.dot(axes["right"]) > 1.5 and absf(moved.dot(axes["forward"])) < 0.4)
		for i in 20:
			await get_tree().physics_frame
		racer.jump_requested = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check("%s: jump goes along current local up" % label,
			racer.velocity.dot(-g) > AppConfig.JUMP_VELOCITY * 0.5)
	racer.queue_free()
	room.queue_free()


## AXIS-006: a 180 into a void damages and recovers; it never eliminates.
func _test_protected_vacuum() -> void:
	_section("protected vacuum 180")
	# A real racer on a real floor, so it records safe transforms the way play does.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.collision_layer = 1
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)

	var racer: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	racer.is_local_player = false
	add_child(racer)
	racer.global_position = Vector3(0, 1.0, 0)
	for i in 90:
		await get_tree().physics_frame
	var gc := racer.gravity
	_check("racer recorded a safe grounded transform", not gc._safe_transforms.is_empty())
	var safe_pos: Vector3 = gc._safe_transforms[-1].origin

	gc.request_inversion()
	_check("inversion spends a Move", gc.charges == AppConfig.MOVE_CHARGES_START - 1)
	racer.global_position = Vector3(0, AppConfig.WORLD_BOUNDS + 10.0, 0)
	var hearts := racer.health.hearts
	racer._check_world_bounds()
	_check("vacuum 180 costs exactly one heart",
		is_equal_approx(racer.health.hearts, hearts - AppConfig.DAMAGE_VACUUM_FALL))
	_check("vacuum 180 never eliminates", not racer.health.is_eliminated)
	_check("racer is recovered to its last safe ground",
		racer.global_position.distance_to(safe_pos) < 0.01)
	_check("recovered racer's gravity matches the safe pose", gc.gravity_dir.is_equal_approx(Vector3.DOWN))

	# With no safe ground ever recorded, a plain fall out of the world is unrecoverable.
	var lost: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	lost.is_local_player = false
	add_child(lost)
	lost.global_position = Vector3(0, AppConfig.WORLD_BOUNDS + 50.0, 0)
	lost._check_world_bounds()
	_check("an unrecoverable fall with no safe ground eliminates", lost.health.is_eliminated)
	racer.queue_free()
	lost.queue_free()
	floor_body.queue_free()


# --- Helpers ------------------------------------------------------------------

func _reset_to(dir: Vector3) -> void:
	_gc.is_transitioning = false
	_gc._align_body_to_gravity(dir)


## One large delta drives the transition straight to completion.
func _complete_transition() -> void:
	if _gc.is_transitioning:
		_gc._physics_process(10.0)


func _is_valid_basis(b: Basis) -> bool:
	var x := b.x
	var y := b.y
	var z := b.z
	if absf(x.length() - 1.0) > EPSILON: return false
	if absf(y.length() - 1.0) > EPSILON: return false
	if absf(z.length() - 1.0) > EPSILON: return false
	if absf(x.dot(y)) > EPSILON: return false
	if absf(y.dot(z)) > EPSILON: return false
	if absf(x.dot(z)) > EPSILON: return false
	return absf(b.determinant() - 1.0) <= EPSILON


func _name_of(v: Vector3) -> String:
	if v.is_equal_approx(Vector3.DOWN): return "-Y"
	if v.is_equal_approx(Vector3.UP): return "+Y"
	if v.is_equal_approx(Vector3.LEFT): return "-X"
	if v.is_equal_approx(Vector3.RIGHT): return "+X"
	if v.is_equal_approx(Vector3.FORWARD): return "-Z"
	return "+Z"


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
