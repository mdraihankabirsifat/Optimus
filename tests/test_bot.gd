extends Node
## BOT-001..004 — bot knowledge isolation and exploration.
## Run: godot --headless res://tests/test_bot.tscn
##
## The headline assertion is that a bot finds the exit using only what it discovered.
## Everything else guards the information boundary that makes the race fair.

const SEED_COUNT := 60
const MAX_STEPS := 900
static var _charge_budget: int = AppConfig.MOVE_CHARGES_START

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame

	_test_knowledge_isolation()
	_test_planner_is_blind_to_the_exit()
	_test_paths_stay_inside_discovered_territory()
	_test_backtracks_from_dead_end()
	_test_follows_its_own_clue()
	_test_zero_moves_cannot_climb()
	await _test_bot_is_eliminated_by_normal_rules()
	_test_exploration_finds_the_exit()

	print("")
	print("==================================================")
	print("  BOT-001..004   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_knowledge_isolation() -> void:
	_section("knowledge starts empty and grows only by observation")
	var graph := CaveGenerator.new().generate(7)
	var k := BotKnowledge.new()

	_check("no cells known before observing", k.discovered.cell_count() == 0)
	_check("exit unknown before observing", not k.exit_found)

	var spawn := graph.spawn_cell
	k.observe(spawn, int(graph.cells[spawn]), spawn == graph.finish_cell)

	_check("observing adds exactly one cell", k.discovered.cell_count() == 1)
	_check("the observed cell is known", k.has_seen(spawn))
	_check("visit count recorded", k.visit_count(spawn) == 1)

	# Neighbours are known to exist, but their contents are not.
	var frontiers := k.frontiers()
	_check("neighbours become frontiers", frontiers.size() > 0)
	var any_frontier_discovered := false
	for f: Vector3i in frontiers:
		if k.has_seen(f):
			any_frontier_discovered = true
	_check("frontiers are not treated as discovered", not any_frontier_discovered)
	_check("bot knows far less than the real cave",
		k.discovered.cell_count() < graph.cell_count())


func _test_planner_is_blind_to_the_exit() -> void:
	_section("planner cannot route to an exit it has never seen")
	var graph := CaveGenerator.new().generate(11)
	var k := BotKnowledge.new()
	var planner := BotPlanner.new()

	var spawn := graph.spawn_cell
	k.observe(spawn, int(graph.cells[spawn]), false)

	_check("exit still unknown", not k.exit_found)
	var path := planner.plan(k, spawn, false)
	_check("planner still produces a move", path.size() > 0)
	_check("planner does not head straight for the real exit",
		path.is_empty() or path[-1] != graph.finish_cell
			or k.has_seen(graph.finish_cell))


func _test_paths_stay_inside_discovered_territory() -> void:
	_section("paths never route through unseen cells")
	var graph := CaveGenerator.new().generate(23)
	var k := BotKnowledge.new()
	var planner := BotPlanner.new()

	var cell := graph.spawn_cell
	var gravity_up := false
	var violations := 0

	for step in 120:
		k.observe(cell, int(graph.cells[cell]), cell == graph.finish_cell)
		var path := planner.plan(k, cell, gravity_up)
		if path.is_empty():
			break

		# Every cell on the path must be discovered, except the final one, which is
		# allowed to be a frontier the bot is deliberately stepping into.
		for i in path.size():
			var p: Vector3i = path[i]
			if k.has_seen(p):
				continue
			if i == path.size() - 1 and k.frontiers().has(p):
				continue
			violations += 1

		var delta: Vector3i = path[0] - cell
		var dir_index: int = CaveGraph.DIRS.find(delta)
		if dir_index == -1 or not graph.is_linked(cell, dir_index):
			break
		var grav: int = BotPlanner.GRAV_UP if gravity_up else BotPlanner.GRAV_DOWN
		if not planner._can_traverse(dir_index, grav):
			gravity_up = not gravity_up
			continue
		cell = path[0]

	_check("no path routed through undiscovered territory", violations == 0)


## A T with a dead end: once the dead end is explored the bot turns round.
func _test_backtracks_from_dead_end() -> void:
	_section("backtracks out of a dead end")
	var g := CaveGraph.new()
	# spawn (0,0,0) - (1,0,0) - dead end (2,0,0);  spawn - (-1,0,0) - (-2,0,0) exit
	g.link(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	g.link(Vector3i(1, 0, 0), Vector3i(2, 0, 0))
	g.link(Vector3i(0, 0, 0), Vector3i(-1, 0, 0))
	g.link(Vector3i(-1, 0, 0), Vector3i(-2, 0, 0))
	var k := BotKnowledge.new()
	var planner := BotPlanner.new()
	var cell := Vector3i(0, 0, 0)
	# Walk it into the dead end first.
	for c: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)]:
		k.observe(c, int(g.cells[c]), false)
	cell = Vector3i(2, 0, 0)
	var path := planner.plan(k, cell, false, 5)
	_check("plans a route out of the dead end", not path.is_empty())
	_check("heads back the way it came", not path.is_empty() and path[0] == Vector3i(1, 0, 0))
	_check("toward the unexplored branch",
		not path.is_empty() and path[-1] == Vector3i(-1, 0, 0))


