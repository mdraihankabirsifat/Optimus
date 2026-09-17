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
## 4: corridor-first tunnels, a route that climbs AND descends, long carved loops.
const VERSION := 4

## Set dressing and pickups. Dead ends are rewarded with boxes far more often than
## corridors are, so exploring a wrong turn is a gamble rather than a pure loss.
var dead_end_box_chance := 0.7
var max_boxes := 12
var max_fires := 9
var max_torches := 10
var crystal_colours := 4

var size := Vector3i(9, 4, 9)
## The guaranteed route's Move cost -- every flip of gravity it needs, up or back down --
## stays at or under this, leaving the rest of the five charges as real choice.
var max_spine_climbs := 3
var min_spawn_finish_distance := 14

## --- Tunnel shape (Prompt 2: a cave, not a house) ---
## Straight corridor runs between turns, in cells (each cell is 8 world units).
var run_min := 3
var run_max := 6
## Horizontal runs per leg of the guaranteed route, between its vertical steps.
var runs_per_leg_min := 2
var runs_per_leg_max := 3
## Vertical steps on the guaranteed route. At least one climbs and one descends.
var vertical_steps_min := 3
var vertical_steps_max := 4
## Dead-end side tunnels.
var branch_count := 8
var branch_len_min := 2
var branch_len_max := 5
## Real cycles: a new tunnel carved from one part of the cave to another part at least
## loop_min_detour hops away, so coming back around means something.
var loop_count := 3
var loop_len_max := 10
var loop_min_detour := 6
var loop_vertical_chance := 0.25
var max_attempts := 40

var last_failure := ""
var attempts_used := 0
## Fewest Moves the last validated cave needs from spawn, found by CaveValidator.
var last_min_moves := 0

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
	# Runs last so it cannot shift any earlier RNG roll: a seed keeps its layout, fire,
	# boxes and decor exactly as they were before features existed.
	_place_features()
	return true


## Named cave sizes for the lobby.
const SIZE_PRESETS := [
	{"name": "Short", "size": Vector3i(7, 3, 7), "min_distance": 10, "branches": 5, "loops": 2,
		"boxes": 8, "fires": 5, "vertical": Vector2i(2, 3), "run": Vector2i(3, 5)},
	{"name": "Standard", "size": Vector3i(9, 4, 9), "min_distance": 14, "branches": 8, "loops": 3,
		"boxes": 12, "fires": 8, "vertical": Vector2i(3, 4), "run": Vector2i(3, 6)},
	{"name": "Long", "size": Vector3i(11, 5, 11), "min_distance": 20, "branches": 12, "loops": 5,
		"boxes": 16, "fires": 11, "vertical": Vector2i(4, 5), "run": Vector2i(4, 7)},
]


func apply_size_preset(index: int) -> void:
	var p: Dictionary = SIZE_PRESETS[clampi(index, 0, SIZE_PRESETS.size() - 1)]
	size = p["size"]
	min_spawn_finish_distance = p["min_distance"]
	branch_count = p["branches"]
	loop_count = p["loops"]
	max_boxes = p["boxes"]
	max_fires = p["fires"]
	vertical_steps_min = (p["vertical"] as Vector2i).x
	vertical_steps_max = (p["vertical"] as Vector2i).y
	run_min = (p["run"] as Vector2i).x
	run_max = (p["run"] as Vector2i).y


