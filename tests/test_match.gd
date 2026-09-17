extends Node
## MATCH-001..003 / HEALTH-001..004 — match flow verification.
## Run: godot --headless res://tests/test_match.tscn

var _passed := 0
var _failed := 0


class FakeRacer:
	extends Node3D
	var input_enabled: bool = true
	var health: PlayerHealth

	func _init() -> void:
		health = PlayerHealth.new()
		health.name = "PlayerHealth"
		add_child(health)


func _ready() -> void:
	# quit() is ignored if called before the tree reaches its main loop.
	await get_tree().process_frame

	_test_countdown_gates_play()
	_test_finish_order()
	_test_elimination()
	_test_results_ordering()
	_test_time_limit()
	_test_format_time()
	_test_health_rules()

	print("")
	print("==================================================")
	print("  MATCH-001..003   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_countdown_gates_play() -> void:
	_section("countdown gates movement and damage")
	var ctx := _make_match(1)
	var mc: MatchController = ctx["match"]
	var racer: FakeRacer = ctx["racers"][0]

	_check("input frozen during countdown", racer.input_enabled == false)
	_check("damage blocked during countdown",
		racer.health.apply_damage(2.0, "fire") == false)
	_check("hearts untouched before GO", is_equal_approx(racer.health.hearts, 5.0))

	_advance(mc, 3.1)
	_check("phase is RACING after countdown", mc.phase == MatchController.Phase.RACING)
	_check("input restored on GO", racer.input_enabled == true)
	_check("damage enabled on GO", racer.health.apply_damage(1.0, "fire") == true)
	_check("timer starts near zero", mc.elapsed < 0.2)
	_teardown(ctx)


func _test_finish_order() -> void:
	_section("finish order and times")
	var ctx := _make_match(3)
	var mc: MatchController = ctx["match"]
	var racers: Array = ctx["racers"]
	_advance(mc, 3.1)

	_advance(mc, 5.0)
	mc._on_finish_body_entered(racers[1])
	_advance(mc, 4.0)
	mc._on_finish_body_entered(racers[0])

	_check("first racer through gets place 1", mc.racers[1]["place"] == 1)
	_check("second racer through gets place 2", mc.racers[0]["place"] == 2)
	_check("finish times are recorded in order",
		float(mc.racers[1]["finish_time"]) < float(mc.racers[0]["finish_time"]))
	_check("finished racer cannot move", racers[1].input_enabled == false)

	# Re-entering the finish trigger must not renumber anyone.
	mc._on_finish_body_entered(racers[1])
	_check("re-entering the finish does not re-place", mc.racers[1]["place"] == 1)
	_check("third racer still unresolved", mc.racers[2]["place"] == 0)
	_check("match still running with one racer out", mc.phase == MatchController.Phase.RACING)

	mc._on_finish_body_entered(racers[2])
	_check("match ends when every racer resolves", mc.phase == MatchController.Phase.ENDED)
	_teardown(ctx)


func _test_elimination() -> void:
	_section("elimination")
	var ctx := _make_match(2)
	var mc: MatchController = ctx["match"]
	var racers: Array = ctx["racers"]
	_advance(mc, 3.1)
	_advance(mc, 2.0)

	racers[0].health.apply_damage(5.0, "fall")
	_check("zero hearts eliminates", racers[0].health.is_eliminated)
	_check("elimination recorded by the match", mc.racers[0]["eliminated"])
	_check("eliminated racer cannot move", racers[0].input_enabled == false)
	_check("eliminated racer has no place", mc.racers[0]["place"] == 0)

	racers[0].health.refill(3.0)
	_check("Heart Refill never resurrects the eliminated",
		is_equal_approx(racers[0].health.hearts, 0.0))

	mc._on_finish_body_entered(racers[0])
	_check("an eliminated racer cannot finish", mc.racers[0]["place"] == 0)

	mc._on_finish_body_entered(racers[1])
	_check("survivor finishing ends the match", mc.phase == MatchController.Phase.ENDED)
	_teardown(ctx)


func _test_results_ordering() -> void:
	_section("results ordering")
	var ctx := _make_match(3)
	var mc: MatchController = ctx["match"]
	var racers: Array = ctx["racers"]
	_advance(mc, 3.1)

	_advance(mc, 2.0)
	racers[0].health.apply_damage(5.0, "fall")   # eliminated early
	_advance(mc, 3.0)
	racers[1].health.apply_damage(5.0, "fall")   # eliminated later
	_advance(mc, 1.0)
	mc._on_finish_body_entered(racers[2])        # finisher

	var results := mc.build_results()
	_check("finisher ranks first", results[0]["name"] == "R2")
	_check("later elimination outranks earlier", results[1]["name"] == "R1")
	_check("earliest elimination ranks last", results[2]["name"] == "R0")
	_teardown(ctx)


func _test_time_limit() -> void:
	_section("Normal has no cave time limit")
	var normal := _make_match(1)
	var nmc: MatchController = normal["match"]
	_advance(nmc, 3.1)
	_advance(nmc, 301.0)
	_advance(nmc, 600.0)
	_check("Normal is still racing after 15 minutes", nmc.phase == MatchController.Phase.RACING)
	_teardown(normal)

	_section("Rush time limit")
	var ctx := _make_match(1)
	var mc: MatchController = ctx["match"]
	mc.cave_time_limit = 180.0
	_advance(mc, 3.1)
	_advance(mc, 179.0)
	_check("Rush still racing before its deadline", mc.phase == MatchController.Phase.RACING)
	_advance(mc, 2.0)
	_check("Rush ends when the clock expires with no qualifiers", mc.phase == MatchController.Phase.ENDED and mc.cave_expired)

	var results := mc.build_results()
	_check("unresolved racer is recorded as DNF",
		not results[0]["finished"] and not results[0]["eliminated"])
	_teardown(ctx)


func _test_format_time() -> void:
	_section("time formatting")
	_check("under a minute", MatchController.format_time(9.5) == "0:09.50")
	_check("over a minute", MatchController.format_time(75.25) == "1:15.25")


## HEALTH-001..005: half and full hearts, cooldowns, refill clamp, shield, Second Chance.
func _test_health_rules() -> void:
	_section("health rules")
	var h := PlayerHealth.new()
	add_child(h)
	_check("starts on exactly 5 hearts", is_equal_approx(h.hearts, 5.0))

	h.apply_damage(0.5, "fire_1", 1.0)
	_check("fire takes half a heart", is_equal_approx(h.hearts, 4.5))
	_check("same source during its cooldown does nothing", not h.apply_damage(0.5, "fire_1", 1.0))
	_check("any source during invulnerability does nothing", not h.apply_damage(1.0, "spider_1"))
	_check("hearts unchanged by blocked hits", is_equal_approx(h.hearts, 4.5))
	h._process(AppConfig.INVULNERABILITY_TIME + 0.05)
	h.apply_damage(1.0, "spider_1")
	_check("a spider takes a full heart once mercy ends", is_equal_approx(h.hearts, 3.5))

	# Standing in fire for 10 seconds, ticking at 60 fps.
	var drain := PlayerHealth.new()
	add_child(drain)
	for i in 600:
		drain._process(1.0 / 60.0)
		drain.apply_damage(AppConfig.DAMAGE_FIRE, "fire_9", AppConfig.FIRE_TICK_COOLDOWN)
	_check("10 s in fire drains at most 10 ticks, not 600 (%.1f hearts left)" % drain.hearts,
		drain.hearts >= AppConfig.HEARTS_MAX - AppConfig.DAMAGE_FIRE * 10.0 and drain.hearts < AppConfig.HEARTS_MAX)

	h.refill(99.0)
	_check("Heart Refill clamps to 5", is_equal_approx(h.hearts, AppConfig.HEARTS_MAX))

	h._process(5.0)
	h.grant_shield()
	h.apply_damage(1.0, "piston_1")
	_check("a shield soaks one whole hit", is_equal_approx(h.hearts, 5.0) and not h.has_shield)

	var sc := PlayerHealth.new()
	add_child(sc)
	sc.grant_second_chance()
	sc.apply_damage(5.0, "trap")
	_check("Second Chance leaves half a heart instead of eliminating",
		is_equal_approx(sc.hearts, 0.5) and not sc.is_eliminated)
	sc._process(5.0)
	sc.apply_damage(5.0, "trap")
	_check("Second Chance works at most once", sc.is_eliminated)
	sc.grant_second_chance()
	sc.refill(3.0)
	_check("neither a refill nor Second Chance resurrects", sc.is_eliminated and is_equal_approx(sc.hearts, 0.0))

	var online := PlayerHealth.new()
	add_child(online)
	online.net_client = true
	_check("an online client's hazards cannot take hearts", not online.apply_damage(1.0, "fire_2"))
	online.net_apply(3.0, false, false, false)
	_check("the server's hearts are applied", is_equal_approx(online.hearts, 3.0))
	for n: Node in [h, drain, sc, online]:
		n.queue_free()


# --- Helpers ------------------------------------------------------------------

func _make_match(count: int) -> Dictionary:
	var finish := Area3D.new()
	finish.add_to_group("finish_area")
	add_child(finish)

	var mc := MatchController.new()
	add_child(mc)
	# Drive _process by hand so the tests control time exactly.
	mc.set_process(false)

	var racers: Array = []
	for i in count:
		var racer := FakeRacer.new()
		racer.name = "R%d" % i
		add_child(racer)
		racers.append(racer)
		mc.register_racer(racer, "R%d" % i)

	mc.begin_countdown()
	return {"match": mc, "racers": racers, "finish": finish}


## Steps the match in 1/60 s slices so per-frame logic behaves as it would in play.
func _advance(mc: MatchController, seconds: float) -> void:
	var step := 1.0 / 60.0
	var remaining := seconds
	while remaining > 0.0:
		mc._process(minf(step, remaining))
		remaining -= step


func _teardown(ctx: Dictionary) -> void:
	ctx["match"].queue_free()
	ctx["finish"].queue_free()
	for racer: Node in ctx["racers"]:
		racer.queue_free()


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
