extends Node
## LEVEL-008 — cave generation validation across many seeds.
## Run: godot --headless res://tests/test_cave.tscn
##
## Asserts the invariants a racer depends on: the cave is connected, the finish is far
## from spawn and reachable within the starting Move budget, loops and verticality exist,
## and the same seed always produces the same cave on every machine.

const SEED_COUNT := 200

var _passed := 0
var _failed := 0


func _ready() -> void:
	# quit() is ignored if called before the tree reaches its main loop.
	await get_tree().process_frame

	var gen := CaveGenerator.new()

	var failures := 0
	var total_cells := 0
	var total_hops := 0
	var total_climbs := 0
	var total_cycles := 0
	var total_attempts := 0
	var worst_climbs := 0
	var min_hops := 9999
	var total_hazards := 0
	var worst_hazards := 0

	print("\nGenerating %d seeds..." % SEED_COUNT)

	for s in SEED_COUNT:
		var graph := gen.generate(s)
		if graph == null:
			failures += 1
			print("   seed %d FAILED: %s" % [s, gen.last_failure])
			continue

		total_attempts += gen.attempts_used
		total_cells += graph.cell_count()
		total_cycles += graph.cycle_count()

		var climbs := graph.spine_climb_cost()
		total_climbs += climbs
		worst_climbs = maxi(worst_climbs, climbs)

		var hops: int = graph.distances_from(graph.spawn_cell).get(graph.finish_cell, -1)
		total_hops += hops
		min_hops = mini(min_hops, hops)
		total_hazards += graph.hazards.size()
		worst_hazards = maxi(worst_hazards, graph.hazards.size())

		# Per-seed invariants. Report only the first breach of each kind to stay readable.
		if not graph.is_fully_connected():
			_fail("seed %d: unreachable cells" % s)
		if climbs > AppConfig.MOVE_CHARGES_START:
			_fail("seed %d: needs %d Moves, racers only have %d"
				% [s, climbs, AppConfig.MOVE_CHARGES_START])
		if hops < 8:
			_fail("seed %d: spawn and finish only %d hops apart" % [s, hops])
		if graph.cycle_count() < 1:
			_fail("seed %d: no loop" % s)
		if graph.vertical_link_count() < 2:
			_fail("seed %d: insufficient verticality" % s)
		if graph.max_degrees_of_freedom() < 3:
			_fail("seed %d: no 3-DOF junction" % s)
		if graph.spawn_cell == graph.finish_cell:
			_fail("seed %d: spawn is the finish" % s)

		# Hazards must never sit on the finish or in the opening chamber. A racer burned
		# before they can move is the exact unfairness the design rules out.
		var spawn_dist: Dictionary = graph.distances_from(graph.spawn_cell)
		for h: Dictionary in graph.hazards:
			var hc: Vector3i = h["cell"]
			if hc == graph.finish_cell:
				_fail("seed %d: hazard on the finish cell" % s)
			if int(spawn_dist.get(hc, 99)) <= 1:
				_fail("seed %d: hazard in the spawn safe zone" % s)
			if not graph.has_cell(hc):
				_fail("seed %d: hazard outside the cave" % s)

	_check("every seed generated a cave", failures == 0)
	_check("no seed exceeds the 5-charge budget", worst_climbs <= AppConfig.MOVE_CHARGES_START)
	_check("closest spawn-finish pair is still far enough", min_hops >= 8)
	_check("every cave has at least one hazard", worst_hazards > 0)

	_test_determinism()

	var ok: int = SEED_COUNT - failures
	if ok > 0:
		print("\n-- statistics over %d caves" % ok)
		print("   cells        avg %.1f" % (float(total_cells) / ok))
		print("   spawn->exit  avg %.1f hops, min %d" % [float(total_hops) / ok, min_hops])
		print("   Moves needed avg %.2f, worst %d (racers start with %d)"
			% [float(total_climbs) / ok, worst_climbs, AppConfig.MOVE_CHARGES_START])
		print("   loops        avg %.1f" % (float(total_cycles) / ok))
		print("   hazards      avg %.1f, most %d" % [float(total_hazards) / ok, worst_hazards])
		print("   attempts     avg %.2f per cave" % (float(total_attempts) / ok))

	print("")
	print("==================================================")
	print("  LEVEL-008   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


## Determinism is what lets a networked match ship a 4-byte seed instead of a level.
func _test_determinism() -> void:
	var a := CaveGenerator.new()
	var b := CaveGenerator.new()
	var identical := true
	for s in [0, 1, 42, 1337, 99999]:
		var ga := a.generate(s)
		var gb := b.generate(s)
		if ga == null or gb == null or ga.graph_hash() != gb.graph_hash():
			identical = false
			break
	_check("same seed produces an identical cave", identical)

	var distinct := {}
	for s in 25:
		var g := CaveGenerator.new().generate(s)
		if g != null:
			distinct[g.graph_hash()] = true
	_check("different seeds produce different caves", distinct.size() >= 24)


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)


func _fail(label: String) -> void:
	if _failed < 10:
		print("   FAIL  %s" % label)
	_failed += 1