## Boost pads, wind, pistons, spiders, crumbling shaft covers, shortcut markers and
## landmark chambers. One feature per cell, nothing dangerous near spawn, and nothing that
## can block the guaranteed route permanently.
func _place_features() -> void:
	var from_spawn := _graph.distances_from(_graph.spawn_cell)
	var taken := {_graph.spawn_cell: true, _graph.finish_cell: true}
	for h: Dictionary in _graph.hazards:
		taken[h["cell"]] = true
	for b: Dictionary in _graph.boxes:
		taken[b["cell"]] = true

	var spine_edges := {}
	for i in range(1, _graph.spine.size()):
		spine_edges[_edge_key(_graph.spine[i - 1], _graph.spine[i])] = true

	var counts := {"pad": 0, "wind": 0, "piston": 0, "spider": 0}
	var limits := {"pad": 5, "wind": 3, "piston": 2, "spider": 2}
	for c: Vector3i in _graph.sorted_cells():
		if taken.has(c):
			continue
		var axis := _graph.straight_axis(c)
		if axis == -1:
			continue
		var hops: int = int(from_spawn.get(c, 0))
		var roll := _rng.randf()
		var d: Vector3i = CaveGraph.DIRS[axis]
		# A spider needs at least two straight cells in a row; it patrols their full length.
		var ahead := _graph.straight_axis(c + d) == axis
		var behind := _graph.straight_axis(c - d) == axis
		if (ahead or behind) and hops >= 4 and roll < 0.6 and counts["spider"] < limits["spider"]:
			var span := 3 if ahead and behind else 2
			var shift := 0 if span == 3 else (1 if ahead else -1)
			_add_feature(taken, counts, {"cell": c, "kind": "spider", "axis": axis,
				"span": span, "shift": shift})
		elif hops >= 4 and roll < 0.68 and counts["piston"] < limits["piston"]:
			_add_feature(taken, counts, {"cell": c, "kind": "piston", "phase": _rng.randi_range(0, 3)})
		elif hops >= 3 and roll < 0.55 and counts["wind"] < limits["wind"]:
			_add_feature(taken, counts, {"cell": c, "kind": "wind", "axis": axis,
				"sign": 1 if _rng.randf() < 0.5 else -1})
		elif hops >= 2 and roll < 0.8 and counts["pad"] < limits["pad"]:
			_add_feature(taken, counts, {"cell": c, "kind": "pad", "axis": axis})

	# Shaft features. A crumbling cover never sits on the guaranteed route, so the spine
	# can never be slowed by one.
	var crumbles := 0
	var shortcuts := 0
	for c: Vector3i in _graph.sorted_cells():
		if not _graph.is_linked(c, CaveGraph.DIR_UP):
			continue
		var above: Vector3i = c + CaveGraph.DIRS[CaveGraph.DIR_UP]
		var on_spine := spine_edges.has(_edge_key(c, above))
		if not on_spine and crumbles < 3 and above != _graph.spawn_cell \
				and above != _graph.finish_cell and _rng.randf() < 0.4:
			_graph.features.append({"cell": above, "kind": "crumble"})
			crumbles += 1
		var detour := _detour_length(c, above) if shortcuts < 3 else 0
		# 999 means the shaft is the only way through: required, not a shortcut.
		if detour >= 5 and detour < 999:
			_graph.features.append({"cell": c, "kind": "shortcut"})
			shortcuts += 1

	# Wall detail: cracks and mineral streaks, one roll per cell, on the rock that exists.
	for c: Vector3i in _graph.sorted_cells():
		if _rng.randf() < 0.45:
			_graph.decor.append({"cell": c, "kind": "walldetail", "variant": _rng.randi_range(0, 11)})

	var landmarks := 0
	for c: Vector3i in _graph.sorted_cells():
		if taken.has(c) or landmarks >= 3 or _graph.degree(c) < 3:
			continue
		if _graph.has_vertical_link(c) or _rng.randf() > 0.35:
			continue
		_graph.features.append({"cell": c, "kind": "landmark", "variant": landmarks})
		taken[c] = true
		landmarks += 1


func _add_feature(taken: Dictionary, counts: Dictionary, f: Dictionary) -> void:
	_graph.features.append(f)
	taken[f["cell"]] = true
	counts[f["kind"]] = int(counts[f["kind"]]) + 1


func _edge_key(a: Vector3i, b: Vector3i) -> String:
	var lo := a if (a.y < b.y or (a.y == b.y and (a.x < b.x or (a.x == b.x and a.z < b.z)))) else b
	var hi := b if lo == a else a
	return "%s|%s" % [lo, hi]


## Hops from a to b if their direct link did not exist. A long detour means the link is a
## real shortcut, worth marking for anyone willing to spend a Move on it.
func _detour_length(a: Vector3i, b: Vector3i) -> int:
	var dist := {a: 0}
	var queue: Array[Vector3i] = [a]
	while not queue.is_empty():
		var cur: Vector3i = queue.pop_front()
		for n: Vector3i in _graph.linked_neighbours(cur):
			if (cur == a and n == b) or (cur == b and n == a) or dist.has(n):
				continue
			dist[n] = int(dist[cur]) + 1
			if n == b:
				return dist[n]
			queue.append(n)
	return 999


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


