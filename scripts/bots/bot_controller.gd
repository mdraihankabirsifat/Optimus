class_name BotController
extends Node
## Drives a PlayerController from BotPlanner output.
##
## The bot moves by filling in the same move_input / jump_requested fields a human fills
## from the keyboard, so it runs through identical movement, acceleration and collision
## code. It cannot out-run a human, teleport, or pass through geometry, because it has no
## route to do so.
##
## This class holds the real CaveGraph, because something has to know where the bot
## physically is in order to answer "what can you see from here". It passes only that
## single cell's information into BotKnowledge. The planner never sees this reference --
## that separation is what keeps the race fair. See scripts/bots/bot_knowledge.gd.

## How often the bot reconsiders. A small delay keeps it from twitching every frame and
## reads as a moment of thought.
@export var think_interval: float = 0.25
## How close to a cell centre counts as "lined up" before dropping down a shaft.
const CENTRE_TOLERANCE := 1.2
const BOX_REACH := 3.2
const EASY_JUNCTION_PAUSE := 1.6

var knowledge := BotKnowledge.new()
var display_name: String = "Bot"
## 0 Easy: walks everywhere and hesitates. 1 Normal: sprints only on longer runs.
## 2 Hard: always sprints. Movement rules are identical at every level -- skill only
## changes choices a human could also make.
var skill: int = 2

var _planner := BotPlanner.new()
var _graph: CaveGraph
var _body: PlayerController
var _path: Array[Vector3i] = []
## Planner gravity each path cell must be entered under (BotPlanner.last_gravities).
var _path_gravs: Array[int] = []
var _think_timer: float = 0.0
var _exit_was_known: bool = false
var _hesitate: float = 0.0
## Where hazards physically are. Only ever consulted for the cell the bot is standing in,
## and only that single fact is passed into knowledge -- the same as seeing it.
var _hazard_cells: Dictionary = {}


func setup(graph: CaveGraph, bot_name: String, colour: Color, personality: int, p_skill: int = 2) -> void:
	skill = clampi(p_skill, 0, 2)
	for h: Dictionary in graph.hazards:
		_hazard_cells[h["cell"]] = true
	for f: Dictionary in graph.features:
		if f["kind"] in ["piston", "spider"]:
			_hazard_cells[f["cell"]] = true
	_graph = graph
	display_name = bot_name
	# Stable per-bot route preference and reaction speed, so four bots do not run the
	# same line and cross the finish line together.
	_planner.personality = personality
	_planner.frontier_jitter = 3.0
	think_interval = 0.18 + 0.07 * float(personality % 4) + (0.35 if skill == 0 else 0.0)
	var body := get_parent() as PlayerController
	body.display_name = bot_name
	body.set_racer_colour(colour)
	var label := body.get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.text = bot_name


func _ready() -> void:
	_body = get_parent() as PlayerController
	assert(_body != null, "BotController must be a child of a PlayerController")
	_body.is_local_player = false


func _physics_process(delta: float) -> void:
	if _graph == null or _body == null:
		return
	if not _body.input_enabled or _body.health.is_eliminated:
		_body.move_input = Vector2.ZERO
		return
	if _body.gravity.is_transitioning:
		_body.move_input = Vector2.ZERO
		return

	var cell := CaveBuilder.world_to_cell(_body.global_position)
	_observe(cell)
	_open_nearby_box()
	if _hesitate > 0.0:
		_hesitate -= delta
		_body.move_input = Vector2.ZERO
		return

	_think_timer -= delta
	if _path.is_empty() or _think_timer <= 0.0:
		_replan(cell)

	_advance_path(cell)
	if _path.is_empty():
		_body.move_input = Vector2.ZERO
		return

	_execute_step(cell, _path[0])


## A box within arm's reach is something the bot can plainly see, so opening it breaks no
## information boundary. Bots never path toward boxes; they only take what they pass.
func _open_nearby_box() -> void:
	for box: MysteryBox in WorldScope.nodes(self, "mystery_boxes"):
		if not box.is_open and box.global_position.distance_to(_body.global_position) < BOX_REACH:
			# A clue from this box is this bot's own, exactly as it would be a human's.
			box.clue_granted.connect(_on_clue, CONNECT_ONE_SHOT)
			box.interact(_body)
			if box.clue_granted.is_connected(_on_clue):
				box.clue_granted.disconnect(_on_clue)
			return


