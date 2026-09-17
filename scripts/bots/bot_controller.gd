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

# --- Freedom Duel ------------------------------------------------------------------------
var _duel: FreedomDuel
var _duel_rng := RandomNumberGenerator.new()
var _strafe_sign := 1.0
var _strafe_timer := 0.0
var _hop_timer := 1.5
var _aim_error := Vector3.ZERO
var _aim_timer := 0.0
var _stuck_timer := 0.0
var _fire_pause := 0.0


func setup(graph: CaveGraph, bot_name: String, colour: Color, personality: int, p_skill: int = 2) -> void:
	skill = clampi(p_skill, 0, 2)
	for h: Dictionary in graph.hazards:
		_hazard_cells[h["cell"]] = true
	for f: Dictionary in graph.features:
		if f["kind"] in ["piston", "spider"]:
			_hazard_cells[f["cell"]] = true
	_graph = graph
	_duel_rng.seed = personality * 7919 + 17
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
	if _body.duel_dof > 0:
		_duel_tick(delta)
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


# --- Freedom Duel ------------------------------------------------------------------------
## A finalist bot. Deliberately simple: face the opponent, keep a middle distance, strafe,
## shoot when the shot lines up, Axis Lock when it would land, go for a Freedom Core that is
## closer to it than to the opponent, hop to dodge when it has the third DOF. It aims with
## the same body and head a human turns with the mouse, and fires through the same
## FreedomDuel.fire() -- the duel's rules apply to it exactly as to a person.
func _duel_tick(delta: float) -> void:
	if _duel == null:
		_duel = WorldScope.first(self, "freedom_duel") as FreedomDuel
	if _duel == null or not _duel.is_fighting() or not _duel.fighters.has(_body):
		# Qualified 1st waiting in the arena, or the countdown: stand ready.
		_body.move_input = Vector2.ZERO
		return
	var foe := _duel.opponent_of(_body)
	if foe == null:
		_body.move_input = Vector2.ZERO
		return
	var up := _body.gravity.local_up()
	var eye := _body.head.global_position
	var foe_centre := foe.global_position + up * 0.3
	var to_foe := foe_centre - eye
	var dist := to_foe.length()
	var los := _duel_line_of_sight(eye, foe)

	# Aim, with an error that shrinks with skill and is re-rolled a few times a second.
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		_aim_timer = 0.3
		var spread: float = [1.5, 1.0, 0.65][skill] * clampf(dist / 12.0, 0.5, 2.0)
		_aim_error = Vector3(_duel_rng.randf_range(-1, 1), _duel_rng.randf_range(-0.6, 0.6), _duel_rng.randf_range(-1, 1)) * spread
	var aim := (foe_centre + _aim_error - eye).normalized()
	var turn: float = [4.0, 7.0, 10.0][skill] * delta
	var flat := aim - up * aim.dot(up)
	if flat.length() > 0.05:
		var want := Basis.looking_at(flat.normalized(), up).get_rotation_quaternion()
		var have := _body.global_basis.get_rotation_quaternion()
		_body.global_basis = Basis(have.slerp(want, minf(1.0, turn))).orthonormalized()
	var pitch := asin(clampf(aim.dot(up), -1.0, 1.0))
	_body.head.rotation.x = move_toward(_body.head.rotation.x, pitch, turn)

	var st: Dictionary = _duel.fighters[_body]
	var foe_st: Dictionary = _duel.fighters[foe]
	var facing := -_body.head.global_basis.z
	var aligned := facing.dot(to_foe.normalized()) > cos(0.12)
	if los and aligned:
		if float(st["lock_cd"]) <= 0.0 and float(foe_st["lock_left"]) <= 0.0 \n				and float(foe_st["immune_left"]) <= 0.0 and dist < 30.0:
			_duel.fire(_body, "lock")
		elif float(st["pulse_cd"]) <= 0.0 and _fire_pause <= 0.0:
			_duel.fire(_body, "pulse")
			# A person re-centres between shots; a bot holding the trigger would out-shoot anyone.
			_fire_pause = [0.9, 0.6, 0.35][skill]
	_fire_pause -= delta

	# Where to be.
	var pos := _body.global_position
	var goal := foe.global_position
	var my_dof := _duel.effective_dof(_body)
	if _duel.core_active:
		var mine := pos.distance_to(_duel.core_position)
		var theirs := foe.global_position.distance_to(_duel.core_position)
		if mine < theirs or my_dof < 3:
			goal = _duel.arena.waypoint(pos, _duel.core_position)
	var to_goal := goal - pos
	to_goal -= up * to_goal.dot(up)
	var approach := Vector3.ZERO
	if goal != foe.global_position:
		approach = to_goal.normalized() if to_goal.length() > 0.3 else Vector3.ZERO
	elif not los or dist > 15.0:
		approach = to_goal.normalized()
	elif dist < 7.0:
		approach = -to_goal.normalized() * 0.7

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = _duel_rng.randf_range(0.8, 2.0)
		_strafe_sign = -_strafe_sign if _duel_rng.randf() < 0.7 else _strafe_sign
	var right := facing.cross(up).normalized()
	var wish := approach + right * _strafe_sign * (0.8 if los else 0.3)

	# Stuck on cover: turn the strafe around, and hop if the third DOF allows it.
	var moving := (_body.velocity - up * _body.velocity.dot(up)).length()
	_stuck_timer = _stuck_timer + delta if wish.length() > 0.3 and moving < 1.0 else 0.0
	if _stuck_timer > 0.6:
		_stuck_timer = 0.0
		_strafe_sign = -_strafe_sign
		if _body.can_jump():
			_body.jump_requested = true

	_hop_timer -= delta
	if _hop_timer <= 0.0:
		_hop_timer = _duel_rng.randf_range(1.2, 3.0)
		if los and _body.can_jump() and skill > 0:
			_body.jump_requested = true

	_body.sprint_input = true
	if wish.length() < 0.05:
		_body.move_input = Vector2.ZERO
		return
	var axes := _body.movement_axes()
	var dir := wish.normalized()
	_body.move_input = Vector2(dir.dot(axes["right"]), -dir.dot(axes["forward"])).normalized()


func _duel_line_of_sight(eye: Vector3, foe: PlayerController) -> bool:
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, foe.global_position, 1 | 2, [_body.get_rid()])
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == foe
