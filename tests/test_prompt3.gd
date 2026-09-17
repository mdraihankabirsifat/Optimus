extends Node
## Master Prompt 3 regressions with real physics bodies and the real match objects:
## fire contact vs the ceiling bypass, racer-to-racer collision on all six surfaces, spikes.
## Run: godot --headless --fixed-fps 60 res://tests/test_prompt3.tscn

const CARDINALS: Array[Vector3] = [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_fire_ceiling_bypass()
	await _test_racer_collision()
	await _test_spikes()
	await _test_heart_exchange()
	_test_bindings()
	await _test_compass()
	await _test_bot_pit(false)
	await _test_bot_pit(true)
	await _test_bot_zero_moves()

	print("")
	print("==================================================")
	print("  PROMPT 3   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


# --- Helpers ----------------------------------------------------------------------------

## A closed box of world collision: `half` is the clear half-extent on each axis.
func _room(centre: Vector3, half: Vector3) -> StaticBody3D:
	var room := StaticBody3D.new()
	room.collision_layer = CaveBuilder.LAYER_WORLD
	add_child(room)
	for axis: Vector3 in CARDINALS:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var size := (half + Vector3.ONE) * 2.0
		var a := axis.abs()
		size = size - a * size + a * 1.0
		box.size = size
		shape.shape = box
		shape.position = axis * (half.dot(a) + 0.5)
		room.add_child(shape)
	room.global_position = centre
	return room


func _racer() -> PlayerController:
	var racer: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	racer.is_local_player = false
	add_child(racer)
	return racer


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle(racer: PlayerController, pos: Vector3, g: Vector3) -> void:
	racer.global_position = pos
	racer.velocity = Vector3.ZERO
	racer.gravity._align_body_to_gravity(g)
	await _frames(40)


## Walk the racer toward a world point by steering in its own movement frame, like a bot.
func _walk_to(racer: PlayerController, target: Vector3, frames: int) -> void:
	for i in frames:
		var axes := racer.movement_axes()
		var to := target - racer.global_position
		to -= (axes["up"] as Vector3) * to.dot(axes["up"])
		if to.length() < 0.3:
			break
		var d := to.normalized()
		racer.move_input = Vector2(d.dot(axes["right"]), -d.dot(axes["forward"]))
		await get_tree().physics_frame
	racer.move_input = Vector2.ZERO


# --- Request 1: fire --------------------------------------------------------------------

func _test_fire_ceiling_bypass() -> void:
	_section("fire: floor contact burns, the ceiling bypass does not")
	# One real tunnel: 4 units clear, floor at FLOOR_Y, 24 long along Z.
	var centre := Vector3(60, 20, -60)
	var t := CaveBuilder.TUNNEL_HALF
	var room := _room(centre + Vector3(0, 0, 0), Vector3(t, t, 12))
	var cell := Node3D.new()
	add_child(cell)
	cell.global_position = centre
	# Side 0: the patch is pushed to +X, the -X edge is clear.
	var fire := FireHazard.create(7, 0, t)
	cell.add_child(fire)
	await _frames(2)
	var top := fire.global_position.y + fire.flame_height
	var ceiling := centre.y + t
	_check("flame volume leaves a capsule plus margin under a 4-unit tunnel ceiling (top %.2f, ceiling %.2f)" % [top, ceiling],
		ceiling - top >= 1.8 + 0.4)

	var racer := _racer()
	var hurt := [0]
	racer.health.damaged.connect(func(_a: float, s: String) -> void:
		if s.begins_with("fire"):
			hurt[0] += 1)
	var fx := fire.global_position.x
	# Ceiling: one 180 and walk the length of the tunnel straight over the flames.
	await _settle(racer, Vector3(fx, centre.y + 1.0, centre.z - 10), Vector3.UP)
	_check("racer stands on the ceiling", racer.is_on_floor())
	await _walk_to(racer, Vector3(fx, racer.global_position.y, centre.z + 10), 240)
	_check("walked over the fire on the ceiling", racer.global_position.z > centre.z + 8)
	_check("the ceiling bypass takes no fire damage", hurt[0] == 0 and is_equal_approx(racer.health.hearts, 5.0))

	# Wall on the clear side: walk past, outside the volume.
	await _settle(racer, Vector3(centre.x - t + 1.0, centre.y, centre.z + 10), Vector3.LEFT)
	_check("racer stands on the clear-side wall", racer.is_on_floor())
	await _walk_to(racer, Vector3(racer.global_position.x, centre.y, centre.z - 10), 240)
	_check("walked past the fire along the clear wall", racer.global_position.z < centre.z - 8)
	_check("wall traversal outside the flames is safe", hurt[0] == 0)

	# Floor: straight through the patch.
	await _settle(racer, Vector3(fx, centre.y - 1.0, centre.z - 10), Vector3.DOWN)
	await _walk_to(racer, Vector3(fx, racer.global_position.y, centre.z), 200)
	await _frames(10)
	_check("floor contact burns", hurt[0] >= 1 and racer.health.hearts < 5.0)
	var hearts := racer.health.hearts
	await _frames(20)
	_check("the tick cooldown holds (no burn every frame)", racer.health.hearts >= hearts - AppConfig.DAMAGE_FIRE)
	await _walk_to(racer, Vector3(fx, racer.global_position.y, centre.z + 10), 200)
	hearts = racer.health.hearts
	await _frames(150)
	_check("leaving the flames stops the damage", is_equal_approx(racer.health.hearts, hearts))
	_check("the burn left the racer alive", not racer.health.is_eliminated)

	racer.queue_free()
	cell.queue_free()
	room.queue_free()
	await _frames(2)


# --- Request 8: racers ------------------------------------------------------------------

func _test_racer_collision() -> void:
	_section("racers collide with each other on every surface")
	var centre := Vector3(-60, 20, 60)
	var room := _room(centre, Vector3(6, 6, 6))
	var a := _racer()
	var b := _racer()
	for g: Vector3 in CARDINALS:
		var up := -g
		var side := Vector3.RIGHT if absf(up.x) < 0.5 else Vector3.BACK
		var floor_point := centre - up * 5.0
		await _settle(a, floor_point - side * 3.0, g)
		await _settle(b, floor_point + side * 0.0, g)
		await _walk_to(a, floor_point + side * 3.0, 150)
		var gap := a.global_position.distance_to(b.global_position)
		_check("%s gravity: a walking racer cannot pass through a standing one (gap %.2f)" % [_name(g), gap],
			gap > 0.7 and (a.global_position - floor_point).dot(side) < 0.0)
	# Merged start: two racers placed inside each other push apart.
	await _settle(a, centre - Vector3(0, 5, 0), Vector3.DOWN)
	b.gravity._align_body_to_gravity(Vector3.DOWN)
	b.global_position = a.global_position + Vector3(0.3, 0, 0)
	await _frames(30)
	_check("overlapping racers separate (gap %.2f)" % a.global_position.distance_to(b.global_position),
		a.global_position.distance_to(b.global_position) > 0.6)
	# A finished or eliminated racer no longer blocks.
	b.set_solid(false)
	await _settle(b, centre - Vector3(0, 5, 0), Vector3.DOWN)
	await _settle(a, centre - Vector3(3, 5, 0), Vector3.DOWN)
	await _walk_to(a, centre - Vector3(-3, 5, 0), 150)
	_check("a non-solid (finished/eliminated) racer is walked through", a.global_position.x > centre.x + 2.0)
	a.queue_free()
	b.queue_free()
	room.queue_free()
	await _frames(2)


# --- Request 8: spikes ------------------------------------------------------------------

func _test_spikes() -> void:
	_section("spikes block and hurt once per cooldown")
	var centre := Vector3(-60, 20, -60)
	var room := _room(centre, Vector3(6, 6, 6))
	var spike := SpikeHazard.create(3, 2.0, 0.5, false)
	add_child(spike)
	spike.global_position = centre - Vector3(0, 6, 0)
	var racer := _racer()
	var hits := [0]
	racer.health.damaged.connect(func(_a: float, s: String) -> void:
		if s.begins_with("spike"):
			hits[0] += 1)
	await _settle(racer, centre + Vector3(-4, -5, 0), Vector3.DOWN)
	# Sprint straight into it.
	racer.sprint_input = true
	await _walk_to(racer, centre + Vector3(4, -5, 0), 90)
	racer.sprint_input = false
	_check("a sprinting racer does not pass through a spike (x %.2f)" % (racer.global_position.x - centre.x),
		racer.global_position.x < centre.x - 0.4)
	_check("touching a spike hurts", hits[0] >= 1)
	_check("once per cooldown, not every frame", hits[0] <= 1)
	var crystal := CaveBuilder.new()._solid_box(Vector3(0.95, 1.45, 0.6), Vector3(0, 0.72, 0.1))
	add_child(crystal)
	crystal.global_position = centre + Vector3(0, -6, 4)
	await _settle(racer, centre + Vector3(0, -5, 1), Vector3.DOWN)
	await _walk_to(racer, centre + Vector3(0, -5, 6), 90)
	_check("a crystal cluster blocks like it looks", racer.global_position.z < centre.z + 3.8)
	racer.queue_free()
	spike.queue_free()
	crystal.queue_free()
	room.queue_free()
	await _frames(2)


# --- Request 4: hearts for Moves --------------------------------------------------------

func _race_world(regen: bool = false) -> Node3D:
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = 4242
	world.bot_count = 2
	add_child(world)
	await get_tree().process_frame
	world.set("_move_regen", regen)
	for b: Node3D in world.bots:
		b.get_node("BotController").set_physics_process(false)
	return world


func _test_heart_exchange() -> void:
	_section("trading hearts for Moves")
	var world: Node3D = await _race_world()
	var mc: MatchController = world.match_controller
	var me: PlayerController = world.local_player()
	me.set_physics_process(false)
	_check("no trade during the countdown", world.request_heart_exchange(me) != "" and is_equal_approx(me.health.hearts, 5.0))
	mc._advance_countdown(10.0)
	var start_moves := me.gravity.charges
	_check("a trade succeeds while racing", world.request_heart_exchange(me) == "")
	_check("one full heart for exactly one Move", is_equal_approx(me.health.hearts, 4.0) and me.gravity.charges == start_moves + 1)
	me.gravity.charges = AppConfig.MOVE_CHARGES_MAX
	_check("rejected at the Move cap, nothing taken", world.request_heart_exchange(me) != "" and is_equal_approx(me.health.hearts, 4.0))
	me.gravity.charges = 0
	me.health.hearts = 0.5
	_check("half a heart cannot be traded", world.request_heart_exchange(me) != "" and me.gravity.charges == 0)
	me.health.hearts = 1.5
	world.request_heart_exchange(me)
	_check("1.5 hearts -> 0.5 and a Move, no deadline", is_equal_approx(me.health.hearts, 0.5) and me.gravity.charges == 1 and not me.health.in_grace())
	me.health.grant_shield()
	me.health.hearts = 1.0
	var eliminations := [0]
	me.health.eliminated.connect(func() -> void: eliminations[0] += 1)
	_check("the last heart can be traded", world.request_heart_exchange(me) == "")
	_check("the last heart still grants the Move", me.gravity.charges == 2)
	_check("trading the last heart does not eliminate", not me.health.is_eliminated and me.input_enabled)
	_check("the 20 second deadline starts", is_equal_approx(me.health.grace_left, AppConfig.LAST_HEART_GRACE))
	_check("a shield does not make the trade free", me.health.has_shield and is_equal_approx(me.health.hearts, 0.0))
	me.health._process(5.0)
	me.gravity.add_charges(1)
	me.health.refill(1.0)
	_check("a Heart Refill does not cancel the deadline", is_equal_approx(me.health.grace_left, 15.0) and is_equal_approx(me.health.hearts, 1.0))
	world.request_heart_exchange(me)
	_check("trading again does not reset or extend the deadline", is_equal_approx(me.health.grace_left, 15.0))
	me.health._process(14.9)
	_check("still alive just before the deadline", not me.health.is_eliminated)
	me.health._process(0.2)
	_check("eliminated once at the deadline", me.health.is_eliminated and eliminations[0] == 1)
	me.health._process(5.0)
	_check("the deadline never fires twice", eliminations[0] == 1)
	_check("an eliminated racer cannot trade", world.request_heart_exchange(me) != "")

	var bot := world.bots[0] as PlayerController
	bot.health.hearts = 1.0
	bot.gravity.charges = 0
	_check("bots use the same trade", world.request_heart_exchange(bot) == "" and bot.health.in_grace())
	mc._on_finish_body_entered(bot)
	_check("qualifying clears the cave deadline", not bot.health.in_grace())
	bot.health._process(30.0)
	_check("a qualified racer is never killed by an old deadline", not bot.health.is_eliminated)

	var other := world.bots[1] as PlayerController
	other.health.hearts = 1.0
	world.request_heart_exchange(other)
	other.health.apply_damage(0.5, "fire_test")
	_check("a real hit at zero hearts during the deadline still eliminates", other.health.is_eliminated)
	world.queue_free()
	await _frames(2)

	var regen_world: Node3D = await _race_world(true)
	(regen_world.match_controller as MatchController)._advance_countdown(10.0)
	var r: PlayerController = regen_world.local_player()
	r.set_physics_process(false)
	_check("with Move regen on, trading is off", regen_world.request_heart_exchange(r) != ""
		and is_equal_approx(r.health.hearts, 5.0) and not r.health.in_grace())
	regen_world.queue_free()
	await _frames(2)


# --- Request 5: bindings ---------------------------------------------------------------

func _test_bindings() -> void:
	_section("every hint follows remapping")
	var box := MysteryBox.new()
	_check("default box hint names the default key", box.prompt_text().contains("[E]"))
	SettingsManager.remap_action("interact", KEY_R)
	_check("E -> R: the box hint says R at once", box.prompt_text().contains("[R]") and not box.prompt_text().contains("[E]"))
	_check("R is the interact binding and E is not", UiKit.binding_text("interact") == "R")
	var before_map := UiKit.binding_text("toggle_map")
	SettingsManager.remap_action("interact", KEY_M)
	_check("a conflict swaps both hints (interact M, map takes R)", UiKit.binding_text("interact") == "M"
		and UiKit.binding_text("toggle_map") == "R")
	SettingsManager.reset_keys()
	_check("reset restores both hints", UiKit.binding_text("interact") == "E" and UiKit.binding_text("toggle_map") == before_map)
	_check("mouse bindings read as mouse buttons", UiKit.binding_text("duel_fire") == "Left mouse")
	_check("several bindings are all shown", UiKit.binding_text("duel_lock") == "Right mouse / Q")
	_check("the gravity chord uses the same formatter", UiKit.chord_text("gravity_mod", "jump") == "G + Space")
	_check("the new heart-trade action is bound and remappable", UiKit.binding_text("exchange_heart") == "H"
		and "exchange_heart" in SettingsManager.REMAPPABLE)
	_check("loading tips fill in keys", not String(load("res://scripts/ui/loading.gd").fill_keys("{exchange_heart}")).contains("{"))
	box.free()


# --- Request 7: compass -----------------------------------------------------------------

func _test_compass() -> void:
	_section("compass is fixed to the world")
	var cam := Camera3D.new()
	add_child(cam)
	var ok_n := true
	var ok_e := true
	for up: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT]:
		cam.global_basis = Basis.looking_at(Vector3.FORWARD, up)
		ok_n = ok_n and absf(float(RaceHUD.compass_heading(cam, 0.0)["bearing"])) < 0.5
	for up: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		cam.global_basis = Basis.looking_at(Vector3.RIGHT, up)
		ok_e = ok_e and absf(float(RaceHUD.compass_heading(cam, 0.0)["bearing"]) - 90.0) < 0.5
	_check("facing world -Z reads N however the camera is rolled (floor, ceiling, walls)", ok_n)
	_check("facing world +X reads E however the camera is rolled", ok_e)
	cam.global_basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)
	var up_view := RaceHUD.compass_heading(cam, 123.0)
	_check("looking straight up keeps the last bearing and says so", is_equal_approx(float(up_view["bearing"]), 123.0) and up_view["vertical"] == "up")
	cam.global_basis = Basis.looking_at(Vector3(0.05, -1, 0).normalized(), Vector3.FORWARD)
	_check("nearly straight down is stable too", RaceHUD.compass_heading(cam, 45.0)["vertical"] == "down")
	_check("bearing names", RaceHUD.bearing_name(0.0) == "N" and RaceHUD.bearing_name(92.0) == "E" and RaceHUD.bearing_name(225.0) == "SW")
	cam.queue_free()

	# A real racer through chained gravity shifts, always facing world +X.
	var racer := _racer()
	await _frames(2)
	var all_east := true
	for g: Vector3 in [Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]:
		racer.gravity._align_body_to_gravity(g)
		racer.head.rotation = Vector3.ZERO
		# Yaw about local up until the camera faces world +X.
		for i in 72:
			if (-racer.camera.global_basis.z).dot(Vector3.RIGHT) > 0.999:
				break
			racer.rotate_object_local(Vector3.UP, TAU / 72.0)
		var b := float(RaceHUD.compass_heading(racer.camera, 0.0)["bearing"])
		all_east = all_east and absf(b - 90.0) < 6.0
	_check("chained shifts on floor, ceiling and walls never remap east", all_east)
	racer.queue_free()


