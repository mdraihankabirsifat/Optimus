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
	for box: MysteryBox in get_tree().get_nodes_in_group("mystery_boxes"):
		if not box.is_open and box.global_position.distance_to(_body.global_position) < BOX_REACH:
			box.interact(_body)
			return


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
	_path = _planner.plan(knowledge, cell, _gravity_is_up(), _body.gravity.charges)


## Drop steps the bot has already reached. Comparing occupied cells rather than distance
## keeps this correct when a fall carries it several cells at once.
func _advance_path(cell: Vector3i) -> void:
	while not _path.is_empty() and _path[0] == cell:
		_path.remove_at(0)


func _execute_step(cell: Vector3i, target: Vector3i) -> void:
	var delta: Vector3i = target - cell
	var dir_index: int = CaveGraph.DIRS.find(delta)
	if dir_index == -1:
		# The bot has drifted off its plan; rethink next tick.
		_path.clear()
		return

	var vertical := dir_index == CaveGraph.DIR_UP or dir_index == CaveGraph.DIR_DOWN
	if vertical:
		_execute_vertical(cell, dir_index)
	else:
		_steer_towards(CaveBuilder.cell_to_world(target))
		_body.sprint_input = skill >= 2 or (skill == 1 and _path.size() >= 3)


## Vertical moves are made by gravity, not by walking. Line up under the shaft first, then
## flip the frame if the shaft runs against the way the bot is currently falling.
func _execute_vertical(cell: Vector3i, dir_index: int) -> void:
	var centre := CaveBuilder.cell_to_world(cell)
	if _horizontal_distance(centre) > CENTRE_TOLERANCE:
		_steer_towards(centre)
		_body.sprint_input = false
		return

	_body.move_input = Vector2.ZERO
	var grav: int = BotPlanner.GRAV_UP if _gravity_is_up() else BotPlanner.GRAV_DOWN
	if not _planner._can_traverse(dir_index, grav):
		_body.gravity.request_inversion()


func _steer_towards(world_target: Vector3) -> void:
	var to_target := world_target - _body.global_position
	var up := _body.gravity.local_up()
	var flat := to_target - up * to_target.dot(up)
	if flat.length() < 0.05:
		_body.move_input = Vector2.ZERO
		return

	# move_input is read in body-local space, the same space a human's WASD lands in.
	var local := _body.global_basis.inverse() * flat.normalized()
	_body.move_input = Vector2(local.x, local.z).normalized()


func _horizontal_distance(world_target: Vector3) -> float:
	var to_target := world_target - _body.global_position
	var up := _body.gravity.local_up()
	return (to_target - up * to_target.dot(up)).length()


func _gravity_is_up() -> bool:
	return _body.gravity.gravity_dir.is_equal_approx(Vector3.UP)
