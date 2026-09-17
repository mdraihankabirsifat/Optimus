extends Node
## DUEL-001..012 — Freedom Duel: qualification, DOF, health, weapons, Freedom Core, DOF
## shifts, sudden death, results, fallbacks, spectating and a bot-vs-bot duel.
## Run: godot --headless --fixed-fps 60 res://tests/test_duel.tscn

const SEED := 4242

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame

	await _test_qualification_and_duel()
	await _test_fallbacks()
	await _test_bot_duel()

	print("")
	print("==================================================")
	print("  DUEL-001..012   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


# --- Helpers ----------------------------------------------------------------------------

func _make_world(bots: int, brains: bool = false) -> Node3D:
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = SEED
	world.bot_count = bots
	world.bot_skill = 2
	add_child(world)
	await get_tree().process_frame
	var mc: MatchController = world.match_controller
	mc._advance_countdown(10.0)
	if not brains:
		for b: Node3D in world.bots:
			b.get_node("BotController").set_physics_process(false)
	return world


func _make_rush_world(bots: int, seconds: int) -> Node3D:
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = SEED
	world.bot_count = bots
	world.ruleset = AppConfig.RULESET_RUSH
	world.rush_seconds = seconds
	add_child(world)
	await get_tree().process_frame
	(world.match_controller as MatchController)._advance_countdown(10.0)
	for b: Node3D in world.bots:
		b.get_node("BotController").set_physics_process(false)
	return world


func _free_world(world: Node3D) -> void:
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _finish(world: Node3D, body: Node3D) -> void:
	(world.match_controller as MatchController)._on_finish_body_entered(body)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Put two fighters on the clear X = 0 line of the arena, facing each other.
func _face_off(duel: FreedomDuel, a: PlayerController, b: PlayerController) -> void:
	var o := DuelArena.ORIGIN
	a.global_position = o + Vector3(0, 1.0, -7)
	b.global_position = o + Vector3(0, 1.0, 7)
	a.global_basis = Basis.looking_at(Vector3.BACK, Vector3.UP)
	b.global_basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	a.head.rotation = Vector3.ZERO
	b.head.rotation = Vector3.ZERO
	await _frames(3)


func _shoot(duel: FreedomDuel, from: PlayerController, to: PlayerController, kind: String) -> bool:
	var st: Dictionary = duel.fighters[from]
	st["pulse_cd"] = 0.0
	st["lock_cd"] = 0.0
	to.health.is_invulnerable = false
	var eye := from.head.global_position
	return duel.fire(from, kind, eye, (to.global_position - eye).normalized())


func _tick(duel: FreedomDuel, seconds: float) -> void:
	var steps := ceili(seconds / 0.05)
	for i in steps:
		duel._tick_fight(0.05)


# --- Tests ------------------------------------------------------------------------------

func _test_qualification_and_duel() -> void:
	_section("qualification")
	var world: Node3D = await _make_world(3)
	var mc: MatchController = world.match_controller
	var duel: FreedomDuel = world.duel
	var player: PlayerController = world.local_player()
	var a := world.bots[0] as PlayerController
	var b := world.bots[1] as PlayerController
	var c := world.bots[2] as PlayerController
	_check("duel exists offline with 4 racers", duel != null and mc.duel == duel)
	_check("phase starts OFF", duel.phase == FreedomDuel.Phase.OFF)

	# Cave state that must NOT carry into the duel.
	a.gravity.charges = 0
	b.health.hearts = 1.5
	b.health.grant_second_chance()

	_finish(world, a)
	_check("first finisher is Finalist A", duel.finalist_a == a)
	_check("phase WAITING after one qualifier", duel.phase == FreedomDuel.Phase.WAITING)
	_check("Qualified 1st recorded", _racer(mc, a)["qualified"] == 1)
	_check("race does not end on first finish", mc.phase == MatchController.Phase.RACING)
	_check("Qualified 1st waits in the arena", DuelArena.contains(a.global_position))
	_check("Qualified 1st can move while waiting", a.input_enabled)
	_check("Qualified 1st cannot be damaged while waiting", a.health.apply_damage(1.0, "fire") == false)
	_finish(world, a)
	_check("finishing twice does not qualify twice", duel.finalist_b == null and duel.phase == FreedomDuel.Phase.WAITING)
	_check("others still racing while A waits", c.input_enabled and player.input_enabled)

	_finish(world, b)
	_check("second finisher is Finalist B", duel.finalist_b == b)
	_check("Qualified 2nd recorded", _racer(mc, b)["qualified"] == 2)
	_check("second qualifier starts the duel intro", duel.phase == FreedomDuel.Phase.INTRO)
	_check("both finalists in the arena", DuelArena.contains(a.global_position) and DuelArena.contains(b.global_position))
	_check("finalists frozen during intro", not a.input_enabled and not b.input_enabled)
	_check("non-finalists stop when the duel starts", not c.input_enabled and not player.input_enabled)
	_check("stopped racers keep their progress", _racer(mc, c)["stopped_by_duel"] and int(_racer(mc, c)["progress"]) < 999)

	_section("duel start state")
	_check("Finalist A starts 3DOF", duel.effective_dof(a) == 3 and a.duel_dof == 3)
	_check("Finalist B starts 2DOF", duel.effective_dof(b) == 2 and b.duel_dof == 2)
	_check("A can jump, B cannot", a.can_jump() and not b.can_jump())
	_check("fresh duel health for A", is_equal_approx(a.health.hearts, AppConfig.DUEL_HEARTS))
	_check("fresh duel health for B (cave damage gone)", is_equal_approx(b.health.hearts, AppConfig.DUEL_HEARTS))
	_check("B gets exactly one shield", b.health.has_shield and duel.fighters[b]["shield_granted"])
	_check("A gets no compensation", not a.health.has_shield)
	_check("no Second Chance carried in", not b.health.has_second_chance)
	_check("Move charges do not drive the duel (A at 0 charges still 3DOF)", a.gravity.charges == 0 and duel.effective_dof(a) == 3)
	var spectate: Array = world._spectate_targets()
	_check("spectators follow the two finalists", spectate.size() == 2 and a in spectate and b in spectate)
	_check("a weapon cannot fire before FIGHT", duel.fire(a, "pulse") == false)

	var ticks: Array[int] = []
	duel.countdown.connect(func(v: int) -> void: ticks.append(v))
	for i in 20:
		duel._tick_intro(0.25)
	_check("countdown ran 3-2-1-0", ticks == [3, 2, 1, 0])
	_check("phase FIGHT after the countdown", duel.phase == FreedomDuel.Phase.FIGHT)
	_check("finalists move on FIGHT", a.input_enabled and b.input_enabled)

	_section("3DOF / 2DOF / 1DOF movement")
	await _face_off(duel, a, b)
	var start_b := b.global_position
	b.jump_requested = true
	await _frames(6)
	_check("2DOF finalist cannot jump", b.global_position.y <= start_b.y + 0.05)
	a.jump_requested = true
	await _frames(8)
	_check("3DOF finalist jumps", a.global_position.y > DuelArena.ORIGIN.y + 1.3)
	await _frames(40)

	_section("Pulse Blaster")
	await _face_off(duel, a, b)
	var hits := [0]
	b.health.damaged.connect(func(_amt: float, _s: String) -> void: hits[0] += 1)
	_check("pulse fires", _shoot(duel, a, b, "pulse"))
	_check("B's opening shield absorbs the first hit", not b.health.has_shield and is_equal_approx(b.health.hearts, 5.0))
	_check("blaster has a cooldown", duel.fire(a, "pulse") == false)
	_shoot(duel, a, b, "pulse")
	_check("second pulse deals damage once", is_equal_approx(b.health.hearts, 5.0 - AppConfig.PULSE_DAMAGE) and hits[0] == 1)
	_check("damage dealt is counted", is_equal_approx(float(duel.fighters[a]["damage_dealt"]), AppConfig.PULSE_DAMAGE))

	_section("Axis Lock")
	_shoot(duel, a, b, "lock")
	_check("lock takes B from 2DOF to 1DOF", duel.effective_dof(b) == 1 and b.duel_dof == 1)
	_check("1DOF keeps one arena axis", b.duel_axis != Vector3.ZERO)
	_check("lock names the removed axis", String(duel.fighters[b]["removed"]) in ["X", "Z"])
	_check("lock landed counted", int(duel.fighters[a]["locks_landed"]) == 1)
	var axis := b.duel_axis
	b.move_input = Vector2(1, 0)
	b.velocity = Vector3.ZERO
	await _frames(20)
	var off_axis := (b.velocity - axis * b.velocity.dot(axis))
	off_axis.y = 0.0
	_check("1DOF moves only along its axis", off_axis.length() < 0.2)
	b.move_input = Vector2.ZERO
	await _face_off(duel, a, b)
	_tick(duel, AppConfig.AXIS_LOCK_DURATION + 0.1)
	_check("axis restores after the lock", duel.effective_dof(b) == 2)
	_check("restored fighter is briefly immune", float(duel.fighters[b]["immune_left"]) > 0.0)
	var resisted := [false]
	duel.lock_resisted.connect(func(_t: PlayerController) -> void: resisted[0] = true)
	_shoot(duel, a, b, "lock")
	_check("immunity prevents chain-locking", resisted[0] and duel.effective_dof(b) == 2)
	_tick(duel, AppConfig.AXIS_LOCK_IMMUNITY + 0.1)
	_shoot(duel, a, b, "lock")
	_check("lock works again after immunity", duel.effective_dof(b) == 1)
	_tick(duel, AppConfig.AXIS_LOCK_DURATION + AppConfig.AXIS_LOCK_IMMUNITY + 0.2)
	_shoot(duel, b, a, "lock")
	_check("lock takes 3DOF to 2DOF and removes Y", duel.effective_dof(a) == 2 and duel.fighters[a]["removed"] == "Y" and not a.can_jump())
	_tick(duel, AppConfig.AXIS_LOCK_DURATION + 0.1)

	_section("Freedom Core")
	duel.core_active = true
	duel.core_position = b.global_position
	duel.capture_core(b)
	_check("core lifts 2DOF to 3DOF", duel.effective_dof(b) == 3 and b.can_jump())
	_check("core capture counted", int(duel.fighters[b]["cores"]) == 1)
	_check("core is consumed once", not duel.core_active)
	duel.capture_core(b)
	_check("a consumed core cannot be taken again", int(duel.fighters[b]["cores"]) == 1)
	_tick(duel, AppConfig.CORE_BOOST_TIME + 0.1)
	_check("core boost is temporary", duel.effective_dof(b) == 2)
	a.health.drop_shield()
	duel.core_active = true
	duel.capture_core(a)
	_check("3DOF core fallback grants a shield", a.health.has_shield and duel.effective_dof(a) == 3)
	a.health.drop_shield()
	duel._core_timer = 999.0

	_section("DOF shift")
	duel._shift_timer = 0.0
	duel._shift_count = 0
	_tick(duel, 0.05)
	_check("FULL FREEDOM gives B 3DOF", duel.shift_name == "FULL FREEDOM" and duel.effective_dof(b) == 3)
	_tick(duel, AppConfig.DOF_SHIFT_DURATION + 0.1)
	_check("shift ends and B returns to 2DOF", duel.shift_name == "" and duel.effective_dof(b) == 2)
	duel._shift_timer = 0.0
	_tick(duel, 0.05)
	_check("Y AXIS LOCKED takes A's jump", duel.shift_name == "Y AXIS LOCKED" and duel.effective_dof(a) == 2)
	_tick(duel, AppConfig.DOF_SHIFT_DURATION + 0.1)
	_check("Y axis restored", duel.effective_dof(a) == 3)

	_section("sudden death")
	b.health.grant_shield()
	duel.duel_time = AppConfig.SUDDEN_DEATH_AT - 0.01
	_tick(duel, 0.05)
	_check("sudden death starts", duel.sudden_death)
	_check("both finalists 3DOF in sudden death", duel.effective_dof(a) == 3 and duel.effective_dof(b) == 3)
	_check("shields end in sudden death", not b.health.has_shield)
	await _face_off(duel, a, b)
	var before := b.health.hearts
	_shoot(duel, a, b, "pulse")
	_check("sudden death hits harder", is_equal_approx(before - b.health.hearts, AppConfig.PULSE_DAMAGE * AppConfig.SUDDEN_DEATH_DAMAGE_SCALE))

	_section("knockout and results")
	b.health.hearts = 0.5
	_racer(mc, c)["progress"] = 3
	_racer(mc, player)["progress"] = 9
	_shoot(duel, a, b, "pulse")
	_check("zero duel health ends the duel", duel.phase == FreedomDuel.Phase.ENDED)
	_check("zero duel health ends the match", mc.phase == MatchController.Phase.ENDED)
	_check("duel loser is not cave-eliminated", not b.health.is_eliminated and not _racer(mc, b)["eliminated"])
	_check("Champion is A", duel.champion == a and _racer(mc, a)["duel_place"] == 1)
	_check("runner-up is B", duel.runner_up == b and _racer(mc, b)["duel_place"] == 2)
	var results := mc.build_results()
	_check("results: Champion first, runner-up second", results[0]["body"] == a and results[1]["body"] == b)
	_check("results: remaining racers by cave progress", results[2]["body"] == c and results[3]["body"] == player)
	_check("duel stats recorded", float(results[0]["duel_stats"].get("damage_dealt", 0.0)) > 0.0
		and int(results[0]["duel_stats"].get("locks_landed", 0)) >= 2)
	_check("fire after the end is refused", duel.fire(a, "pulse") == false)
	await _free_world(world)


func _test_fallbacks() -> void:
	_section("fallback: the only possible challenger is eliminated")
	var world: Node3D = await _make_world(1)
	var mc: MatchController = world.match_controller
	var duel: FreedomDuel = world.duel
	var bot := world.bots[0] as PlayerController
	_finish(world, bot)
	_check("bot waits as Qualified 1st", duel.phase == FreedomDuel.Phase.WAITING)
	world.local_player().health.eliminate()
	_check("no challenger left: Champion by default", duel.phase == FreedomDuel.Phase.ENDED and duel.champion == bot and duel.runner_up == null)
	_check("match ends, no soft-lock", mc.phase == MatchController.Phase.ENDED)
	_check("results lead with the Champion", mc.build_results()[0]["body"] == bot)
	await _free_world(world)

	_section("Normal: no waiting time limit")
	world = await _make_world(2)
	mc = world.match_controller
	duel = world.duel
	_finish(world, world.bots[0])
	duel.wait_time = 600.0
	mc.elapsed = 900.0
	await _frames(3)
	_check("Normal: Qualified 1st still waits after 15 minutes while others can qualify",
		duel.phase == FreedomDuel.Phase.WAITING and mc.phase == MatchController.Phase.RACING)
	await _free_world(world)

	_section("Rush expiry: one qualifier")
	world = await _make_rush_world(2, 180)
	mc = world.match_controller
	duel = world.duel
	_finish(world, world.bots[0])
	mc.elapsed = 179.99
	await _frames(3)
	_check("Rush: time up with one qualifier -> Champion by default", duel.phase == FreedomDuel.Phase.ENDED
		and duel.champion == world.bots[0] and duel.runner_up == null and duel.end_reason == "Rush time up")
	_check("Rush: match ended once", mc.phase == MatchController.Phase.ENDED and mc.cave_expired)
	var late := world.bots[1] as PlayerController
	_finish(world, late)
	_check("Rush: an arrival after the deadline does not count", not _racer(mc, late)["finished"])
	await _free_world(world)

	_section("Rush expiry: no qualifiers")
	world = await _make_rush_world(2, 300)
	mc = world.match_controller
	duel = world.duel
	var ups := [-1]
	mc.cave_time_up.connect(func(q: int) -> void: ups[0] = q)
	mc.elapsed = 300.5
	await _frames(3)
	_check("Rush: time up with nobody out ends the race, no Champion", mc.phase == MatchController.Phase.ENDED
		and duel.champion == null and ups[0] == 0)
	_check("Rush: results invent no Champion", int(mc.build_results()[0].get("duel_place", 0)) == 0)
	await _free_world(world)

	_section("Rush expiry: two qualifiers, the duel keeps its own clock")
	world = await _make_rush_world(3, 180)
	mc = world.match_controller
	duel = world.duel
	_finish(world, world.bots[0])
	_finish(world, world.bots[1])
	for i in 30:
		duel._tick_intro(0.25)
	mc.elapsed = 181.0
	await _frames(3)
	_check("Rush: the deadline does not end a duel already running", duel.phase == FreedomDuel.Phase.FIGHT
		and mc.phase == MatchController.Phase.RACING and mc.cave_expired)
	_check("Rush: a racer still in the cave is a DNF", not _racer(mc, world.bots[2])["finished"]
		and not world.bots[2].input_enabled)
	await _free_world(world)

	_section("force end: waiting vs fighting")
	world = await _make_world(2)
	mc = world.match_controller
	duel = world.duel
	_finish(world, world.bots[0])
	_finish(world, world.bots[1])
	for i in 30:
		duel._tick_intro(0.25)
	mc.force_end()
	_check("force end never cuts a duel short", mc.phase == MatchController.Phase.RACING and duel.phase == FreedomDuel.Phase.FIGHT)
	duel.duel_time = AppConfig.DUEL_HARD_LIMIT - 0.01
	world.bots[0].health.hearts = 4.0
	world.bots[1].health.hearts = 2.0
	_tick(duel, 0.05)
	_check("hard limit resolves on hearts", duel.phase == FreedomDuel.Phase.ENDED and duel.champion == world.bots[0])
	await _free_world(world)

	world = await _make_world(2)
	mc = world.match_controller
	duel = world.duel
	_finish(world, world.bots[0])
	mc.force_end()
	_check("force end while waiting: Qualified 1st is Champion", duel.phase == FreedomDuel.Phase.ENDED and mc.phase == MatchController.Phase.ENDED)
	await _free_world(world)

	_section("no duel without a field")
	var solo: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	solo.randomise_seed = false
	solo.fixed_seed = SEED
	solo.duel_enabled = false
	add_child(solo)
	await get_tree().process_frame
	_check("duel can be switched off for traversal harnesses", solo.duel == null and solo.match_controller.duel == null)
	await _free_world(solo)


func _test_bot_duel() -> void:
	_section("bot finalists fight")
	var world: Node3D = await _make_world(2, true)
	var mc: MatchController = world.match_controller
	var duel: FreedomDuel = world.duel
	var player: PlayerController = world.local_player()
	player.set_physics_process(false)
	_finish(world, world.bots[0])
	_finish(world, world.bots[1])
	var shots := [0, 0]
	duel.shot.connect(func(_s: PlayerController, _k: String, _f: Vector3, _t: Vector3, hit: PlayerController) -> void:
		shots[0] += 1
		if hit != null:
			shots[1] += 1)
	var frames := 0
	while duel.phase != FreedomDuel.Phase.ENDED and frames < 60 * 100:
		await get_tree().physics_frame
		frames += 1
	print("    bot duel: %d shots, %d hits, %.1f s, champion %s (%s)" % [shots[0], shots[1], duel.duel_time,
		duel.champion.display_name if duel.champion else "-", duel.end_reason])
	_check("bots shoot", shots[0] > 5)
	_check("bots land hits", shots[1] > 0)
	_check("bot duel resolves", duel.phase == FreedomDuel.Phase.ENDED and mc.phase == MatchController.Phase.ENDED)
	_check("bots stayed inside the arena", DuelArena.contains(world.bots[0].global_position) and DuelArena.contains(world.bots[1].global_position))
	await _free_world(world)


func _racer(mc: MatchController, body: Node3D) -> Dictionary:
	for r: Dictionary in mc.racers:
		if r["body"] == body:
			return r
	return {}


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
