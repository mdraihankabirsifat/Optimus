class_name BotPlanner
extends RefCounted
## Decides where a bot goes next, using ONLY what that bot has personally discovered.
##
## THIS FILE MUST NEVER RECEIVE THE REAL CaveGraph. Everything it reads comes from a
## BotKnowledge instance. If the bot has not seen the exit, nothing here can find it --
## that is the property that makes the race fair, and it is worth protecting over any
## amount of cleverness.
##
## Search runs over states of (cell, gravity orientation) rather than cells alone, because
## whether an edge is walkable depends on which way the bot is currently falling. Gravity
## is restricted to down/up: the cave's vertical structure is Y-axis only, so a 180
## inversion is always the right tool and pathing for 90 degree wall-walks would cost far
## more than it buys. Documented as a deliberate simplification in docs/MVP_SCOPE.md.

const STEP_COST := 1.0
## A charge is precious. Weighted so the planner takes a long way round rather than
## spending a Move it does not need.
const INVERSION_COST := 12.0
## Nudges the bot toward fresh ground instead of pacing a corridor it already knows.
const REVISIT_PENALTY := 2.5
## A cell the bot has seen fire, a piston or a spider in. Worth a few steps of detour.
const HAZARD_COST := 5.0
## Charges held back while still exploring. Climbing a shaft on your last Move strands you
## up there with no way down, which is the single biggest cause of a bot never finishing.
## Once the exit is actually in sight the reserve is released and the bot commits.
const EXPLORE_RESERVE := 0

const GRAV_DOWN := 0
const GRAV_UP := 1

## Per-bot preference noise. Without it every bot shares one planner and one set of
## observations, so four bots walk the same route and finish within a fraction of a second
## of each other -- which reads as a bug rather than a race. The jitter is derived from the
## cell and the bot's own seed, so a given bot's taste in corridors is stable rather than
## dithering between frames.
var personality: int = 0
var frontier_jitter: float = 0.0


## Returns the cells to walk through, starting with the one after `from`.
## Empty means there is nowhere useful left to go.
## `charges` gates inversions: at zero the search simply cannot flip gravity, so the bot
## plans a route it can actually walk instead of one it cannot pay for.
func plan(knowledge: BotKnowledge, from: Vector3i, gravity_is_up: bool,
		charges: int = 99) -> Array[Vector3i]:
	var start_g: int = GRAV_UP if gravity_is_up else GRAV_DOWN
	# Spend freely once the exit is known; hold something back while still searching.
	var spendable: int = charges if knowledge.exit_found \
		else maxi(0, charges - EXPLORE_RESERVE)
	var result := _dijkstra(knowledge, from, start_g, spendable)
	var dist: Dictionary = result["dist"]
	var prev: Dictionary = result["prev"]

	var goal_key := ""
	if knowledge.exit_found:
		goal_key = _best_key_for_cell(dist, knowledge.exit_cell)
	else:
		goal_key = _nearest_frontier_key(knowledge, dist, prev)

	if goal_key == "":
		# Nothing new is reachable and the exit is unknown -- usually out of charges with
		# every remaining frontier on the far side of a shaft. Keep searching known ground
		# rather than standing still: a frozen racer looks broken, and a Move refill from a
		# mystery box can reopen the map at any moment.
		goal_key = _least_visited_key(knowledge, dist)
	if goal_key == "":
		return []
	return _reconstruct(prev, goal_key, from)


## Dijkstra over (cell, gravity) states. Expansion is limited to cells the bot has actually
## observed -- it cannot route through territory it has never seen.
func _dijkstra(knowledge: BotKnowledge, from: Vector3i, start_g: int,
		charges: int) -> Dictionary:
	var start_key := _key(from, start_g)
	var dist := {start_key: 0.0}
	var prev := {}
	var cell_of := {start_key: from}
	var grav_of := {start_key: start_g}
	var open := {start_key: true}

	while not open.is_empty():
		var current := ""
		var best := INF
		for key: String in open:
			var d: float = dist[key]
			if d < best:
				best = d
				current = key
		open.erase(current)

		var cell: Vector3i = cell_of[current]
		var grav: int = grav_of[current]

		# Option 1: invert gravity in place. Costs a Move, and is simply unavailable
		# when the bot has none left -- the same rule a human plays under.
		if charges > 0:
			_relax_inversion(cell, grav, best, dist, prev, cell_of, grav_of, open)
		# Option 2: travel to a linked neighbour the bot has already seen.
		for dir_index in 6:
			if not knowledge.discovered.is_linked(cell, dir_index):
				continue
			var neighbour: Vector3i = cell + CaveGraph.DIRS[dir_index]
			if not knowledge.has_seen(neighbour):
				continue
			if not _can_traverse(dir_index, grav):
				continue

			var step: float = STEP_COST \
				+ REVISIT_PENALTY * float(knowledge.visit_count(neighbour)) \
				+ (HAZARD_COST if knowledge.is_hazard(neighbour) else 0.0)
			var next_key := _key(neighbour, grav)
			var next_cost: float = best + step
			if next_cost < float(dist.get(next_key, INF)):
				dist[next_key] = next_cost
				prev[next_key] = current
				cell_of[next_key] = neighbour
				grav_of[next_key] = grav
				open[next_key] = true

	return {"dist": dist, "prev": prev, "cell_of": cell_of}


