extends Node
## Master Prompt 4: Battle Timer Mode (spawns, kills, respawns, scoring, expiry, tie-breaks,
## isolation from racing), Sprint Gifts (gating, exact window, refresh, pickup) and the new
## cave floors. Real bodies and the real match objects.
## Run: godot --headless --fixed-fps 60 res://tests/test_prompt4.tscn

const SEED := 4242

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_sprint_gift()
	await _test_battle()
	await _test_battle_ties()
	_test_cave_floors()
	await _test_map_and_clues()
	print("")
	print("==================================================")
	print("  PROMPT 4   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# --- Sprint Gift ------------------------------------------------------------------------

func _test_sprint_gift() -> void:
	_section("Sprint Gift gates Shift")
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, 9.5, 0)
	var racer: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	racer.is_local_player = false
	add_child(racer)
	racer.global_position = Vector3(0, 11, 0)
	await _frames(20)
	racer.move_input = Vector2(0, -1)
	racer.sprint_input = true
	await _frames(60)
	var planar := Vector2(racer.velocity.x, racer.velocity.z).length()
	_check("Shift held with no gift: ordinary walking speed (%.2f)" % planar, absf(planar - AppConfig.WALK_SPEED) < 0.3)
	racer.grant_sprint_gift()
	await _frames(40)
	planar = Vector2(racer.velocity.x, racer.velocity.z).length()
	_check("with a gift, Shift sprints (%.2f)" % planar, planar > AppConfig.WALK_SPEED + 2.0)
	racer.sprint_input = false
	await _frames(30)
	planar = Vector2(racer.velocity.x, racer.velocity.z).length()
	_check("releasing Shift walks while the gift keeps counting", absf(planar - AppConfig.WALK_SPEED) < 0.3 and racer.sprint_gift_left < AppConfig.SPRINT_GIFT_TIME - 1.0)
	var left := racer.sprint_gift_left
	racer.sprint_input = true
	await _frames(6)
	_check("pressing again does not reset the window", racer.sprint_gift_left < left)
	racer.sprint_gift_left = 2.0
	racer.grant_sprint_gift()
	_check("a second gift refreshes to exactly 5 s, never stacks", is_equal_approx(racer.sprint_gift_left, AppConfig.SPRINT_GIFT_TIME))
	racer.sprint_gift_left = 0.05
	await _frames(40)
	planar = Vector2(racer.velocity.x, racer.velocity.z).length()
	_check("at expiry sprint stops even with Shift still held (%.2f)" % planar, racer.sprint_gift_left == 0.0 and not racer.is_sprinting() and absf(planar - AppConfig.WALK_SPEED) < 0.3)

	var gift := SprintGift.create(0, Vector3i.ZERO)
	add_child(gift)
	gift.global_position = racer.global_position
	await _frames(4)
	_check("walking into a gift opens the 5 s window", racer.sprint_gift_left > 4.9 and not gift.available)
	gift._process(AppConfig.SPRINT_GIFT_RESPAWN + 0.1)
	_check("the gift grows back", gift.available)
	racer.queue_free()
	gift.queue_free()
	floor_body.queue_free()
	await _frames(2)


# --- Battle Mode ------------------------------------------------------------------------

func _battle_world(bots: int, seconds: int = 180) -> Node3D:
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = SEED
	world.bot_count = bots
	world.ruleset = AppConfig.RULESET_BATTLE
	world.rush_seconds = seconds
	add_child(world)
	await get_tree().process_frame
	for b: Node3D in world.bots:
		b.get_node("BotController").set_physics_process(false)
	world.local_player().set_physics_process(false)
	return world