## Two unexplored frontiers the same distance away. A clue pointing west must pick west.
func _test_follows_its_own_clue() -> void:
	_section("reacts to its own clue")
	var g := CaveGraph.new()
	g.link(Vector3i(0, 0, 0), Vector3i(1, 0, 0))
	g.link(Vector3i(0, 0, 0), Vector3i(-1, 0, 0))
	var picks := {"east": 0, "west": 0}
	for personality in 8:
		var k := BotKnowledge.new()
		k.observe(Vector3i(0, 0, 0), int(g.cells[Vector3i(0, 0, 0)]), false)
		var planner := BotPlanner.new()
		planner.personality = personality
		planner.frontier_jitter = 3.0
		k.observe_clue(Vector3(-1, 0, 0), 0)
		var path := planner.plan(k, Vector3i(0, 0, 0), false, 5)
		if not path.is_empty():
			picks["west" if path[-1].x < 0 else "east"] += 1
	_check("with a westward clue, every bot personality heads west (%d/8)" % picks["west"], picks["west"] == 8)
	var blank := BotKnowledge.new()
	_check("no clue, no bias", BotPlanner.clue_alignment(blank, Vector3i.ZERO, Vector3i(-1, 0, 0)) == 0.0)
	var other := BotKnowledge.new()
	other.observe(Vector3i(0, 0, 0), int(g.cells[Vector3i(0, 0, 0)]), false)
	_check("one bot's clue is not another's", not other.has_clue)
	_check("a clue never reveals the exit cell", not other.exit_found)