func _relax_inversion(cell: Vector3i, grav: int, best: float, dist: Dictionary,
		prev: Dictionary, cell_of: Dictionary, grav_of: Dictionary,
		open: Dictionary) -> void:
	var flipped := GRAV_DOWN if grav == GRAV_UP else GRAV_UP
	var flip_key := _key(cell, flipped)
	var flip_cost: float = best + INVERSION_COST
	if flip_cost >= float(dist.get(flip_key, INF)):
		return
	dist[flip_key] = flip_cost
	prev[flip_key] = _key(cell, grav)
	cell_of[flip_key] = cell
	grav_of[flip_key] = flipped
	open[flip_key] = true


## Walking sideways is always fine, and so is falling. Moving against your own gravity is
## not -- that is what an inversion is for.
func _can_traverse(dir_index: int, grav: int) -> bool:
	if dir_index == CaveGraph.DIR_UP:
		return grav == GRAV_UP      # "up" is downhill when you are falling upward
	if dir_index == CaveGraph.DIR_DOWN:
		return grav == GRAV_DOWN
	return true


## The closest cell the bot knows exists but has never entered.
func _nearest_frontier_key(knowledge: BotKnowledge, dist: Dictionary,
		prev: Dictionary) -> String:
	var best_key := ""
	var best_cost := INF

	for frontier: Vector3i in knowledge.frontiers():
		for dir_index in 6:
			var neighbour: Vector3i = frontier + CaveGraph.DIRS[dir_index]
			if not knowledge.has_seen(neighbour):
				continue
			var back := CaveGraph.opposite(dir_index)
			if not knowledge.discovered.is_linked(neighbour, back):
				continue

			for grav in [GRAV_DOWN, GRAV_UP]:
				var key := _key(neighbour, grav)
				if not dist.has(key):
					continue
				if not _can_traverse(back, grav):
					continue
				var cost: float = float(dist[key]) + STEP_COST + _taste(frontier)
				if cost < best_cost:
					best_cost = cost
					best_key = _key(frontier, grav)
					# The frontier is one step past a known cell; stitch it on.
					prev[best_key] = key

	return best_key


## Somewhere known that the bot has seen least often. Keeps a stranded bot moving.
func _least_visited_key(knowledge: BotKnowledge, dist: Dictionary) -> String:
	var best_key := ""
	var fewest := 1 << 30
	var best_cost := INF
	for cell: Vector3i in knowledge.discovered.cells:
		for grav in [GRAV_DOWN, GRAV_UP]:
			var key := _key(cell, grav)
			if not dist.has(key) or float(dist[key]) <= 0.0:
				continue
			var seen := knowledge.visit_count(cell)
			var cost: float = float(dist[key])
			if seen < fewest or (seen == fewest and cost < best_cost):
				fewest = seen
				best_cost = cost
				best_key = key
	return best_key


## A stable, bot-specific preference for one corridor over another.
func _taste(cell: Vector3i) -> float:
	if frontier_jitter <= 0.0:
		return 0.0
	var h: int = abs(hash(Vector4i(cell.x, cell.y, cell.z, personality)))
	return float(h % 1000) / 1000.0 * frontier_jitter


func _best_key_for_cell(dist: Dictionary, cell: Vector3i) -> String:
	var best_key := ""
	var best := INF
	for grav in [GRAV_DOWN, GRAV_UP]:
		var key := _key(cell, grav)
		if dist.has(key) and float(dist[key]) < best:
			best = float(dist[key])
			best_key = key
	return best_key


## Walks the predecessor chain back to the start, dropping repeated cells so the caller
## gets a clean list of places to walk rather than a list of state changes.
func _reconstruct(prev: Dictionary, goal_key: String, from: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var key := goal_key
	var guard := 0
	while key != "" and guard < 4096:
		guard += 1
		cells.append(_cell_from_key(key))
		if not prev.has(key):
			break
		key = prev[key]

	cells.reverse()

	var path: Array[Vector3i] = []
	for cell: Vector3i in cells:
		if cell == from and path.is_empty():
			continue
		if not path.is_empty() and path[-1] == cell:
			continue
		path.append(cell)
	return path


func _key(cell: Vector3i, grav: int) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, cell.z, grav]


func _cell_from_key(key: String) -> Vector3i:
	var parts := key.split(",")
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
