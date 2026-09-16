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
	var total_min_moves := 0
	var worst_min_moves := 0
	var hash_first := {}

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

		# Gravity-aware solvability over (cell, gravity, Moves left), no loot.
		var need := CaveValidator.min_moves_to_finish(graph, AppConfig.MOVE_CHARGES_START)
		if need == CaveValidator.UNREACHABLE:
			_fail("seed %d: exit unreachable under gravity rules with 5 Moves" % s)
		else:
			total_min_moves += need
			worst_min_moves = maxi(worst_min_moves, need)
			if need > climbs:
				_fail("seed %d: validator needs %d Moves but the spine promised %d" % [s, need, climbs])
		# Structure: links symmetric and in bounds, no overlapping placements.
		var problem := CaveValidator.structural_problem(graph, gen.size)
		if problem != "":
			_fail("seed %d: %s" % [s, problem])
		# Hazard constraints.
		var dist := graph.distances_from(graph.spawn_cell)
		for h: Dictionary in graph.hazards:
			if int(dist.get(h["cell"], 0)) < AppConfig.HAZARD_MIN_SPAWN_DISTANCE:
				_fail("seed %d: fire %s too close to spawn" % [s, h["cell"]])
			if graph.has_vertical_link(h["cell"]):
				_fail("seed %d: fire in a shaft cell %s" % [s, h["cell"]])
		for f: Dictionary in graph.features:
			if f["kind"] in ["piston", "spider"] \
					and int(dist.get(f["cell"], 0)) < AppConfig.HAZARD_MIN_SPAWN_DISTANCE:
				_fail("seed %d: %s at %s too close to spawn" % [s, f["kind"], f["cell"]])
		# The spawn chamber must be explorable on foot before anyone spends a Move.
		if CaveValidator.free_region(graph, graph.spawn_cell).size() < 2:
			_fail("seed %d: spawn is sealed unless a Move is spent" % s)
		hash_first[s] = graph.graph_hash()

	_check("every seed generated a cave", failures == 0)
	_check("no seed exceeds the 5-charge budget", worst_climbs <= AppConfig.MOVE_CHARGES_START)
	_check("closest spawn-finish pair is still far enough", min_hops >= 8)
	_check("gravity-aware search solves every cave within 5 Moves",
		failures == 0 and worst_min_moves <= AppConfig.MOVE_CHARGES_START)
	_test_validator_rules()

	# Same seed, fresh generator: identical graph hash for every one of the 200 seeds.
	var rehash_ok := true
	var regen := CaveGenerator.new()
	for s: int in hash_first:
		var again := regen.generate(s)
		if again == null or again.graph_hash() != int(hash_first[s]):
			rehash_ok = false
			_fail("seed %d: regenerating gave a different graph hash" % s)
			break
	_check("all %d seeds regenerate to the same graph hash" % hash_first.size(), rehash_ok)

	_test_determinism()
	_test_presets_and_features()

	var ok: int = SEED_COUNT - failures
	if ok > 0:
		print("\n-- statistics over %d caves" % ok)
		print("   cells        avg %.1f" % (float(total_cells) / ok))
		print("   spawn->exit  avg %.1f hops, min %d" % [float(total_hops) / ok, min_hops])
		print("   Moves needed avg %.2f, worst %d (racers start with %d)"
			% [float(total_climbs) / ok, worst_climbs, AppConfig.MOVE_CHARGES_START])
		print("   gravity-aware minimum Moves avg %.2f, worst %d" % [float(total_min_moves) / ok, worst_min_moves])
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


## Hand-built caves with known answers, so the validator itself is tested rather than trusted.
func _test_validator_rules() -> void:
	var flat := CaveGraph.new()
	flat.link(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	flat.link(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	flat.spawn_cell = Vector3i(0, 0, 0)
	flat.finish_cell = Vector3i(2, 0, 0)
	_check("validator: flat corridor needs 0 Moves", CaveValidator.min_moves_to_finish(flat) == 0)

	var shaft := CaveGraph.new()
	shaft.link(Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	shaft.link(Vector3i(0, 1, 0), Vector3i(0, 2, 0))
	shaft.spawn_cell = Vector3i(0, 0, 0)
	shaft.finish_cell = Vector3i(0, 2, 0)
	_check("validator: a shaft up needs exactly 1 Move", CaveValidator.min_moves_to_finish(shaft) == 1)
	_check("validator: a shaft up is impossible with 0 Moves",
		CaveValidator.min_moves_to_finish(shaft, 0) == CaveValidator.UNREACHABLE)

	# Up one shaft, along the top, down another. Inversions alone cost 2 (flip up, flip back
	# down), but one 90-degree turn to +X does it: walk up the east wall, drop sideways into
	# the top corridor, walk down the second shaft's east wall. The validator must find the 1.
	var arch := CaveGraph.new()
	arch.link(Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	arch.link(Vector3i(0, 1, 0), Vector3i(1, 1, 0))
	arch.link(Vector3i(1, 1, 0), Vector3i(1, 0, 0))
	arch.spawn_cell = Vector3i(0, 0, 0)
	arch.finish_cell = Vector3i(1, 0, 0)
	_check("validator: over an arch costs 1 Move using a wall-walk",
		CaveValidator.min_moves_to_finish(arch) == 1)
	_check("validator: the arch cannot be crossed with 0 Moves",
		CaveValidator.min_moves_to_finish(arch, 0) == CaveValidator.UNREACHABLE)

	var drop := CaveGraph.new()
	drop.link(Vector3i(0, 1, 0), Vector3i(0, 0, 0))
	drop.spawn_cell = Vector3i(0, 1, 0)
	drop.finish_cell = Vector3i(0, 0, 0)
	_check("validator: dropping down a shaft is free", CaveValidator.min_moves_to_finish(drop) == 0)

	# A 90-degree turn climbs too: under +X gravity the east wall runs straight up the shaft.
	var costs := CaveValidator.solve(shaft, Vector3i(0, 0, 0), CaveGraph.DIR_PLUS_X, 0)
	_check("validator: walking up a wall under sideways gravity is free",
		costs.has("0,2,0,%d" % CaveGraph.DIR_PLUS_X))

	var broken := CaveGraph.new()
	broken.link(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	broken.cells[Vector3i(1, 0, 0)] = 0
	broken.spawn_cell = Vector3i(0, 0, 0)
	broken.finish_cell = Vector3i(1, 0, 0)
	_check("validator: a one-way link is reported",
		CaveValidator.structural_problem(broken, Vector3i(4, 4, 4)) != "")


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
