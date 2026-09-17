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
## whether an edge is walkable depends on which way the bot is currently falling.
##
## BOT-011: with wall_walks_enabled the search covers all six gravities, so a bot can choose
## a 90-degree turn onto a wall -- walking up a shaft wall, or crossing an arch with one Move
## where two inversions would be needed. Every shift, 90 or 180, costs one Move, the same
## rule a human plays under. tests/test_wallwalk.gd shows the body can physically do it.

const STEP_COST := 1.0
## A charge is precious. Weighted so the planner takes a long way round rather than
## spending a Move it does not need.
const INVERSION_COST := 12.0
## Extra planning cost of a 180 over a 90. Measured in tests/bot_physical.gd over 40 bot
## races: at 0.5 bots chose walls 55 times but finished 70% (vs 98%) and spent 2.5x the
## Moves -- sideways gravity makes long corridors into falls. At 0 bots turn onto a wall only
## when it is strictly cheaper, such as crossing an arch on one Move instead of two.
const FLIP_EXTRA_COST := 0.0
## Nudges the bot toward fresh ground instead of pacing a corridor it already knows.
const REVISIT_PENALTY := 2.5
## A cell the bot has seen fire, a piston or a spider in. Worth a few steps of detour.
const HAZARD_COST := 5.0
## Charges held back while still exploring. Climbing a shaft on your last Move strands you
## up there with no way down, which is the single biggest cause of a bot never finishing.
## Once the exit is actually in sight the reserve is released and the bot commits.
const EXPLORE_RESERVE := 0

## With a clue in hand, a frontier straight along the hinted direction is worth this many
## steps of extra walking, and one on the hinted level a few more. A clue speeds the search
## up; it never overrides it, because the hint is coarse and the cave has walls.
const CLUE_WEIGHT := 6.0
const CLUE_LEVEL_WEIGHT := 3.0

const GRAV_DOWN := 0
const GRAV_UP := 1
const GRAV_PLUS_X := 2
const GRAV_MINUS_X := 3
const GRAV_PLUS_Z := 4
const GRAV_MINUS_Z := 5
## Planner gravity index -> CaveGraph direction index of that gravity.
const GRAV_TO_DIR: Array[int] = [CaveGraph.DIR_DOWN, CaveGraph.DIR_UP, CaveGraph.DIR_PLUS_X,
	CaveGraph.DIR_MINUS_X, CaveGraph.DIR_PLUS_Z, CaveGraph.DIR_MINUS_Z]

## Off: bots only ever invert (the pre-BOT-011 behaviour). On: all six gravities.
static var wall_walks_enabled: bool = true

## Filled by every plan: the gravity each returned cell must be entered under, as planner
## gravity indices. The controller shifts when the next step needs a different one.
var last_gravities: Array[int] = []

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
	return plan_from(knowledge, from, GRAV_UP if gravity_is_up else GRAV_DOWN, charges)


## As plan(), starting under any planner gravity.
func plan_from(knowledge: BotKnowledge, from: Vector3i, start_g: int,
		charges: int = 99) -> Array[Vector3i]:
	last_gravities.clear()
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
		goal_key = _nearest_frontier_key(knowledge, dist, prev, from)

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

		# Option 1: change gravity in place. Costs a Move, and is simply unavailable
		# when the bot has none left -- the same rule a human plays under.
		if charges > 0:
			for other: int in gravities():
				if other != grav:
					var extra := FLIP_EXTRA_COST if wall_walks_enabled and _is_flip(grav, other) else 0.0
					_relax_shift(cell, grav, other, best + extra, dist, prev, cell_of, grav_of, open)
		# Option 2: travel to a linked neighbour the bot has already seen.
		# Under a sideways gravity an open wall is not a choice: the racer falls through it.
		var fall_dir := GRAV_TO_DIR[grav]
		var falling := grav >= GRAV_PLUS_X and knowledge.discovered.is_linked(cell, fall_dir)
		for dir_index in 6:
			if not knowledge.discovered.is_linked(cell, dir_index):
				continue
			if falling and dir_index != fall_dir:
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


func _relax_shift(cell: Vector3i, grav: int, flipped: int, best: float, dist: Dictionary,
		prev: Dictionary, cell_of: Dictionary, grav_of: Dictionary,
		open: Dictionary) -> void:
	var flip_key := _key(cell, flipped)
	var flip_cost: float = best + INVERSION_COST
	if flip_cost >= float(dist.get(flip_key, INF)):
		return
	dist[flip_key] = flip_cost
	prev[flip_key] = _key(cell, grav)
	cell_of[flip_key] = cell
	grav_of[flip_key] = flipped
	open[flip_key] = true