# --- Request 12: bots escape a ledge with gravity ---------------------------------------

## Stands in for GameWorld: the bot's parent answers "is regen on" and trades hearts with the
## same rules the real world uses.
class BotHost:
	extends Node3D
	var _move_regen := false
	func request_heart_exchange(body: PlayerController) -> String:
		if _move_regen:
			return "off while Move regeneration is on"
		if body.gravity.charges >= AppConfig.MOVE_CHARGES_MAX:
			return "your Moves are full"
		if not body.health.exchange_heart():
			return "you need a full heart"
		body.gravity.add_charges(1)
		return ""


## Three tunnel cells in a row along +X. In the middle one a ledge 1.7 high crosses the whole
## tunnel: too high to jump (a jump clears about 1.3). With `shaft_above` the middle cell has no
## ceiling (a shaft goes up), so the bot must use a side wall instead of the ceiling.
func _pit_world(shaft_above: bool) -> Dictionary:
	var host := BotHost.new()
	add_child(host)
	var g := CaveGraph.new()
	var a := Vector3i(10, 3, 10)
	var b := Vector3i(11, 3, 10)
	var c := Vector3i(12, 3, 10)
	for cell in [a, b, c]:
		g.add_cell(cell)
	g.link(a, b)
	g.link(b, c)
	if shaft_above:
		g.add_cell(Vector3i(11, 4, 10))
		g.link(b, Vector3i(11, 4, 10))
	g.spawn_cell = a
	g.finish_cell = c
	var builder := CaveBuilder.new()
	builder.theme = CaveTheme.by_id("stone_age")
	builder.build(g, host, -1)
	var ledge := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.7, CaveBuilder.TUNNEL_HALF * 2.0)
	shape.shape = box
	ledge.add_child(shape)
	host.add_child(ledge)
	ledge.global_position = CaveBuilder.cell_to_world(b) + Vector3(0, CaveBuilder.FLOOR_Y + 0.85, 0)
	var bot: PlayerController = load("res://scenes/bots/bot_player.tscn").instantiate()
	host.add_child(bot)
	bot.global_position = CaveBuilder.floor_position(a)
	var ctrl: BotController = bot.get_node("BotController")
	ctrl.setup(g, "Pit", Color.ORANGE, 1, 2)
	return {"host": host, "bot": bot, "ctrl": ctrl, "goal_x": ledge.global_position.x + 1.5, "graph": g}


