extends Node
## AXIS-011 -- the physical controller agrees with CaveValidator's transition rules.
## The validator claims a racer under sideways gravity can walk along a wall into a shaft
## above, and that a racer falls through any open face in its gravity direction. This drives
## a real PlayerController through real generated cave geometry to check both.
## Run: godot --headless res://tests/test_wallwalk.tscn

const SEEDS := [4242, 11, 23, 77, 1337]

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	var climbed := 0
	var attempts := 0
	var dropped := 0
	var drop_attempts := 0
	for s: int in SEEDS:
		var gen := CaveGenerator.new()
		var graph := gen.generate(s)
		var root := Node3D.new()
		add_child(root)
		CaveBuilder.new().build(graph, root, -1)
		await get_tree().physics_frame

		var shaft := _find_wall_shaft(graph)
		if shaft != Vector3i(-99, -99, -99):
			attempts += 1
			if await _walk_up_wall(root, graph, shaft):
				climbed += 1
		var drop := _find_drop(graph)
		if drop != Vector3i(-99, -99, -99):
			drop_attempts += 1
			if await _fall_through(root, drop):
				dropped += 1
		root.queue_free()
		await get_tree().physics_frame

	print("   wall climbs %d / %d, drops %d / %d" % [climbed, attempts, dropped, drop_attempts])
	_check(attempts > 0, "found shafts with a climbable wall to test")
	_check(climbed == attempts, "under +X gravity a racer walks up the east wall into the shaft above")
	_check(drop_attempts > 0 and dropped == drop_attempts, "under normal gravity a racer drops through an open floor")

	print("")
	print("==================================================")
	print("  AXIS-011 WALLWALK   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


## A cell with a shaft up whose east wall is solid in both it and the cell above, with
## nothing on its floor that could snag the capsule.
func _find_wall_shaft(graph: CaveGraph) -> Vector3i:
	for c: Vector3i in graph.sorted_cells():
		var above: Vector3i = c + CaveGraph.DIRS[CaveGraph.DIR_UP]
		if graph.is_linked(c, CaveGraph.DIR_UP) and not graph.is_linked(c, CaveGraph.DIR_PLUS_X) \
				and not graph.is_linked(above, CaveGraph.DIR_PLUS_X) and not graph.is_linked(above, CaveGraph.DIR_UP) \
				and graph.features_at(above).is_empty() and graph.features_at(c).is_empty():
			return c
	return Vector3i(-99, -99, -99)


func _find_drop(graph: CaveGraph) -> Vector3i:
	for c: Vector3i in graph.sorted_cells():
		if graph.is_linked(c, CaveGraph.DIR_DOWN) and graph.features_at(c).is_empty():
			var ok := true
			for f: Dictionary in graph.features:
				if f["kind"] == "crumble" and f["cell"] == c:
					ok = false
			if ok:
				return c
	return Vector3i(-99, -99, -99)


func _spawn(root: Node3D, at: Vector3) -> PlayerController:
	var racer: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	racer.is_local_player = false
	root.add_child(racer)
	racer.global_position = at
	return racer


func _walk_up_wall(root: Node3D, graph: CaveGraph, c: Vector3i) -> bool:
	var racer := _spawn(root, CaveBuilder.cell_to_world(c))
	racer.gravity._align_body_to_gravity(Vector3.RIGHT)
	var target := CaveBuilder.cell_to_world(c + CaveGraph.DIRS[CaveGraph.DIR_UP])
	var reached := false
	for i in 60 * 6:
		# Walk world-up, which is along the wall now that +X is down.
		var local := racer.global_basis.inverse() * Vector3.UP
		racer.move_input = Vector2(local.x, local.z).normalized()
		await get_tree().physics_frame
		if CaveBuilder.world_to_cell(racer.global_position) == c + CaveGraph.DIRS[CaveGraph.DIR_UP] \
				and racer.global_position.y > target.y - 2.0:
			reached = true
			break
	if not reached:
		print("   seed cell %s: stuck at %s (cell %s)" % [c, racer.global_position,
			CaveBuilder.world_to_cell(racer.global_position)])
	racer.queue_free()
	return reached


func _fall_through(root: Node3D, c: Vector3i) -> bool:
	var racer := _spawn(root, CaveBuilder.cell_to_world(c))
	var below: Vector3i = c + CaveGraph.DIRS[CaveGraph.DIR_DOWN]
	var reached := false
	for i in 60 * 4:
		await get_tree().physics_frame
		if CaveBuilder.world_to_cell(racer.global_position).y <= below.y:
			reached = true
			break
	racer.queue_free()
	return reached


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
