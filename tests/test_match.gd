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
	_section("time limit")
	var ctx := _make_match(1)
	var mc: MatchController = ctx["match"]
	_advance(mc, 3.1)
	_advance(mc, AppConfig.MATCH_TIME_LIMIT + 1.0)
	_check("match ends when the clock expires", mc.phase == MatchController.Phase.ENDED)

	var results := mc.build_results()
	_check("unresolved racer is recorded as DNF",
		not results[0]["finished"] and not results[0]["eliminated"])
	_teardown(ctx)


func _test_format_time() -> void:
	_section("time formatting")
	_check("under a minute", MatchController.format_time(9.5) == "0:09.50")
	_check("over a minute", MatchController.format_time(75.25) == "1:15.25")


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
