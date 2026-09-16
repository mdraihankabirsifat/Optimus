class_name CaveGenerator
extends RefCounted
## Seeded cave generation. Produces a CaveGraph and nothing else -- it never touches nodes.
##
## SOLVABLE BY CONSTRUCTION. Rather than generating an arbitrary maze and then proving a
## gravity-aware route exists through it, we carve the guaranteed route first and braid the
## rest of the cave on afterwards. Adding edges to a graph can never disconnect it, so the
## spine remains valid no matter what braiding does. That turns an expensive state-space
## search into a cheap assertion. See the critical design review in docs/MVP_SCOPE.md.
##
## Traversal cost model: horizontal travel and falling are free; climbing one cell (8 world
## units) cannot be jumped and costs exactly one Move charge. So the spine's climb count is
## the number of charges a racer needs to finish, and it is capped below the starting five.

## Bump when generation logic changes. Peers with different versions cannot race together.
const VERSION := 2

## Set dressing and pickups. Dead ends are rewarded with boxes far more often than
## corridors are, so exploring a wrong turn is a gamble rather than a pure loss.
var dead_end_box_chance := 0.7
var max_boxes := 12
var max_fires := 9
var max_torches := 10
var crystal_colours := 4

var size := Vector3i(6, 4, 6)
## Racers start with 5 charges; the guaranteed route may use at most this many, leaving
## the rest as genuine strategic choice rather than a tax.
var max_spine_climbs := 3
var min_spawn_finish_distance := 8
var branch_attempts := 45
var loop_attempts := 30
## Fraction of LOOPS allowed to stay on one Y level. Branches are always horizontal --
## see _pick_branch_dir.
##
## Vertical links are not free to traverse -- crossing one costs a Move charge, and racers
## only ever get five. Scattering vertical connections everywhere fragments each floor into
## pieces that cannot be explored without paying, which strands anyone searching blind.
## Keeping braiding mostly horizontal makes each level explorable for free and turns the
## remaining vertical links into deliberate, readable moments.
var horizontal_bias := 0.85
var max_attempts := 24

var last_failure := ""
var attempts_used := 0

var _rng := RandomNumberGenerator.new()
var _graph: CaveGraph


## Returns a validated CaveGraph, or null if every attempt failed (last_failure says why).
func generate(p_seed: int) -> CaveGraph:
	attempts_used = 0
	for attempt in max_attempts:
		attempts_used = attempt + 1
		# Deterministic per (seed, attempt) so a repaired cave is still reproducible.
		_rng.seed = p_seed * 7919 + attempt
		_graph = CaveGraph.new()
		if _build() and _validate():
			return _graph
	return null


func _build() -> bool:
	if not _carve_spine():
		return false
	_add_branches()
	_add_loops()
	_place_hazards_and_boxes()
	_place_decor()
	return true


## Fire and mystery boxes, from the same seeded RNG as the cave itself.
##
## Fire never appears near spawn, never in a shaft cell (landing in flames after a forced
## drop reads as unfair), and always leaves one edge of the cell clear. Boxes favour dead
## ends so a wrong turn can still pay off.
func _place_hazards_and_boxes() -> void:
	var distances := _graph.distances_from(_graph.spawn_cell)
	var taken := {_graph.spawn_cell: true, _graph.finish_cell: true}
	var fires := 0
	var box_count := 0

	for c: Vector3i in _graph.sorted_cells():
		if taken.has(c) or fires >= max_fires:
			continue
		var hops: int = int(distances.get(c, 0))
		if hops < AppConfig.HAZARD_MIN_SPAWN_DISTANCE:
			continue
		if _graph.has_vertical_link(c):
			continue
		if _rng.randf() < AppConfig.FIRE_DENSITY:
			_graph.hazards.append({"cell": c, "side": _rng.randi_range(0, 3)})
			taken[c] = true
			fires += 1

	for c: Vector3i in _graph.sorted_cells():
		if taken.has(c) or box_count >= max_boxes:
			continue
		var hops: int = int(distances.get(c, 0))
		if hops < AppConfig.BOX_MIN_SPAWN_DISTANCE:
			continue
		var chance: float = dead_end_box_chance if _graph.degree(c) == 1 \
			else AppConfig.BOX_DENSITY * 0.5
		if _rng.randf() < chance:
			_graph.boxes.append({"cell": c, "corner": _rng.randi_range(0, 3), "index": box_count})
			taken[c] = true
			box_count += 1


## Landmarks so no two chambers read alike, plus a soft environmental cue: cells within
## two hops of the finish carry ember crystals. Warmth near the exit rewards attention
## without ever marking the exit itself.
func _place_decor() -> void:
	var near_exit := _graph.distances_from(_graph.finish_cell)
	var torches := 0
	for c: Vector3i in _graph.sorted_cells():
		if c == _graph.finish_cell:
			continue
		var exit_hops: int = int(near_exit.get(c, 99))
		if exit_hops <= 2 and c != _graph.spawn_cell:
			_graph.decor.append({"cell": c, "kind": "ember", "variant": _rng.randi_range(0, 3)})

		if _graph.degree(c) >= 3 and torches < max_torches and _rng.randf() < 0.55:
			_graph.decor.append({"cell": c, "kind": "torch", "variant": _rng.randi_range(0, 3)})
			torches += 1

		var roll := _rng.randf()
		if roll < 0.30:
			_graph.decor.append({"cell": c, "kind": "stalagmite", "variant": _rng.randi_range(0, 7)})
		elif roll < 0.52:
			_graph.decor.append({"cell": c, "kind": "stalactite", "variant": _rng.randi_range(0, 7)})
		elif roll < 0.70:
			_graph.decor.append({"cell": c, "kind": "crystal", "variant": _rng.randi_range(0, crystal_colours - 1)})
		elif roll < 0.82:
			_graph.decor.append({"cell": c, "kind": "moss", "variant": _rng.randi_range(0, 3)})