## Two racers facing each other in a sealed box far from the cave.
func _face_off(a: PlayerController, b: PlayerController) -> Node3D:
	var room := StaticBody3D.new()
	add_child(room)
	for axis: Vector3 in [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var s := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(30, 30, 30) - axis.abs() * 29.0
		s.shape = bx
		s.position = axis * 12.5
		room.add_child(s)
	room.global_position = Vector3(-120, 60, -120)
	a.global_position = room.global_position + Vector3(0, -10, -6)
	b.global_position = room.global_position + Vector3(0, -10, 6)
	return room


func _test_battle() -> void:
	_section("Battle Mode")
	var world: Node3D = await _battle_world(3)
	var mc: MatchController = world.match_controller
	var battle: BattleMode = world.battle
	_check("Battle Mode built, no Freedom Duel", battle != null and world.duel == null and mc.duel == null)
	_check("the clock is the chosen duration", is_equal_approx(mc.cave_time_limit, 180.0))
	var bodies: Array[PlayerController] = []
	for r: Dictionary in mc.racers:
		bodies.append(r["body"])
	var spread := true
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			spread = spread and bodies[i].global_position.distance_to(bodies[j].global_position) >= 16.0
	_check("everyone starts at a different spawn point, 16+ units apart", spread and battle.spawn_points.size() >= 4)
	mc._advance_countdown(10.0)
	_check("no exit to reach: the finish trigger is off", mc._finish_area == null)
	_check("no heart trade in Battle Mode", world.request_heart_exchange(bodies[0]) != "" and is_equal_approx(bodies[0].health.hearts, 5.0))

	var a := bodies[1]
	var b := bodies[2]
	var room := _face_off(a, b)
	await _frames(3)
	b.health.hearts = 0.5
	var kills := [0]
	battle.killed.connect(func(_k: PlayerController, _v: PlayerController) -> void: kills[0] += 1)
	var eye := a.head.global_position
	_check("a shot fires", battle.fire(a, eye, (b.global_position - eye).normalized()))
	_check("the lethal hit scores exactly one point for the shooter", kills[0] == 1 and int(battle.fighters[a]["score"]) == 1)
	_check("the victim is down, not eliminated from the match", battle.fighters[b]["dead"] and not b.health.is_eliminated
		and not mc.racers[2]["eliminated"] and not b.visible and b.collision_layer == 0)
	battle.fighters[a]["pulse_cd"] = 0.0
	battle.fire(a, eye, (b.global_position - eye).normalized())
	_check("a down racer cannot be killed twice", kills[0] == 1 and int(battle.fighters[a]["score"]) == 1)
	battle._physics_process(AppConfig.BATTLE_RESPAWN_DELAY - 0.1)
	_check("still down just before the respawn delay", battle.fighters[b]["dead"])
	battle._physics_process(0.2)
	_check("respawned after the delay with full hearts and Moves", not battle.fighters[b]["dead"] and is_equal_approx(b.health.hearts, 5.0)
		and b.gravity.charges == AppConfig.MOVE_CHARGES_START and b.visible)
	_check("respawned away from the killer", b.global_position.distance_to(a.global_position) >= BattleMode.KILLER_CLEARANCE)
	_check("spawn protection holds damage off", not b.health.apply_damage(1.0, "fire") and is_equal_approx(b.health.hearts, 5.0))
	battle._physics_process(AppConfig.BATTLE_SPAWN_PROTECTION + 0.1)
	_check("protection ends", b.health.apply_damage(0.5, "probe"))

	var c := bodies[3]
	var before_scores := 0
	for body: PlayerController in battle.fighters:
		before_scores += int(battle.fighters[body]["score"])
	c.health.apply_damage(10.0, "fire")
	var after_scores := 0
	for body: PlayerController in battle.fighters:
		after_scores += int(battle.fighters[body]["score"])
	_check("a death to the cave scores nobody and counts a death", battle.fighters[c]["dead"] and int(battle.fighters[c]["deaths"]) == 1 and after_scores == before_scores)

	# A kill in the same frame the clock runs out: physics (the kill) runs before the clock.
	battle._physics_process(AppConfig.BATTLE_RESPAWN_DELAY + 0.1)
	_face_off(a, b).queue_free()
	await _frames(3)
	a.global_position = room.global_position + Vector3(0, -10, -6)
	b.global_position = room.global_position + Vector3(0, -10, 6)
	b.health.set_damage_enabled(true)
	battle.fighters[b]["protect_left"] = 0.0
	await _frames(3)
	b.health.hearts = 0.5
	b.health.is_invulnerable = false
	battle.fighters[a]["pulse_cd"] = 0.0
	mc.elapsed = mc.cave_time_limit - 0.001
	eye = a.head.global_position
	battle.fire(a, eye, (b.global_position - eye).normalized())
	mc._process(0.01)
	_check("a kill landing as time runs out counts, then the match ends once", int(battle.fighters[a]["score"]) == 2 and mc.phase == MatchController.Phase.ENDED and battle.over)
	var results := mc.build_results()
	_check("results rank the top scorer first and mark a Battle winner", results[0]["body"] == a and bool(results[0].get("battle_winner", false)))
	_check("no Champion, no qualification in a Battle result", int(results[0].get("duel_place", 0)) == 0 and int(results[0].get("qualified", 0)) == 0)
	battle.fighters[a]["pulse_cd"] = 0.0
	_check("no shots after time", not battle.fire(a, eye, Vector3.FORWARD))
	room.queue_free()
	world.queue_free()
	await _frames(3)


func _test_battle_ties() -> void:
	_section("Battle Mode tie-breaks and isolation")
	var world: Node3D = await _battle_world(2)
	var battle: BattleMode = world.battle
	var mc: MatchController = world.match_controller
	var r0: PlayerController = mc.racers[0]["body"]
	var r1: PlayerController = mc.racers[1]["body"]
	var r2: PlayerController = mc.racers[2]["body"]
	battle.fighters[r1]["score"] = 3
	battle.fighters[r1]["deaths"] = 2
	battle.fighters[r1]["reached_at"] = 50.0
	battle.fighters[r2]["score"] = 3
	battle.fighters[r2]["deaths"] = 1
	battle.fighters[r2]["reached_at"] = 90.0
	var ranking := battle.build_ranking()
	_check("tied score: fewer deaths wins", ranking[0]["body"] == r2)
	battle.fighters[r2]["deaths"] = 2
	ranking = battle.build_ranking()
	_check("tied score and deaths: first to reach the score wins", ranking[0]["body"] == r1 and not battle.is_draw(ranking))
	battle.fighters[r2]["reached_at"] = 50.0
	ranking = battle.build_ranking()
	_check("identical on everything: a declared draw", battle.is_draw(ranking))
	_check("a second Battle world keeps its own scores", battle.fighters[r0]["score"] == 0)
	var other: Node3D = await _battle_world(1)
	_check("two Battle worlds share no fighters", (other.battle as BattleMode).fighters.keys().all(func(k: Variant) -> bool: return not battle.fighters.has(k)))
	world.queue_free()
	other.queue_free()
	await _frames(3)


func _test_cave_floors() -> void:
	_section("cave pacing floors")
	for size_index in CaveGenerator.SIZE_PRESETS.size():
		var gen := CaveGenerator.new()
		gen.configure(size_index, AppConfig.RULESET_NORMAL, AppConfig.RUSH_DEFAULT)
		var ok := true
		var fastest := INF
		var cuts := 0
		for s in 12:
			var g := gen.generate(5000 + s)
			if g == null:
				ok = false
				continue
			var t := CaveGenerator.route_seconds(g, gen.last_min_moves)
			fastest = minf(fastest, t)
			ok = ok and t >= gen.min_route_seconds
			cuts += gen.last_long_cuts
		_check("size %d: every cave's shortest route is at or over its floor (fastest %.0f s >= %.0f s)" % [size_index, fastest, gen.min_route_seconds], ok)
		_check("size %d: long-cut detours are carved (%d over 12 caves)" % [size_index, cuts], cuts > 0)


## The map and the clue: what the judges actually navigate with. The map must never show a room
## nobody has seen, and a clue must say something a person can act on.
func _test_map_and_clues() -> void:
	_section("the map and the clue")
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = SEED
	world.bot_count = 1
	add_child(world)
	await get_tree().process_frame
	var hud: RaceHUD = world.hud
	var graph: CaveGraph = world.graph
	var player: PlayerController = world.local_player()
	player.set_physics_process(false)
	var d := hud._map_data()
	_check("at the start the map holds only the spawn room", int(d["visited"].size()) == 1 and d["visited"].has(graph.spawn_cell))
	_check("the exit is not marked before anyone has seen it", not bool(d["exit_seen"]))
	_check("every opening out of the spawn is marked as a passage not taken", d["frontier"].size() >= 1)
	for cell: Vector3i in d["frontier"]:
		_check("a passage not taken is never drawn as a room you walked (%s)" % cell, not d["visited"].has(cell))
		break

	# Walk into the exit: only then may the map name it.
	world.visited_cells[graph.finish_cell] = true
	player.global_position = CaveBuilder.cell_to_world(graph.finish_cell)
	await get_tree().physics_frame
	d = hud._map_data()
	_check("once you have stood in the exit, the map marks it", bool(d["exit_seen"]))
	_check("the map only ever draws the level you are on", int(hud._level_count(d)) <= int(d["visited"].size()))

	var box := MysteryBox.new()
	box.finish_position = Vector3(0, 0, -80)
	var info := box._coarse_clue(Vector3.ZERO)
	_check("a clue names a compass direction", String(info["compass"]) == "north")
	_check("a clue says roughly how far, in rooms (%s)" % info["distance_text"], int(info["rooms"]) >= 2)
	box.finish_position = Vector3(40, CaveBuilder.CELL_SIZE * 2.0, 40)
	info = box._coarse_clue(Vector3.ZERO)
	_check("a clue counts the levels, not just up or down (%s)" % info["level_text"],
		int(info["vertical"]) == 1 and String(info["level_text"]).contains("2 levels up"))
	_check("a clue never hands over the exit cell", not info.has("cell") and not info.has("path"))
	hud.on_clue(world.local_player(), Vector3(0, 0, -1), 1, 6)
	_check("the clue reaches the HUD and stays long enough to use",
		hud._clue_rooms == 6 and hud._clue_timer > 30.0 and AppConfig.CLUE_TIME >= 30.0)
	_check("clues are common enough to matter", int(AppConfig.LOOT_TABLE["clue"]) >= 10)
	box.free()
	world.queue_free()
	await _frames(2)


func _section(title: String) -> void:
	print("\n-- %s" % title)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
