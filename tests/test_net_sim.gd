extends Node
## NET-003 / NET-005 -- the server's authority and a client's mirror, run in one process
## with real race worlds and no sockets. The handlers under test are exactly the ones the
## network calls; only the transport is skipped. tests/test_net.gd covers the transport.
## Run: godot --headless res://tests/test_net_sim.tscn

const SEED_A := 4242
const SEED_B := 777

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	GameState.net_role = "server"

	print("\n-- two rooms race side by side on one server")
	var room_b := LobbyState.new("BBBB", LobbyState.MODE_MIXED)
	room_b.add_human(201, "Solo")
	room_b.add_bot()
	NetManager._rooms["BBBB"] = room_b
	var room_a := LobbyState.new("AAAA", LobbyState.MODE_ONLINE)
	room_a.add_human(101, "Ana")
	room_a.add_human(102, "Ben")
	room_a.set_mode(LobbyState.MODE_MIXED)
	room_a.replace_disconnected_with_bot = false
	room_a.set_total_slots(4)
	room_a.fill_with_bots()
	NetManager._rooms["AAAA"] = room_a

	var a := _server_world("AAAA", SEED_A, room_a.roster())
	var b := _server_world("BBBB", SEED_B, room_b.roster())
	var ma: NetMatch = a.get("net_match")
	var mb: NetMatch = b.get("net_match")
	var mca: MatchController = a.get("match_controller")
	_check(ma != null and mb != null, "both server races built a NetMatch")
	_check(ma.racers.size() == 4 and mb.racers.size() == 2, "2 humans + 2 bots, and 1 human + 1 bot")
	_check(ma.racers[0].net_puppet and ma.racers[1].net_puppet, "humans are puppets on the server")
	_check(not ma.racers[2].net_puppet and ma.racers[2].has_node("BotController"), "bots are simulated on the server")
	_check(a.get("_player") == null, "a server race has no local player")

	var gen := CaveGenerator.new()
	gen.apply_size_preset(1)
	var fresh := gen.generate(SEED_A)
	_check(fresh.graph_hash() == (a.get("graph") as CaveGraph).graph_hash(),
		"server cave hash equals a client's freshly generated cave for the same seed")

	var boxes_a := WorldScope.nodes(ma.racers[2], "mystery_boxes")
	var own := true
	for n in boxes_a:
		own = own and a.is_ancestor_of(n)
	_check(not boxes_a.is_empty() and own, "a bot only ever finds boxes in its own room")
	var spiders_scope := true
	for n in WorldScope.nodes(mb.racers[1], "racers"):
		spiders_scope = spiders_scope and b.is_ancestor_of(n)
	_check(spiders_scope, "hazards only see racers in their own room")

	print("-- countdown waits for clients, then runs on the server clock")
	await get_tree().create_timer(0.5).timeout
	_check(mca.phase == MatchController.Phase.PENDING, "no countdown before clients load")
	ma.server_on_loaded(101, fresh.graph_hash())
	ma.server_on_loaded(102, fresh.graph_hash())
	mb.server_on_loaded(201, (b.get("graph") as CaveGraph).graph_hash())
	await get_tree().process_frame
	await get_tree().process_frame
	_check(mca.phase == MatchController.Phase.COUNTDOWN, "countdown starts once every client has loaded")
	ma.server_on_shift(101, CaveGraph.DIR_PLUS_X)
	_check(ma.racers[0].gravity.charges == 5, "no shift is accepted before GO")
	await get_tree().create_timer(AppConfig.MATCH_COUNTDOWN_SECONDS + 0.4).timeout
	_check(mca.phase == MatchController.Phase.RACING, "GO")

	print("-- Gravity Moves: validated and deducted exactly once, per racer")
	var ana := ma.racers[0]
	var ben := ma.racers[1]
	ma.server_on_shift(101, CaveGraph.DIR_PLUS_X)
	_check(ana.gravity.gravity_dir.is_equal_approx(Vector3.RIGHT) and ana.gravity.charges == 4,
		"Ana's 90-degree shift: gravity +X, 4 Moves left")
	_check(ben.gravity.gravity_dir.is_equal_approx(Vector3.DOWN) and ben.gravity.charges == 5,
		"Ben's gravity and Moves are untouched")
	ma.server_on_shift(101, CaveGraph.DIR_PLUS_X)
	_check(ana.gravity.charges == 4, "same direction again is refused without a charge")
	ma.server_on_shift(101, 9)
	_check(ana.gravity.charges == 4, "an invalid direction index is ignored")
	var dirs := [CaveGraph.DIR_MINUS_X, CaveGraph.DIR_UP, CaveGraph.DIR_DOWN, CaveGraph.DIR_PLUS_Z]
	for d: int in dirs:
		await get_tree().create_timer(AppConfig.GRAVITY_TRANSITION_TIME + 0.05).timeout
		ma.server_on_shift(101, d)
	_check(ana.gravity.charges == 0, "four more shifts spend the rest")
	await get_tree().create_timer(AppConfig.GRAVITY_TRANSITION_TIME + 0.05).timeout
	var before := ana.gravity.gravity_dir
	ma.server_on_shift(101, CaveGraph.DIR_MINUS_Z)
	_check(ana.gravity.charges == 0 and ana.gravity.gravity_dir.is_equal_approx(before), "zero Moves: shift rejected")
	ma.server_on_shift(999, CaveGraph.DIR_UP)
	_check(ben.gravity.charges == 5, "a peer not in this race cannot shift anyone")

	print("-- mystery box contention resolves once")
	var box: MysteryBox = null
	for n in boxes_a:
		box = n as MysteryBox
		break
	var opens: Array = []
	box.opened.connect(func(r: PlayerController, reward: String, _d: String) -> void: opens.append([r, reward]))
	ma.server_on_interact(101, box.box_index)
	_check(opens.is_empty(), "too far away: the request is refused")
	var near := box.global_position + Vector3(0.0, 1.0, 1.0)
	ma.server_on_test_teleport(101, near)
	ma.server_on_test_teleport(102, near + Vector3(0.5, 0.0, 0.0))
	await get_tree().physics_frame
	ma.server_on_interact(102, box.box_index)
	ma.server_on_interact(101, box.box_index)
	_check(opens.size() == 1 and opens[0][0] == ben, "two racers, one box: exactly one opener, the first request")
	_check(box.is_open, "box stays open")

	print("-- damage and falls are the server's")
	var hearts := ben.health.hearts
	ma.server_on_fell(102, false)
	ma.server_on_fell(102, false)
	_check(is_equal_approx(ben.health.hearts, hearts - AppConfig.DAMAGE_VACUUM_FALL),
		"two fall reports inside the mercy window cost one heart, once")
	_check(not ben.health.is_eliminated, "a recoverable fall never eliminates")

	print("-- implausible movement is corrected, not accepted")
	# The teleport and the fall above each opened a short recovery window; let it close.
	await get_tree().create_timer(1.6).timeout
	var held := ben.net_target_position
	ma.server_on_state(102, held, Quaternion.IDENTITY, Vector3.ZERO, 3, 1)
	await get_tree().create_timer(0.1).timeout
	ma.server_on_state(102, held + Vector3(0.0, 0.0, 120.0), Quaternion.IDENTITY, Vector3.ZERO, 3, 1)
	_check(ben.net_target_position.is_equal_approx(held), "a 120-unit jump in 0.1 s is rejected")
	ma.server_on_state(102, held + Vector3(0.3, 0.0, 0.0), Quaternion.IDENTITY, Vector3.ZERO, 3, 1)
	_check(ben.net_target_position.is_equal_approx(held + Vector3(0.3, 0.0, 0.0)), "a small step is accepted")
	ma.server_on_state(102, Vector3(NAN, 0, 0), Quaternion.IDENTITY, Vector3.ZERO, 3, 1)
	_check(ben.net_target_position.is_finite(), "garbage positions are ignored")

	print("-- placements are awarded once, in arrival order")
	var finish := WorldScope.first(a, "finish_area") as Area3D
	var finish_pos := finish.global_position
	ma.server_on_test_teleport(101, finish_pos)
	await _physics(4)
	_check(bool(mca.racers[0]["finished"]) and int(mca.racers[0]["place"]) == 1, "Ana reaches the exit first: 1st")
	ma.server_on_test_teleport(101, finish_pos + Vector3(0, 0, 20))
	await _physics(3)
	ma.server_on_test_teleport(101, finish_pos)
	await _physics(3)
	_check(int(mca.racers[0]["place"]) == 1, "re-entering the exit changes nothing")
	ma.server_on_test_teleport(102, finish_pos)
	await _physics(4)
	_check(int(mca.racers[1]["place"]) == 2, "Ben arrives second: 2nd")

	print("-- disconnects never stall a race")
	mb.server_on_disconnect(201)
	var solo := mb.racers[0]
	_check(not solo.net_puppet and solo.has_node("BotController"), "Mixed Race: a bot takes over the dropped racer")
	_check(String((b.get("match_controller") as MatchController).racers[0]["name"]).ends_with("(bot)"),
		"and races under a (bot) name")
	await _physics(30)
	_check(is_instance_valid(solo) and solo.global_position.is_finite(), "the replacement bot simulates normally")
	room_a.remove_member(102)
	ma.server_on_disconnect(102)
	_check(ma._peer_of_rid.size() == 1, "a finished racer's disconnect is recorded without a crash")

	print("-- results")
	var results_seen: Array = []
	mca.match_ended.connect(func(r: Array) -> void: results_seen.append(r))
	mca.force_end()
	_check(results_seen.size() == 1, "the race ends once")
	var order: Array = results_seen[0] if not results_seen.is_empty() else []
	_check(order.size() == 4 and order[0]["name"] == "Ana" and order[1]["name"] == "Ben",
		"results list finishers first, by place")
	var again := mca.build_results()
	var same := true
	for i in again.size():
		same = same and again[i]["rid"] == order[i]["rid"]
	_check(same, "building results twice gives the same order")

	await _client_mirror()

	GameState.net_role = ""
	NetManager._rooms.clear()
	print("")
	print("==================================================")
	print("  NET SIM   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


## A client's world applies whatever the server says and decides nothing itself.
func _client_mirror() -> void:
	print("-- a client mirrors the server")
	GameState.net_role = "client"
	var room := LobbyState.new("CCCC", LobbyState.MODE_MIXED)
	room.add_human(301, "Me")
	room.add_human(302, "Them")
	room.fill_with_bots()
	var config := {"room": "CCCC", "seed": SEED_A, "cave_size": 1, "bot_skill": 1, "move_regen": false,
		"mode": "mixed", "roster": room.roster(), "local_rid": 0}
	var gen := CaveGenerator.new()
	gen.apply_size_preset(1)
	config["graph_hash"] = gen.generate(SEED_A).graph_hash()

	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.set("net_role", "client")
	world.set("net_config", config)
	add_child(world)
	await get_tree().process_frame
	var m: NetMatch = world.get("net_match")
	var mc: MatchController = world.get("match_controller")
	var me := m.racers[0]
	var them := m.racers[1]
	_check(not me.net_puppet and me.net_client and me.health.net_client, "my racer moves itself, health is the server's")
	_check(them.net_puppet and them.health.net_client, "everyone else is a puppet")
	_check(not them.has_node("BotController") and not m.racers[2].has_node("BotController"),
		"no bot brains run on a client")

	var hearts := me.health.hearts
	_check(not me.health.apply_damage(1.0, "fire_test") and is_equal_approx(me.health.hearts, hearts),
		"a local hazard cannot take a heart")
	await get_tree().create_timer(1.0).timeout
	_check(mc.phase == MatchController.Phase.PENDING, "no countdown until the server sends one")
	m.client_on_countdown(3)
	_check(mc.phase == MatchController.Phase.COUNTDOWN and not me.input_enabled, "countdown freezes input")
	m.client_on_go(0.0)
	_check(mc.phase == MatchController.Phase.RACING and me.input_enabled, "GO from the server")

	m.client_on_snapshot(1.0, 5.0, [[1, them.global_position + Vector3(1, 0, 0), Quaternion.IDENTITY,
		Vector3.ZERO, CaveGraph.DIR_PLUS_X, 1]], [])
	_check(them.gravity.gravity_dir.is_equal_approx(Vector3.RIGHT), "a remote racer's gravity follows the snapshot")
	_check(me.gravity.gravity_dir.is_equal_approx(Vector3.DOWN), "my gravity is untouched by theirs")

	var damaged := []
	me.health.damaged.connect(func(amount: float, _s: String) -> void: damaged.append(amount))
	m.client_on_racer_state(0, hearts - 1.0, 4, 0)
	_check(is_equal_approx(me.health.hearts, hearts - 1.0) and me.gravity.charges == 4, "hearts and Moves from the server")
	_check(damaged.size() == 1, "the damage feedback fires once")

	me.gravity.request_shift(Vector3.RIGHT)
	_check(me.gravity.charges == 3 and me.gravity.is_transitioning, "a local shift is predicted at once")
	m.client_on_shift_denied("no_charges", 0, CaveGraph.DIR_DOWN)
	_check(me.gravity.charges == 0 and me.gravity.gravity_dir.is_equal_approx(Vector3.DOWN) \
		and not me.gravity.is_transitioning, "a server denial snaps the prediction back")

	var box: MysteryBox = null
	for n in WorldScope.nodes(world, "mystery_boxes"):
		box = n as MysteryBox
		break
	var requests := []
	box.open_requested.connect(func(bx: MysteryBox, _r: PlayerController) -> void: requests.append(bx))
	box.interact(me)
	_check(requests.size() == 1 and not box.is_open, "pressing E only asks the server")
	var opened := []
	box.opened.connect(func(_r: PlayerController, reward: String, _d: String) -> void: opened.append(reward))
	m.client_on_box(box.box_index, 1, "heart", "Heart Refill")
	m.client_on_box(box.box_index, 0, "move", "Move Refill")
	_check(box.is_open and opened == ["heart"], "the server's opener is shown, once")

	m.client_on_finished(1, 1, 30.0)
	_check(bool(mc.racers[1]["finished"]) and int(mc.racers[1]["place"]) == 1, "placements come from the server")
	m.client_on_eliminated(2, 31.0, true)
	_check(bool(mc.racers[2]["disconnected"]), "a disconnect is shown as a disconnect")

	var results := [{"rid": 1, "name": "Them", "is_bot": false, "finished": true, "place": 1, "finish_time": 30.0,
		"eliminated": false, "elimination_time": 0.0, "disconnected": false}]
	m.client_on_results(results, {"Them": {"boxes": 1, "moves_used": 2, "damage_taken": 0.0,
		"colour": "ff0000", "is_bot": false}}, 42.0)
	_check(mc.phase == MatchController.Phase.ENDED and GameState.last_results_online, "results end the race")
	_check((GameState.stats["Them"]["colour"] as Color).is_equal_approx(Color.RED), "server stats arrive with colours")
	world.queue_free()
	await get_tree().process_frame


func _server_world(code: String, p_seed: int, roster: Array) -> Node3D:
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.set("net_role", "server")
	world.set("net_config", {"room": code, "seed": p_seed, "cave_size": 1, "bot_skill": 2,
		"move_regen": false, "mode": "mixed", "roster": roster})
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	vp.add_child(world)
	return world


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