## The guaranteed route, corridor-first. Legs of long straight runs joined by narrow turns,
## separated by vertical steps that go BOTH ways: the cave is a layered network, never a
## staircase to the exit. The vertical plan is chosen up front so its Move cost -- every
## time gravity has to flip, up or back down -- is known before a cell is carved.
func _carve_spine() -> bool:
	var start_y := clampi(size.y / 2, 0, size.y - 1)
	var current := Vector3i(_rng.randi_range(1, size.x - 2), start_y, _rng.randi_range(1, size.z - 2))
	_graph.spawn_cell = current
	_graph.add_cell(current)
	_graph.spine.append(current)

	var plan := _vertical_plan(start_y)
	if plan.is_empty():
		last_failure = "no vertical plan fits the lattice"
		return false

	var heading: int = CaveGraph.FLAT_DIRS[_rng.randi_range(0, 3)]
	for leg in plan.size() + 1:
		for r in _rng.randi_range(runs_per_leg_min, runs_per_leg_max):
			heading = _choose_heading(current, heading, r > 0)
			if heading == -1:
				last_failure = "spine boxed in"
				return false
			var length := _rng.randi_range(run_min, run_max)
			var carved := 0
			for step in length:
				var next: Vector3i = current + CaveGraph.DIRS[heading]
				if not _in_bounds(next) or _graph.has_cell(next):
					break
				_graph.link(current, next)
				current = next
				_graph.spine.append(current)
				carved += 1
			if carved == 0 and r == 0:
				last_failure = "spine could not start a run"
				return false
		if leg < plan.size():
			var dir_index := CaveGraph.DIR_UP if plan[leg] > 0 else CaveGraph.DIR_DOWN
			var next: Vector3i = current + CaveGraph.DIRS[dir_index]
			if not _in_bounds(next) or _graph.has_cell(next):
				last_failure = "spine vertical step blocked"
				return false
			_graph.link(current, next)
			current = next
			_graph.spine.append(current)

	_graph.finish_cell = current
	return true


## +1 climb / -1 descend for each vertical step of the route. Keeps inside the lattice,
## always contains both directions, and costs at most max_spine_climbs Moves.
func _vertical_plan(start_y: int) -> Array[int]:
	for tries in 30:
		var n := _rng.randi_range(vertical_steps_min, vertical_steps_max)
		var plan: Array[int] = []
		var y := start_y
		for i in n:
			var options: Array[int] = []
			if y + 1 < size.y:
				options.append(1)
			if y - 1 >= 0:
				options.append(-1)
			if options.is_empty():
				break
			var step: int = options[_rng.randi_range(0, options.size() - 1)]
			plan.append(step)
			y += step
		if plan.size() != n or not plan.has(1) or not plan.has(-1):
			continue
		if CaveGraph.move_cost_of_steps(plan) <= max_spine_climbs:
			return plan
	var empty: Array[int] = []
	return empty


## Keep going straight when allowed and there is room; otherwise turn toward the side with
## the longest free run. Never doubles straight back.
func _choose_heading(from: Vector3i, current: int, must_turn: bool) -> int:
	var candidates: Array[int] = []
	for dir_index: int in CaveGraph.FLAT_DIRS:
		if current >= 0 and dir_index == CaveGraph.opposite(current):
			continue
		if must_turn and dir_index == current:
			continue
		candidates.append(dir_index)
	# Shuffle deterministically so ties do not always favour +X.
	for i in range(candidates.size() - 1, 0, -1):
		var k := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[k]
		candidates[k] = tmp
	var best := -1
	var best_room := 0
	for dir_index: int in candidates:
		var room := _free_run(from, dir_index)
		if room > best_room:
			best_room = room
			best = dir_index
	return best


func _free_run(from: Vector3i, dir_index: int) -> int:
	var n := 0
	var cur := from
	while n < run_max:
		cur += CaveGraph.DIRS[dir_index]
		if not _in_bounds(cur) or _graph.has_cell(cur):
			break
		n += 1
	return n


