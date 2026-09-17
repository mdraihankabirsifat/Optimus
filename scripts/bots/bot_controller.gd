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

# --- Prompt 3: progress watchdog ---------------------------------------------------------
## Seconds without real progress (moving 1.2 units) before each recovery stage.
const STALL_REPLAN := 2.5
const STALL_BLOCK := 5.0
const STALL_ESCAPE := 8.0
const STALL_CYCLE := 14.0
const BLOCK_SECONDS := 20.0
## Gravity escapes a bot may spend in one cell before it stops trying there.
const ESCAPES_PER_CELL := 2
var _clock := 0.0
var _stall := 0.0
var _anchor := Vector3.INF
var _stage := 0
var _escapes: Dictionary = {}
var _yield_timer := 0.0
var _yield_dir := Vector3.ZERO
## After turning onto a wall to escape, walk "up" that wall (toward the old ceiling) this long
## to clear the lip before the route resumes.
var _climb_timer := 0.0
var _climb_dir := Vector3.ZERO
## Developer diagnostics: what the bot is doing about a stall, or why it is waiting.
var recovery_note := ""
var wait_reason := ""
var recoveries := 0

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
	_listen_for_damage.call_deferred()


## Getting hurt somewhere is something the bot felt: that cell is dangerous from now on,
## exactly as a person would remember it. And a stall that hurts must not wait politely.
## Deferred: the racer's health node is only ready after this controller.
func _listen_for_damage() -> void:
	if _body == null or _body.health == null:
		return
	_body.health.damaged.connect(func(_amount: float, _source: String) -> void:
		if _body.duel_dof > 0:
			return
		var here := CaveBuilder.world_to_cell(_body.global_position)
		knowledge.observe_hazard(here)
		if _stall >= STALL_REPLAN and _stage < 2:
			_stage = 2
			_stall = STALL_ESCAPE)


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
	_battle_combat(delta)
	if _seek_sprint_gift():
		return
	if _hesitate > 0.0:
		_hesitate -= delta
		_body.move_input = Vector2.ZERO
		return

	_clock += delta
	knowledge.now = _clock
	_think_timer -= delta
	if _path.is_empty() or _think_timer <= 0.0:
		_replan(cell)

	_advance_path(cell)
	if _climb_timer > 0.0:
		_climb_timer -= delta
		var axes := _body.movement_axes()
		var d := _climb_dir - (axes["up"] as Vector3) * _climb_dir.dot(axes["up"])
		if d.length() > 0.1:
			d = d.normalized()
			_body.move_input = Vector2(d.dot(axes["right"]), -d.dot(axes["forward"]))
			return
	_watchdog(cell, delta)
	if _path.is_empty():
		_body.move_input = Vector2.ZERO
		return

	_execute_step(cell, _path[0])
	_yield_to_racers(delta)


## Prompt 3: bots must never stand still without a reason. Real progress is moving; tiny
## jitter is not. An explained wait (countdown, easy-bot pause, gravity turn, waiting for a
## regenerated Move) never escalates. An unexplained stall escalates in stages, each one
## something a human could do: think again, give up on that doorway for a while and hop,
## then spend a Move to walk a different surface out -- never teleporting, never free Moves.
func _watchdog(cell: Vector3i, delta: float) -> void:
	if _anchor == Vector3.INF or _body.global_position.distance_to(_anchor) > 1.2:
		_anchor = _body.global_position
		_stall = 0.0
		_stage = 0
		recovery_note = ""
		wait_reason = ""
		return
	if wait_reason != "" and _body.gravity.charges > 0:
		wait_reason = ""
		_stall = STALL_ESCAPE - 0.5
	if wait_reason != "":
		return
	_stall += delta
	if _stage == 0 and _stall >= STALL_REPLAN:
		_stage = 1
		recoveries += 1
		recovery_note = "replan"
		_path.clear()
	elif _stage == 1 and _stall >= STALL_BLOCK:
		_stage = 2
		recovery_note = "blocked edge, hop"
		if not _path.is_empty():
			var dir := CaveGraph.DIRS.find(_path[0] - cell)
			if dir >= 0:
				knowledge.block_edge(cell, dir, BLOCK_SECONDS)
		if _body.can_jump():
			_body.jump_requested = true
		_path.clear()
	elif _stage == 2 and _stall >= STALL_ESCAPE:
		_stage = 3
		_gravity_escape(cell)
	elif _stall >= STALL_CYCLE:
		_stage = 1
		_stall = STALL_REPLAN
		_path.clear()