func _test_bot_pit(shaft_above: bool) -> void:
	_section("bot escapes a ledge it cannot jump, using the %s" % ("side wall" if shaft_above else "ceiling"))
	var w := _pit_world(shaft_above)
	var bot: PlayerController = w["bot"]
	var ctrl: BotController = w["ctrl"]
	var shifts := [0]
	bot.gravity.shift_started.connect(func(_d: Vector3) -> void: shifts[0] += 1)
	var start_moves := bot.gravity.charges
	var crossed := false
	for i in 60 * 40:
		await get_tree().physics_frame
		if bot.global_position.x > float(w["goal_x"]):
			crossed = true
			break
	print("    %s after %d frames, shifts %d, moves %d->%d, %s" % ["crossed" if crossed else "stuck", _frames_used(crossed),
		shifts[0], start_moves, bot.gravity.charges, ctrl.debug_state()])
	_check("the bot gets past the ledge (%s)" % ("wall" if shaft_above else "ceiling"), crossed)
	_check("each Move was charged once per real shift", start_moves - bot.gravity.charges == shifts[0])
	_check("no endless flipping (%d shifts)" % shifts[0], shifts[0] <= 3)
	(w["host"] as Node).queue_free()
	await _frames(2)


var _frame_mark := 0
func _frames_used(_crossed: bool) -> int:
	return Engine.get_physics_frames() - _frame_mark


