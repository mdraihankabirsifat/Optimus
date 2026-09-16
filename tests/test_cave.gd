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

	_check("every seed generated a cave", failures == 0)
	_check("no seed exceeds the 5-charge budget", worst_climbs <= AppConfig.MOVE_CHARGES_START)
	_check("closest spawn-finish pair is still far enough", min_hops >= 8)

	_test_determinism()
	_test_presets_and_features()

	var ok: int = SEED_COUNT - failures
	if ok > 0:
		print("\n-- statistics over %d caves" % ok)
		print("   cells        avg %.1f" % (float(total_cells) / ok))
		print("   spawn->exit  avg %.1f hops, min %d" % [float(total_hops) / ok, min_hops])
		print("   Moves needed avg %.2f, worst %d (racers start with %d)"
			% [float(total_climbs) / ok, worst_climbs, AppConfig.MOVE_CHARGES_START])
		print("   loops        avg %.1f" % (float(total_cycles) / ok))
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


## LEVEL-011, HAZ-002..004, FUN-001/004: every size generates, and no feature can make the
## guaranteed route worse.
func _test_presets_and_features() -> void:
	for p in CaveGenerator.SIZE_PRESETS.size():
		var fails := 0
		var bad_crumble := 0
		var bad_spawn := 0
		var features := 0
		for s in 40:
			var gen := CaveGenerator.new()
			gen.apply_size_preset(p)
			var g := gen.generate(s)
			if g == null:
				fails += 1
				continue
			var spine_pairs := {}
			for i in range(1, g.spine.size()):
				spine_pairs[str(g.spine[i - 1]) + str(g.spine[i])] = true
				spine_pairs[str(g.spine[i]) + str(g.spine[i - 1])] = true
			for f: Dictionary in g.features:
				features += 1
				var c: Vector3i = f["cell"]
				if f["kind"] != "shortcut" and (c == g.spawn_cell or c == g.finish_cell):
					bad_spawn += 1
				if f["kind"] == "crumble":
					var below: Vector3i = c + CaveGraph.DIRS[CaveGraph.DIR_DOWN]
					if spine_pairs.has(str(below) + str(c)):
						bad_crumble += 1
		var label: String = CaveGenerator.SIZE_PRESETS[p]["name"]
		_check("%s caves all generate (%d failed of 40)" % [label, fails], fails == 0)
		_check("%s: no crumbling cover on the guaranteed route" % label, bad_crumble == 0)
		_check("%s: no feature in the spawn or finish cell" % label, bad_spawn == 0)
		_check("%s: caves actually contain features" % label, features > 40)


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