## Dead-end side tunnels. Branches stay horizontal: a branch that dropped a level would be a
## pit whose only way out is a Move, which strands a racer who has none. They leave from
## corridor cells, not junctions, so side passages stay narrow instead of piling into rooms.
func _add_branches() -> void:
	var made := 0
	for attempt in branch_count * 6:
		if made >= branch_count:
			break
		var cells := _graph.sorted_cells()
		var origin: Vector3i = cells[_rng.randi_range(0, cells.size() - 1)]
		if _graph.degree(origin) > 2 or origin == _graph.finish_cell:
			continue
		var heading := _choose_heading(origin, -9, false)
		if heading == -1 or _free_run(origin, heading) < branch_len_min:
			continue
		var length := _rng.randi_range(branch_len_min, branch_len_max)
		var current := origin
		var carved := 0
		for step in length:
			if step == length / 2 + 1 and _rng.randf() < 0.3:
				var turn := _choose_heading(current, heading, true)
				if turn != -1:
					heading = turn
			var next: Vector3i = current + CaveGraph.DIRS[heading]
			if not _in_bounds(next) or _graph.has_cell(next):
				break
			_graph.link(current, next)
			current = next
			carved += 1
		if carved >= branch_len_min:
			made += 1


## Real cycles. A new tunnel is carved through empty rock from one cell until it meets a
## DIFFERENT part of the cave that was at least loop_min_detour hops away. Never a self-edge,
## never a shortcut between neighbours: taking the loop is a genuine trip that comes back
## somewhere recognisable. Some loops change level, joining upper and lower routes.
func _add_loops() -> void:
	var made := 0
	for attempt in loop_count * 15:
		if made >= loop_count:
			break
		var cells := _graph.sorted_cells()
		var origin: Vector3i = cells[_rng.randi_range(0, cells.size() - 1)]
		if _graph.degree(origin) > 2:
			continue
		var heading := _choose_heading(origin, -9, false)
		if heading == -1:
			continue
		var hops := _graph.distances_from(origin)
		var path: Array[Vector3i] = [origin]
		var visited := {origin: true}
		var closed := false
		for step in loop_len_max:
			var current: Vector3i = path[-1]
			var dir_index := heading
			if step > 0 and _rng.randf() < loop_vertical_chance:
				dir_index = CaveGraph.DIR_UP if _rng.randf() < 0.5 else CaveGraph.DIR_DOWN
			elif step > 2 and _rng.randf() < 0.18:
				var turn := _choose_heading(current, heading, true)
				if turn != -1:
					heading = turn
					dir_index = turn
			var next: Vector3i = current + CaveGraph.DIRS[dir_index]
			if not _in_bounds(next) or visited.has(next):
				continue
			if _graph.has_cell(next):
				if path.size() >= 3 and int(hops.get(next, 0)) >= loop_min_detour:
					path.append(next)
					closed = true
				break
			path.append(next)
			visited[next] = true
		if not closed:
			continue
		for k in range(1, path.size()):
			_graph.link(path[k - 1], path[k])
		made += 1


func _validate() -> bool:
	var spine_cost := _graph.spine_move_cost()
	if spine_cost > max_spine_climbs:
		last_failure = "the guaranteed route needs %d Moves, budget is %d" % [spine_cost, max_spine_climbs]
		return false

	if _graph.dead_end_count() < 2:
		last_failure = "fewer than two dead ends"
		return false
	if _graph.cycle_count() < mini(loop_count, 2):
		last_failure = "only %d real loops" % _graph.cycle_count()
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

	var problem := CaveValidator.structural_problem(_graph, size)
	if problem != "":
		last_failure = problem
		return false

	# Gravity-aware solvability: search (cell, gravity, Moves left) from spawn with the
	# starting charges and no loot. Connectivity alone would pass a cave whose exit sits
	# at the top of a shaft nobody can pay to climb.
	last_min_moves = CaveValidator.min_moves_to_finish(_graph, AppConfig.MOVE_CHARGES_START)
	if last_min_moves == CaveValidator.UNREACHABLE:
		last_failure = "exit unreachable within %d Moves under gravity rules" % AppConfig.MOVE_CHARGES_START
		return false

	return true


func _in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.x < size.x \
		and c.y >= 0 and c.y < size.y \
		and c.z >= 0 and c.z < size.z