## Out of a pit or a snag by changing surface: flip to the ceiling if there is one, else turn
## onto a solid wall. Paid for like any other Move; with no Move left it waits for regen, or
## trades a heart when that is legal and it is not the last one, or reports itself trapped.
func _gravity_escape(cell: Vector3i) -> void:
	if int(_escapes.get(cell, 0)) >= ESCAPES_PER_CELL:
		recovery_note = "trapped here: escapes spent"
		return
	var down_dir := BotPlanner.GRAV_TO_DIR[_grav()]
	var target_dir := -1
	var up_dir := CaveGraph.opposite(down_dir)
	if _graph.has_cell(cell) and not knowledge.discovered.is_linked(cell, up_dir):
		target_dir = up_dir   # a real ceiling above: flip onto it
	else:
		for d: int in 6:
			if d == down_dir or d == up_dir:
				continue
			if not knowledge.discovered.is_linked(cell, d):
				target_dir = d   # a solid wall: turn onto it
				break
	if target_dir < 0:
		recovery_note = "trapped here: no surface to use"
		return
	if _body.gravity.charges <= 0:
		var world := _body.get_parent()
		if bool(world.get("_move_regen")):
			wait_reason = "waiting for a regenerated Move"
			return
		if _body.health.hearts >= AppConfig.HEART_EXCHANGE_COST * 2.0 and world.has_method("request_heart_exchange"):
			if String(world.call("request_heart_exchange", _body)) != "":
				recovery_note = "trapped here: no Move to spend"
				return
		else:
			recovery_note = "trapped here: no Move to spend"
			return
	_escapes[cell] = int(_escapes.get(cell, 0)) + 1
	recovery_note = "gravity escape"
	if target_dir != up_dir:
		# Onto a wall: once turned, climb toward the old ceiling to get above the lip.
		_climb_dir = Vector3(CaveGraph.DIRS[up_dir])
		_climb_timer = 1.4 + AppConfig.GRAVITY_TRANSITION_TIME
	_body.move_input = Vector2.ZERO
	_body.gravity.request_direction(Vector3(CaveGraph.DIRS[target_dir]))
	_path.clear()


## Two racers nose to nose in a tunnel: the one with the higher id steps to its right for a
## moment, so they pass instead of pushing forever. Deterministic, so they never both yield.
func _yield_to_racers(delta: float) -> void:
	if _yield_timer > 0.0:
		_yield_timer -= delta
		var axes := _body.movement_axes()
		var d := _yield_dir
		_body.move_input = (_body.move_input + Vector2(d.dot(axes["right"]), -d.dot(axes["forward"]))).limit_length(1.0)
		return
	if _body.move_input.length() < 0.2 or _stall < 0.6:
		return
	var axes := _body.movement_axes()
	var wish: Vector3 = (axes["right"] * _body.move_input.x - axes["forward"] * _body.move_input.y).normalized()
	for other: Node in WorldScope.nodes(self, "racers"):
		var o := other as PlayerController
		if o == null or o == _body or o.collision_layer == 0:
			continue
		var rel := o.global_position - _body.global_position
		if rel.length() < 1.4 and rel.normalized().dot(wish) > 0.5 and _gives_way_to(o):
			_yield_dir = (axes["right"] as Vector3)
			_yield_timer = 0.7
			return


## Who steps aside. Instance ids alone can form a cycle -- A waits for B, B for C, C for A --
## which reads as three bots jittering in a doorway. The racer with less left to walk has
## right of way; a human always does; ids only break an exact tie, and that order is total.
func _gives_way_to(other: PlayerController) -> bool:
	var their_controller := other.get_node_or_null("BotController") as BotController
	if their_controller == null:
		return true
	var mine := _path.size()
	var theirs: int = their_controller.remaining_steps()
	if mine != theirs:
		return mine > theirs
	return _body.get_instance_id() > other.get_instance_id()


func remaining_steps() -> int:
	return _path.size()


## Master Prompt 4, Battle Mode: a bot keeps exploring the cave with its normal planner and
## shoots any rival it can actually see within range, aiming with its own body and head and
## firing through BattleMode.fire -- the same rules, cooldown and hitscan as a human.
var _battle_node: BattleMode
var _battle_pause := 0.0


func _battle() -> BattleMode:
	if _battle_node == null:
		_battle_node = WorldScope.first(self, "battle_mode") as BattleMode
	return _battle_node


