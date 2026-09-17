extends Node
## Master Prompt 3 regressions with real physics bodies and the real match objects:
## fire contact vs the ceiling bypass, racer-to-racer collision on all six surfaces, spikes.
## Run: godot --headless --fixed-fps 60 res://tests/test_prompt3.tscn

const CARDINALS: Array[Vector3] = [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_fire_ceiling_bypass()
	await _test_racer_collision()
	await _test_spikes()

	print("")
	print("==================================================")
	print("  PROMPT 3   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


# --- Helpers ----------------------------------------------------------------------------

## A closed box of world collision: `half` is the clear half-extent on each axis.
func _room(centre: Vector3, half: Vector3) -> StaticBody3D:
	var room := StaticBody3D.new()
	room.collision_layer = CaveBuilder.LAYER_WORLD
	add_child(room)
	for axis: Vector3 in CARDINALS:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var size := (half + Vector3.ONE) * 2.0
		var a := axis.abs()
		size = size - a * size + a * 1.0
		box.size = size
		shape.shape = box
		shape.position = axis * (half.dot(a) + 0.5)
		room.add_child(shape)
	room.global_position = centre
	return room


func _racer() -> PlayerController:
	var racer: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	racer.is_local_player = false
	add_child(racer)
	return racer


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle(racer: PlayerController, pos: Vector3, g: Vector3) -> void:
	racer.global_position = pos
	racer.velocity = Vector3.ZERO
	racer.gravity._align_body_to_gravity(g)
	await _frames(40)


## Walk the racer toward a world point by steering in its own movement frame, like a bot.
func _walk_to(racer: PlayerController, target: Vector3, frames: int) -> void:
	for i in frames:
		var axes := racer.movement_axes()
		var to := target - racer.global_position
		to -= (axes["up"] as Vector3) * to.dot(axes["up"])
		if to.length() < 0.3:
			break
		var d := to.normalized()
		racer.move_input = Vector2(d.dot(axes["right"]), -d.dot(axes["forward"]))
		await get_tree().physics_frame
	racer.move_input = Vector2.ZERO


# --- Request 1: fire --------------------------------------------------------------------

func _test_fire_ceiling_bypass() -> void:
	_section("fire: floor contact burns, the ceiling bypass does not")
	# One real tunnel: 4 units clear, floor at FLOOR_Y, 24 long along Z.
	var centre := Vector3(60, 20, -60)
	var t := CaveBuilder.TUNNEL_HALF
	var room := _room(centre + Vector3(0, 0, 0), Vector3(t, t, 12))
	var cell := Node3D.new()
	add_child(cell)
	cell.global_position = centre
	# Side 0: the patch is pushed to +X, the -X edge is clear.
	var fire := FireHazard.create(7, 0, t)
	cell.add_child(fire)
	await _frames(2)
	var top := fire.global_position.y + fire.flame_height
	var ceiling := centre.y + t
	_check("flame volume leaves a capsule plus margin under a 4-unit tunnel ceiling (top %.2f, ceiling %.2f)" % [top, ceiling],
		ceiling - top >= 1.8 + 0.4)

	var racer := _racer()
	var hurt := [0]
	racer.health.damaged.connect(func(_a: float, s: String) -> void:
		if s.begins_with("fire"):
			hurt[0] += 1)
	var fx := fire.global_position.x
	# Ceiling: one 180 and walk the length of the tunnel straight over the flames.
	await _settle(racer, Vector3(fx, centre.y + 1.0, centre.z - 10), Vector3.UP)
	_check("racer stands on the ceiling", racer.is_on_floor())
	await _walk_to(racer, Vector3(fx, racer.global_position.y, centre.z + 10), 240)
	_check("walked over the fire on the ceiling", racer.global_position.z > centre.z + 8)
	_check("the ceiling bypass takes no fire damage", hurt[0] == 0 and is_equal_approx(racer.health.hearts, 5.0))

	# Wall on the clear side: walk past, outside the volume.
	await _settle(racer, Vector3(centre.x - t + 1.0, centre.y, centre.z + 10), Vector3.LEFT)
	_check("racer stands on the clear-side wall", racer.is_on_floor())
	await _walk_to(racer, Vector3(racer.global_position.x, centre.y, centre.z - 10), 240)
	_check("walked past the fire along the clear wall", racer.global_position.z < centre.z - 8)
	_check("wall traversal outside the flames is safe", hurt[0] == 0)

	# Floor: straight through the patch.
	await _settle(racer, Vector3(fx, centre.y - 1.0, centre.z - 10), Vector3.DOWN)
	await _walk_to(racer, Vector3(fx, racer.global_position.y, centre.z), 200)
	await _frames(10)
	_check("floor contact burns", hurt[0] >= 1 and racer.health.hearts < 5.0)
	var hearts := racer.health.hearts
	await _frames(20)
	_check("the tick cooldown holds (no burn every frame)", racer.health.hearts >= hearts - AppConfig.DAMAGE_FIRE)
	await _walk_to(racer, Vector3(fx, racer.global_position.y, centre.z + 10), 200)
	hearts = racer.health.hearts
	await _frames(150)
	_check("leaving the flames stops the damage", is_equal_approx(racer.health.hearts, hearts))
	_check("the burn left the racer alive", not racer.health.is_eliminated)

	racer.queue_free()
	cell.queue_free()
	room.queue_free()
	await _frames(2)


# --- Request 8: racers ------------------------------------------------------------------

func _test_racer_collision() -> void:
	_section("racers collide with each other on every surface")
	var centre := Vector3(-60, 20, 60)
	var room := _room(centre, Vector3(6, 6, 6))
	var a := _racer()
	var b := _racer()
	for g: Vector3 in CARDINALS:
		var up := -g
		var side := Vector3.RIGHT if absf(up.x) < 0.5 else Vector3.BACK
		var floor_point := centre - up * 5.0
		await _settle(a, floor_point - side * 3.0, g)
		await _settle(b, floor_point + side * 0.0, g)
		await _walk_to(a, floor_point + side * 3.0, 150)
		var gap := a.global_position.distance_to(b.global_position)
		_check("%s gravity: a walking racer cannot pass through a standing one (gap %.2f)" % [_name(g), gap],
			gap > 0.7 and (a.global_position - floor_point).dot(side) < 0.0)
	# Merged start: two racers placed inside each other push apart.
	await _settle(a, centre - Vector3(0, 5, 0), Vector3.DOWN)
	b.gravity._align_body_to_gravity(Vector3.DOWN)
	b.global_position = a.global_position + Vector3(0.3, 0, 0)
	await _frames(30)
	_check("overlapping racers separate (gap %.2f)" % a.global_position.distance_to(b.global_position),
		a.global_position.distance_to(b.global_position) > 0.6)
	# A finished or eliminated racer no longer blocks.
	b.set_solid(false)
	await _settle(b, centre - Vector3(0, 5, 0), Vector3.DOWN)
	await _settle(a, centre - Vector3(3, 5, 0), Vector3.DOWN)
	await _walk_to(a, centre - Vector3(-3, 5, 0), 150)
	_check("a non-solid (finished/eliminated) racer is walked through", a.global_position.x > centre.x + 2.0)
	a.queue_free()
	b.queue_free()
	room.queue_free()
	await _frames(2)


# --- Request 8: spikes ------------------------------------------------------------------

func _test_spikes() -> void:
	_section("spikes block and hurt once per cooldown")
	var centre := Vector3(-60, 20, -60)
	var room := _room(centre, Vector3(6, 6, 6))
	var spike := SpikeHazard.create(3, 2.0, 0.5, false)
	add_child(spike)
	spike.global_position = centre - Vector3(0, 6, 0)
	var racer := _racer()
	var hits := [0]
	racer.health.damaged.connect(func(_a: float, s: String) -> void:
		if s.begins_with("spike"):
			hits[0] += 1)
	await _settle(racer, centre + Vector3(-4, -5, 0), Vector3.DOWN)
	# Sprint straight into it.
	racer.sprint_input = true
	await _walk_to(racer, centre + Vector3(4, -5, 0), 90)
	racer.sprint_input = false
	_check("a sprinting racer does not pass through a spike (x %.2f)" % (racer.global_position.x - centre.x),
		racer.global_position.x < centre.x - 0.4)
	_check("touching a spike hurts", hits[0] >= 1)
	_check("once per cooldown, not every frame", hits[0] <= 1)
	var crystal := CaveBuilder.new()._solid_box(Vector3(0.95, 1.45, 0.6), Vector3(0, 0.72, 0.1))
	add_child(crystal)
	crystal.global_position = centre + Vector3(0, -6, 4)
	await _settle(racer, centre + Vector3(0, -5, 1), Vector3.DOWN)
	await _walk_to(racer, centre + Vector3(0, -5, 6), 90)
	_check("a crystal cluster blocks like it looks", racer.global_position.z < centre.z + 3.8)
	racer.queue_free()
	spike.queue_free()
	crystal.queue_free()
	room.queue_free()
	await _frames(2)


func _name(g: Vector3) -> String:
	for i in CARDINALS.size():
		if CARDINALS[i].is_equal_approx(g):
			return ["down", "up", "-X", "+X", "-Z", "+Z"][i]
	return str(g)


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