## Walk from spawn to finish in legs: wander horizontally, climb, wander, climb, wander.
## The number of climbs is chosen up front, which is what bounds the Move cost.
func _carve_spine() -> bool:
	var current := Vector3i(
		_rng.randi_range(0, size.x - 1), 0, _rng.randi_range(0, size.z - 1))
	_graph.spawn_cell = current
	_graph.add_cell(current)
	_graph.spine.append(current)

	var climbs: int = _rng.randi_range(2, mini(max_spine_climbs, size.y - 1))
	var last_dir := -1

	for leg in climbs + 1:
		for step in _rng.randi_range(3, 6):
			var dir_index := _pick_wander_dir(current, last_dir)
			if dir_index == -1:
				break
			var next: Vector3i = current + CaveGraph.DIRS[dir_index]
			_graph.link(current, next)
			current = next
			_graph.spine.append(current)
			last_dir = dir_index

		if leg < climbs:
			var up: Vector3i = current + CaveGraph.DIRS[CaveGraph.DIR_UP]
			if not _in_bounds(up):
				last_failure = "spine climbed out of bounds"
				return false
			_graph.link(current, up)
			current = up
			_graph.spine.append(current)
			last_dir = CaveGraph.DIR_UP

	_graph.finish_cell = current
	return true


## Pick a horizontal direction that stays in bounds and avoids immediately doubling back,
## which is what keeps corridors from collapsing into a two-cell shuffle.
func _pick_wander_dir(from: Vector3i, last_dir: int) -> int:
	var options: Array[int] = []
	var fallback: Array[int] = []
	for dir_index: int in CaveGraph.FLAT_DIRS:
		if not _in_bounds(from + CaveGraph.DIRS[dir_index]):
			continue
		fallback.append(dir_index)
		if last_dir != -1 and dir_index == CaveGraph.opposite(last_dir):
			continue
		options.append(dir_index)
	if not options.is_empty():
		return options[_rng.randi_range(0, options.size() - 1)]
	if not fallback.is_empty():
		return fallback[_rng.randi_range(0, fallback.size() - 1)]
	return -1


## Side passages and dead ends. These are what make the cave worth exploring and what
## punish a racer who guesses wrong -- without them the spine is a corridor, not a maze.
func _add_branches() -> void:
	var existing: Array = _graph.cells.keys()
	for i in branch_attempts:
		var origin: Vector3i = existing[_rng.randi_range(0, existing.size() - 1)]
		var current := origin
		for depth in _rng.randi_range(1, 3):
			var dir_index := _pick_branch_dir(current)
			if dir_index == -1:
				break
			var next: Vector3i = current + CaveGraph.DIRS[dir_index]
			if _graph.has_cell(next):
				break
			_graph.link(current, next)
			current = next


## Branches are always horizontal, without exception.
##
## A branch creates NEW cells, so a branch that climbed would produce a dead end whose only
## exit is vertical -- and a racer who arrives there with no charges left is softlocked,
## unable to move at all. Loops are free to go vertical because they only ever connect
## cells that already exist, so they cannot trap anyone.
func _pick_branch_dir(from: Vector3i) -> int:
	var options: Array[int] = []
	for dir_index: int in CaveGraph.FLAT_DIRS:
		var target: Vector3i = from + CaveGraph.DIRS[dir_index]
		if _in_bounds(target) and not _graph.has_cell(target):
			options.append(dir_index)
	if options.is_empty():
		return -1
	return options[_rng.randi_range(0, options.size() - 1)]


## Braid the maze: link cells that are already adjacent but unconnected. Every link added
## here creates a cycle, letting racers return to earlier regions by a different route.
## This can only ever make the cave easier to traverse, never harder, so the spine
## guarantee survives untouched.
func _add_loops() -> void:
	var existing: Array = _graph.cells.keys()
	for i in loop_attempts:
		var c: Vector3i = existing[_rng.randi_range(0, existing.size() - 1)]
		var dir_index := _rng.randi_range(0, 5)
		if _rng.randf() < horizontal_bias:
			dir_index = CaveGraph.FLAT_DIRS[_rng.randi_range(0, 3)]
		var n: Vector3i = c + CaveGraph.DIRS[dir_index]
		if not _graph.has_cell(n) or _graph.is_linked(c, dir_index):
			continue
		_graph.link(c, n)


func _validate() -> bool:
	var climbs := _graph.spine_climb_cost()
	if climbs > max_spine_climbs:
		last_failure = "spine needs %d climbs, budget is %d" % [climbs, max_spine_climbs]
		return false

	if not _graph.is_fully_connected():
		last_failure = "cave contains unreachable cells"
		return false

	var distances := _graph.distances_from(_graph.spawn_cell)
	if not distances.has(_graph.finish_cell):
		last_failure = "finish unreachable from spawn"
		return false

	var hops: int = distances[_graph.finish_cell]
	if hops < min_spawn_finish_distance:
		last_failure = "spawn and finish only %d hops apart" % hops
		return false

	if _graph.cycle_count() < 1:
		last_failure = "cave has no loop"
		return false

	if _graph.vertical_link_count() < 2:
		last_failure = "cave has too little verticality"
		return false

	# The theme must be physically present in the level, not just in the mechanic.
	if _graph.max_degrees_of_freedom() < 3:
		last_failure = "no cell offers all three degrees of freedom"
		return false

	return true


func _in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.x < size.x \
		and c.y >= 0 and c.y < size.y \
		and c.z >= 0 and c.z < size.z
