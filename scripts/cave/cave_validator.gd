class_name CaveValidator
extends RefCounted
## Gravity-aware solvability. Pure data, no nodes, no randomness.
##
## Plain connectivity is not enough in this game: an edge that is walkable under one
## gravity is a wall under another. This searches the state graph
##     (cell, gravity direction, Moves remaining)
## from the spawn with the starting charges and no mystery-box loot, and reports the
## fewest Moves any racer needs to reach the exit.
##
## Minimising Moves spent per (cell, gravity) is equivalent to searching the full
## three-part state, because having more Moves left never removes an option. That keeps
## the search to 6 x cells states and makes it cheap enough to run inside the generator.
##
## Transition rules, matching what the player controller physically allows:
##   fall   - if the cell is open in the gravity direction, the racer drops into the next
##            cell. Free, and forced: no walking while falling.
##   walk   - standing on a surface (the cell is closed in the gravity direction), the racer
##            may walk into any linked neighbour perpendicular to gravity. Free.
##   climb  - moving against gravity is impossible: a jump reaches about 1.3 units and a
##            cell is 8. That is what a Move is for.
##   shift  - any of the five other cardinal gravities, standing or falling. Costs 1 Move:
##            four are the 90-degree G+WASD turns, one is the 180-degree G+Space inversion.
##
## The cave is sealed, so there is no vacuum to fall into here; the protected vacuum-180
## rule is a runtime safety net, not something the level needs to route around.

const UNREACHABLE := -1


## Fewest Moves needed to reach the finish from spawn under `start_gravity`, or
## UNREACHABLE if it cannot be done within `budget`.
static func min_moves_to_finish(graph: CaveGraph, budget: int = AppConfig.MOVE_CHARGES_START,
		start_gravity: int = CaveGraph.DIR_DOWN) -> int:
	var costs := solve(graph, graph.spawn_cell, start_gravity, budget)
	var best := UNREACHABLE
	for g in 6:
		var key := _key(graph.finish_cell, g)
		if costs.has(key):
			var c: int = costs[key]
			if best == UNREACHABLE or c < best:
				best = c
	return best


## 0-1 breadth-first search. Returns {state key: fewest Moves spent} for every state
## reachable within `budget` Moves.
static func solve(graph: CaveGraph, from: Vector3i, start_gravity: int, budget: int) -> Dictionary:
	var costs := {}
	if not graph.has_cell(from):
		return costs
	# Deque as two arrays: zero-cost transitions go to the front, Moves to the back.
	var front: Array = [[from, start_gravity, 0]]
	var back: Array = []
	costs[_key(from, start_gravity)] = 0

	while not front.is_empty() or not back.is_empty():
		if front.is_empty():
			front = back
			back = []
			front.reverse()
		var state: Array = front.pop_back()
		var cell: Vector3i = state[0]
		var g: int = state[1]
		var spent: int = state[2]
		if int(costs.get(_key(cell, g), 1 << 30)) < spent:
			continue

		if graph.is_linked(cell, g):
			# Falling. Nothing to stand on, so the only free transition is the drop.
			_relax(costs, front, cell + CaveGraph.DIRS[g], g, spent)
		else:
			var against := CaveGraph.opposite(g)
			for d in 6:
				if d == g or d == against or not graph.is_linked(cell, d):
					continue
				_relax(costs, front, cell + CaveGraph.DIRS[d], g, spent)

		if spent < budget:
			for g2 in 6:
				if g2 != g:
					_relax(costs, back, cell, g2, spent + 1)
	return costs


## Every (cell, gravity) a racer can occupy with no Moves at all from `from`. Used by tests
## to prove the spawn chamber is explorable on foot.
static func free_region(graph: CaveGraph, from: Vector3i, gravity: int = CaveGraph.DIR_DOWN) -> Dictionary:
	var cells := {}
	for key: String in solve(graph, from, gravity, 0):
		var parts := key.split(",")
		cells[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = true
	return cells


## Structural invariants the generator must never break. Returns "" when valid, otherwise
## a description of the first problem found.
static func structural_problem(graph: CaveGraph, bounds: Vector3i) -> String:
	for c: Vector3i in graph.sorted_cells():
		if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= bounds.x or c.y >= bounds.y or c.z >= bounds.z:
			return "cell %s lies outside the %s lattice" % [c, bounds]
		var mask := int(graph.cells[c])
		if mask < 0 or mask > 0b111111:
			return "cell %s has an invalid connection mask %d" % [c, mask]
		for d in 6:
			if not graph.is_linked(c, d):
				continue
			var n: Vector3i = c + CaveGraph.DIRS[d]
			if not graph.has_cell(n):
				return "cell %s links to missing cell %s" % [c, n]
			if not graph.is_linked(n, CaveGraph.opposite(d)):
				return "one-way link between %s and %s" % [c, n]
	if not graph.has_cell(graph.spawn_cell):
		return "spawn cell is not part of the cave"
	if not graph.has_cell(graph.finish_cell):
		return "finish cell is not part of the cave"

	var used := {}
	for h: Dictionary in graph.hazards:
		var key := "hazard@%s" % h["cell"]
		if used.has(h["cell"]):
			return "two placements share cell %s" % h["cell"]
		used[h["cell"]] = key
	for b: Dictionary in graph.boxes:
		if used.has(b["cell"]):
			return "a box overlaps another placement at %s" % b["cell"]
		used[b["cell"]] = "box"
	if used.has(graph.spawn_cell):
		return "a hazard or box sits in the spawn cell"
	if used.has(graph.finish_cell):
		return "a hazard or box sits in the finish cell"
	return ""


static func _relax(costs: Dictionary, queue: Array, cell: Vector3i, g: int, spent: int) -> void:
	var key := _key(cell, g)
	if int(costs.get(key, 1 << 30)) <= spent:
		return
	costs[key] = spent
	queue.push_back([cell, g, spent])


static func _key(cell: Vector3i, g: int) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, cell.z, g]