func _on_clue(racer: PlayerController, direction: Vector3, vertical: int) -> void:
	if racer != _body:
		return
	knowledge.observe_clue(direction, vertical)
	# Re-think with the new hint rather than finishing a walk toward somewhere else.
	_path.clear()
	_body.rig.emote("a clue!")


## Feed the knowledge model exactly what is visible from this cell and nothing more.
func _observe(cell: Vector3i) -> void:
	if not _graph.has_cell(cell):
		return
	var finish_here := cell == _graph.finish_cell
	# Easy bots stop to look around at every junction they have not seen before.
	if skill == 0 and not knowledge.has_seen(cell) and _graph.degree(cell) >= 3:
		_hesitate = EASY_JUNCTION_PAUSE
	knowledge.observe(cell, int(_graph.cells[cell]), finish_here)
	if _hazard_cells.has(cell):
		knowledge.observe_hazard(cell)

	# Spotting the exit invalidates whatever it was exploring toward.
	if knowledge.exit_found and not _exit_was_known:
		_exit_was_known = true
		_path.clear()


func _replan(cell: Vector3i) -> void:
	_think_timer = think_interval
	_path = _planner.plan_from(knowledge, cell, _grav(), _body.gravity.charges)
	_path_gravs = _planner.last_gravities.duplicate()


## Drop steps the bot has already reached. Comparing occupied cells rather than distance
## keeps this correct when a fall carries it several cells at once.
func _advance_path(cell: Vector3i) -> void:
	while not _path.is_empty() and _path[0] == cell:
		_path.remove_at(0)
		if not _path_gravs.is_empty():
			_path_gravs.remove_at(0)


func _execute_step(cell: Vector3i, target: Vector3i) -> void:
	var delta: Vector3i = target - cell
	var dir_index: int = CaveGraph.DIRS.find(delta)
	if dir_index == -1:
		# The bot has drifted off its plan; rethink next tick.
		_path.clear()
		return

	var current := _grav()
	var wanted := _path_gravs[0] if not _path_gravs.is_empty() else current
	if not _planner._can_traverse(dir_index, wanted):
		wanted = current if _planner._can_traverse(dir_index, current) else wanted
	var wanted_dir: int = BotPlanner.GRAV_TO_DIR[wanted]
	var centre := CaveBuilder.cell_to_world(cell)

	if wanted != current:
		# A Move first. If the step is a fall along the new gravity -- up a shaft after an
		# inversion, say -- line up with the opening before spending it.
		if dir_index == wanted_dir and _distance_across(centre, wanted_dir) > CENTRE_TOLERANCE:
			_steer_towards(centre)
			_body.sprint_input = false
			return
		_body.move_input = Vector2.ZERO
		_body.gravity.request_direction(Vector3(CaveGraph.DIRS[wanted_dir]))
		return

	if dir_index == BotPlanner.GRAV_TO_DIR[current]:
		# Falling along our own gravity: line up with the opening, then let go.
		if _distance_across(centre, dir_index) > CENTRE_TOLERANCE:
			_steer_towards(centre)
			_body.sprint_input = false
		else:
			_body.move_input = Vector2.ZERO
		return

	_steer_towards(CaveBuilder.cell_to_world(target))
	_body.sprint_input = skill >= 2 or (skill == 1 and _path.size() >= 3)


## Distance from `world_target` measured in the plane perpendicular to a grid axis.
func _distance_across(world_target: Vector3, axis_dir: int) -> float:
	var axis := Vector3(CaveGraph.DIRS[axis_dir])
	var to_target := world_target - _body.global_position
	return (to_target - axis * to_target.dot(axis)).length()


func _steer_towards(world_target: Vector3) -> void:
	var to_target := world_target - _body.global_position
	var up := _body.gravity.local_up()
	var flat := to_target - up * to_target.dot(up)
	if flat.length() < 0.05:
		_body.move_input = Vector2.ZERO
		return

	# move_input is read in the racer's current movement frame, exactly as a human's WASD.
	var axes := _body.movement_axes()
	var dir := flat.normalized()
	_body.move_input = Vector2(dir.dot(axes["right"]), -dir.dot(axes["forward"])).normalized()


func _grav() -> int:
	return BotPlanner.grav_index(_body.gravity.gravity_dir)