func _battle_combat(delta: float) -> bool:
	var b := _battle()
	if b == null or not b.is_alive(_body):
		return false
	_battle_pause -= delta
	var eye := _body.head.global_position
	var target: PlayerController = null
	var best := 30.0
	for other: PlayerController in b.fighters:
		if other == _body or not b.is_alive(other) or not is_instance_valid(other):
			continue
		var d := eye.distance_to(other.global_position)
		if d < best and _duel_line_of_sight(eye, other):
			best = d
			target = other
	if target == null:
		return false
	var up := _body.gravity.local_up()
	var spread: float = [1.2, 0.8, 0.5][skill] * clampf(best / 12.0, 0.5, 2.0)
	var aim := (target.global_position + up * 0.3 - eye).normalized()
	var turn: float = [4.0, 7.0, 10.0][skill] * delta
	var flat := aim - up * aim.dot(up)
	if flat.length() > 0.05:
		var want := Basis.looking_at(flat.normalized(), up).get_rotation_quaternion()
		_body.global_basis = Basis(_body.global_basis.get_rotation_quaternion().slerp(want, minf(1.0, turn))).orthonormalized()
	_body.head.rotation.x = move_toward(_body.head.rotation.x, asin(clampf(aim.dot(up), -1.0, 1.0)), turn)
	var facing := -_body.head.global_basis.z
	if facing.dot(aim) > cos(0.15) and _battle_pause <= 0.0:
		var jitter := Vector3(_duel_rng.randf_range(-1, 1), _duel_rng.randf_range(-0.5, 0.5), _duel_rng.randf_range(-1, 1)) * spread * 0.05
		if b.fire(_body, eye, (facing + jitter).normalized()):
			_battle_pause = [0.9, 0.6, 0.35][skill]
	return true


## Master Prompt 4: a Sprint Gift the bot can plainly see -- in its own cell, close by -- is
## worth a few steps. It walks over and takes it; the pickup and the 5-second window are the
## same as a human's, and the movement code only lets it sprint inside that window.
func _seek_sprint_gift() -> bool:
	if _body.gravity.is_transitioning or _body.sprint_gift_left > 1.0:
		return false
	var here := CaveBuilder.world_to_cell(_body.global_position)
	for gift: SprintGift in WorldScope.nodes(self, "sprint_gifts"):
		if not gift.available or CaveBuilder.world_to_cell(gift.global_position) != here:
			continue
		if gift.global_position.distance_to(_body.global_position) > 7.0:
			continue
		_steer_towards(gift.global_position)
		return true
	return false


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
	# Battle Mode has no exit: the cell is just a cell.
	var finish_here := cell == _graph.finish_cell and _battle() == null
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
	_planner.hearts = _body.health.hearts
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

	_steer_towards(_doorway_aim(cell, dir_index, CaveBuilder.cell_to_world(target)))
	_body.sprint_input = skill >= 2 or (skill == 1 and _path.size() >= 3)


## Prompt 3: the openings between cells are tunnel-sized (4 units) even out of a 7-unit chamber.
## A bot that heads straight for the next cell's centre from a corner of a chamber scrapes the
## frame beside the opening and stalls. Off the centre line, aim at a point ahead ON the line
## first, so it lines up with the mouth before going through it.
func _doorway_aim(cell: Vector3i, dir_index: int, target_centre: Vector3) -> Vector3:
	var dir := Vector3(CaveGraph.DIRS[dir_index])
	var centre := CaveBuilder.cell_to_world(cell)
	var rel := _body.global_position - centre
	var up := _body.gravity.local_up()
	var lateral := rel - dir * rel.dot(dir)
	lateral -= up * lateral.dot(up)
	if lateral.length() < CaveBuilder.TUNNEL_HALF - 1.0:
		return target_centre
	var along := rel.dot(dir)
	# A point on the axis a little ahead, kept inside this cell until lined up.
	var ahead := clampf(along + 1.5, -CaveBuilder.CELL_SIZE * 0.5, CaveBuilder.CELL_SIZE * 0.5 - 1.5)
	return centre + dir * ahead + (rel - lateral - dir * rel.dot(dir))


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
		if float(st["lock_cd"]) <= 0.0 and float(foe_st["lock_left"]) <= 0.0 \
				and float(foe_st["immune_left"]) <= 0.0 and dist < 30.0:
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


## Developer diagnostics only (tests, logs, F3 overlay). Never shown to players.
func debug_state() -> String:
	var next := str(_path[0]) if not _path.is_empty() else "-"
	return "path %d next %s exit %s stage %d %s%s recoveries %d" % [_path.size(), next,
		"known" if knowledge.exit_found else "unknown", _stage, recovery_note,
		(" wait: " + wait_reason) if wait_reason != "" else "", recoveries]