static func _is_flip(a: int, b: int) -> bool:
	return GRAV_TO_DIR[a] == CaveGraph.opposite(GRAV_TO_DIR[b])


## Gravities the search may use.
static func gravities() -> Array[int]:
	if wall_walks_enabled:
		return [GRAV_DOWN, GRAV_UP, GRAV_PLUS_X, GRAV_MINUS_X, GRAV_PLUS_Z, GRAV_MINUS_Z]
	return [GRAV_DOWN, GRAV_UP]


## Planner gravity index for a world gravity vector.
static func grav_index(gravity_dir: Vector3) -> int:
	var snapped := GravityController.snap_to_cardinal(gravity_dir)
	for g in GRAV_TO_DIR.size():
		if Vector3(CaveGraph.DIRS[GRAV_TO_DIR[g]]).is_equal_approx(snapped):
			return g
	return GRAV_DOWN


## Walking across your own floor plane is always fine, and so is falling. Moving against your
## own gravity is not -- that is what a Move is for. For a sideways gravity, "across" includes
## straight up and down a wall.
func _can_traverse(dir_index: int, grav: int) -> bool:
	return dir_index != CaveGraph.opposite(GRAV_TO_DIR[grav])


## The closest cell the bot knows exists but has never entered.
func _nearest_frontier_key(knowledge: BotKnowledge, dist: Dictionary,
		prev: Dictionary, from: Vector3i = Vector3i.ZERO) -> String:
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

			for grav: int in gravities():
				var key := _key(neighbour, grav)
				if not dist.has(key):
					continue
				if not _can_traverse(back, grav):
					continue
				var cost: float = float(dist[key]) + STEP_COST + _taste(frontier) \
					- clue_alignment(knowledge, from, frontier)
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
		for grav: int in gravities():
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


## How much a frontier agrees with this bot's own clue, in step-equivalents. Zero without
## a clue. Uses only the clue's coarse direction and the bot's own position.
static func clue_alignment(knowledge: BotKnowledge, from: Vector3i, frontier: Vector3i) -> float:
	if not knowledge.has_clue:
		return 0.0
	var offset := Vector3(frontier - from)
	var flat := Vector3(offset.x, 0.0, offset.z)
	var along := 0.0
	if flat.length() > 0.01:
		along = flat.normalized().dot(knowledge.clue_direction)
	var level := 0.0
	if knowledge.clue_vertical != 0 and signi(frontier.y - from.y) == knowledge.clue_vertical:
		level = 1.0
	return CLUE_WEIGHT * along + CLUE_LEVEL_WEIGHT * level


## A stable, bot-specific preference for one corridor over another.
func _taste(cell: Vector3i) -> float:
	if frontier_jitter <= 0.0:
		return 0.0
	var h: int = abs(hash(Vector4i(cell.x, cell.y, cell.z, personality)))
	return float(h % 1000) / 1000.0 * frontier_jitter


func _best_key_for_cell(dist: Dictionary, cell: Vector3i) -> String:
	var best_key := ""
	var best := INF
	for grav: int in gravities():
		var key := _key(cell, grav)
		if dist.has(key) and float(dist[key]) < best:
			best = float(dist[key])
			best_key = key
	return best_key


## Walks the predecessor chain back to the start, dropping repeated cells so the caller
## gets a clean list of places to walk rather than a list of state changes.
func _reconstruct(prev: Dictionary, goal_key: String, from: Vector3i) -> Array[Vector3i]:
	var keys: Array[String] = []
	var key := goal_key
	var guard := 0
	while key != "" and guard < 4096:
		guard += 1
		keys.append(key)
		if not prev.has(key):
			break
		key = prev[key]

	keys.reverse()

	var path: Array[Vector3i] = []
	last_gravities.clear()
	for k: String in keys:
		var cell := _cell_from_key(k)
		if cell == from and path.is_empty():
			continue
		if not path.is_empty() and path[-1] == cell:
			continue
		path.append(cell)
		last_gravities.append(int(k.get_slice(",", 3)))
	return path


func _key(cell: Vector3i, grav: int) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, cell.z, grav]


func _cell_from_key(key: String) -> Vector3i:
	var parts := key.split(",")
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