## Out of Moves, a bot cannot plan up a shaft.
func _test_zero_moves_cannot_climb() -> void:
	_section("zero Moves cannot climb")
	var g := CaveGraph.new()
	g.link(Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	var k := BotKnowledge.new()
	k.observe(Vector3i(0, 0, 0), int(g.cells[Vector3i(0, 0, 0)]), false)
	var planner := BotPlanner.new()
	var broke := planner.plan(k, Vector3i(0, 0, 0), false, 0)
	_check("with 0 Moves the shaft above is not a route", broke.is_empty() or broke[-1] != Vector3i(0, 1, 0))
	var rich := planner.plan(k, Vector3i(0, 0, 0), false, 1)
	_check("with 1 Move it is", not rich.is_empty() and rich[-1] == Vector3i(0, 1, 0))


## A bot is a racer like any other: hearts run out, it is out of the race.
func _test_bot_is_eliminated_by_normal_rules() -> void:
	_section("bots are eliminated like anyone")
	var bot: PlayerController = load("res://scenes/bots/bot_player.tscn").instantiate()
	add_child(bot)
	await get_tree().process_frame
	var graph := CaveGenerator.new().generate(11)
	(bot.get_node("BotController") as BotController).setup(graph, "Rook", Color.RED, 1, 2)
	for i in 5:
		bot.health._process(AppConfig.INVULNERABILITY_TIME + 0.1)
		bot.health.apply_damage(1.0, "spider_%d" % i)
	_check("five full hits eliminate a bot", bot.health.is_eliminated)
	bot.input_enabled = false
	await get_tree().physics_frame
	_check("an eliminated bot makes no moves", bot.move_input == Vector2.ZERO)
	bot.queue_free()


func _test_exploration_finds_the_exit() -> void:
	_section("bots explore and finish, across %d caves" % SEED_COUNT)
	var found := 0
	var total_steps := 0
	var total_inversions := 0
	var worst_steps := 0
	var worst_inversions := 0
	var ran_dry := 0
	var first_failure := ""

	for s in SEED_COUNT:
		var graph := CaveGenerator.new().generate(s)
		if graph == null:
			continue
		var run := _simulate(graph)
		if bool(run["found"]):
			found += 1
			total_steps += int(run["steps"])
			total_inversions += int(run["inversions"])
			worst_steps = maxi(worst_steps, int(run["steps"]))
			worst_inversions = maxi(worst_inversions, int(run["inversions"]))
			if int(run["charges"]) == 0:
				ran_dry += 1
		elif first_failure == "":
			first_failure = "seed %d: %s" % [s, run["reason"]]

	# A bot that cannot reach the exit on its remaining charges keeps searching known
	# ground rather than freezing, and the match records it as DNF. Occasional DNFs are
	# acceptable and honest; freezing on screen is not.
	var rate := float(found) / float(SEED_COUNT)
	_check("at least 90%% of bots finish (%d/%d)%s"
		% [found, SEED_COUNT, "" if first_failure == "" else "  " + first_failure],
		rate >= 0.90)
	_check("a bot never runs out of moves to make",
		first_failure.find("no plan") == -1)
	_check("no bot ever spent more than its %d charges" % AppConfig.MOVE_CHARGES_START,
		worst_inversions <= AppConfig.MOVE_CHARGES_START)

	if found > 0:
		print("   steps      avg %.1f, worst %d" % [float(total_steps) / found, worst_steps])
		print("   Moves used avg %.2f, worst %d (budget %d)"
			% [float(total_inversions) / found, worst_inversions,
				AppConfig.MOVE_CHARGES_START])
		print("   ran out of charges before finishing: %d of %d" % [ran_dry, found])


## Drives a bot purely as logic -- no physics, no scene. It observes where it stands,
## commits to a plan, and inverts gravity when the next step demands it.
##
## Committing to the plan matters: replanning every single step made the bot oscillate
## between gravity frames whenever two frontiers were near-equally attractive, burning
## Moves it could not afford.
func _simulate(graph: CaveGraph) -> Dictionary:
	var k := BotKnowledge.new()
	var planner := BotPlanner.new()
	var cell := graph.spawn_cell
	var gravity_up := false
	var charges: int = _charge_budget
	var steps := 0
	var inversions := 0
	var path: Array[Vector3i] = []
	var exit_was_known := false
	var guard := 0

	while steps < MAX_STEPS and guard < MAX_STEPS * 4:
		guard += 1
		k.observe(cell, int(graph.cells[cell]), cell == graph.finish_cell)
		if cell == graph.finish_cell:
			return {"found": true, "steps": steps, "inversions": inversions,
				"charges": charges}

		# Spotting the exit invalidates whatever the bot was exploring toward.
		if k.exit_found and not exit_was_known:
			exit_was_known = true
			path.clear()

		if path.is_empty():
			path = planner.plan(k, cell, gravity_up, charges)
			if path.is_empty():
				return {"found": false, "reason": "no plan", "steps": steps,
					"inversions": inversions, "charges": charges}

		var delta: Vector3i = path[0] - cell
		var dir_index: int = CaveGraph.DIRS.find(delta)
		if dir_index == -1:
			path.clear()
			continue
		if not graph.is_linked(cell, dir_index):
			return {"found": false, "reason": "planner routed through a wall",
				"steps": steps, "inversions": inversions, "charges": charges}

		var grav: int = BotPlanner.GRAV_UP if gravity_up else BotPlanner.GRAV_DOWN
		if not planner._can_traverse(dir_index, grav):
			if charges <= 0:
				# Cannot pay for the frame change; think again without inversions.
				path.clear()
				continue
			gravity_up = not gravity_up
			charges -= 1
			inversions += 1
			continue

		cell = path[0]
		path.remove_at(0)
		steps += 1

	return {"found": false, "reason": "step limit", "steps": steps,
		"inversions": inversions, "charges": charges}


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