func _test_bot_zero_moves() -> void:
	_section("a trapped bot with no Moves")
	var w := _pit_world(false)
	var bot: PlayerController = w["bot"]
	var ctrl: BotController = w["ctrl"]
	var host: BotHost = w["host"]
	host._move_regen = true
	bot.gravity.charges = 0
	for i in 60 * 14:
		await get_tree().physics_frame
	_check("regen on: it waits for a regenerated Move instead of flailing (%s)" % ctrl.debug_state(),
		ctrl.wait_reason.contains("regenerated") and bot.gravity.charges == 0 and is_equal_approx(bot.health.hearts, 5.0))
	bot.gravity.add_charges(1)
	var crossed := false
	for i in 60 * 25:
		await get_tree().physics_frame
		if bot.global_position.x > float(w["goal_x"]):
			crossed = true
			break
	_check("when the Move arrives it resumes and escapes", crossed)
	host.queue_free()
	await _frames(2)

	w = _pit_world(false)
	bot = w["bot"]
	ctrl = w["ctrl"]
	bot.gravity.charges = 0
	crossed = false
	for i in 60 * 30:
		await get_tree().physics_frame
		if bot.global_position.x > float(w["goal_x"]):
			crossed = true
			break
	_check("regen off: it trades one heart for the Move it needs and escapes", crossed and is_equal_approx(bot.health.hearts, 4.0))
	(w["host"] as Node).queue_free()
	await _frames(2)

	w = _pit_world(false)
	bot = w["bot"]
	ctrl = w["ctrl"]
	bot.gravity.charges = 0
	bot.health.hearts = 1.0
	for i in 60 * 14:
		await get_tree().physics_frame
	_check("on its last heart it will not trade itself into a deadline; it reports being trapped (%s)" % ctrl.debug_state(),
		ctrl.recovery_note.contains("trapped") and not bot.health.in_grace())
	(w["host"] as Node).queue_free()
	await _frames(2)


func _name(g: Vector3) -> String:
	for i in CARDINALS.size():
		if CARDINALS[i].is_equal_approx(g):
			return ["down", "up", "-X", "+X", "-Z", "+Z"][i]
	return str(g)


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
