extends Node
## A scripted player for tests/test_net.gd. Runs a real game client in its own process: it
## connects over WebSocket, uses the lobby, loads the race through the normal scenes, and
## plays by calling the same functions the keyboard would. It writes what it observed to a
## JSON file for the orchestrator to judge.
##
## Lives under the tree root rather than as the current scene, because starting a race
## changes scene and would otherwise free it mid-test.

var role := "host"
var port := 8931
var out_path := ""
var code_path := ""
var obs := {}
var _states: Array[String] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"role": role = kv[1]
			"port": port = int(kv[1])
			"out": out_path = kv[1]
			"codefile": code_path = kv[1]
	NetManager.state_changed.connect(func(_s: int) -> void: _states.append(NetManager.state_name()))
	_run()


func _run() -> void:
	NetManager.connect_to_server("ws://127.0.0.1:%d" % port, "Host" if role == "host" else "Guest")
	if not await _until(func() -> bool: return NetManager.is_online(), 20.0):
		_finish("never connected: " + NetManager.last_error)
		return
	obs["connected"] = true

	if role == "host":
		NetManager.create_room("mixed")
		if not await _until(func() -> bool: return NetManager.in_room(), 10.0):
			_finish("room was never created")
			return
		var f := FileAccess.open(code_path, FileAccess.WRITE)
		f.store_string(String(NetManager.lobby["code"]))
		f.close()
		obs["room_code"] = NetManager.lobby["code"]
		NetManager.host_action("slots", 4)
		if not await _until(func() -> bool: return _humans() == 2, 30.0):
			_finish("guest never joined")
			return
		NetManager.host_action("fill_bots")
		NetManager.host_action("seed", 4242)
		var startable := func() -> bool:
			return String(NetManager.lobby.get("start_problem", "x")) == "" \
				and (NetManager.lobby["slots"] as Array).size() == 4
		if not await _until(startable, 30.0):
			_finish("lobby never became startable: %s" % NetManager.lobby.get("start_problem", ""))
			return
		obs["lobby_before_start"] = NetManager.lobby.duplicate(true)
		NetManager.start_race()
	else:
		if not await _until(func() -> bool: return FileAccess.file_exists(code_path), 30.0):
			_finish("no room code to join")
			return
		var code := FileAccess.get_file_as_string(code_path).strip_edges()
		NetManager.join_room(code)
		if not await _until(func() -> bool: return NetManager.in_room(), 10.0):
			_finish("could not join room " + code)
			return
		obs["joined"] = code
		NetManager.set_ready(true)

	if not await _until(func() -> bool: return _match() != null and _match().mc.phase == MatchController.Phase.RACING, 40.0):
		_finish("race never reached GO")
		return
	var m := _match()
	var world := m.world
	var me := m.racers[m.local_rid]
	var other_rid := 1 if m.local_rid == 0 else 0
	var other := m.racers[other_rid]
	obs["local_rid"] = m.local_rid
	obs["racer_count"] = m.racers.size()
	obs["graph_hash_matches"] = (world.get("graph") as CaveGraph).graph_hash() == int(GameState.net_config["graph_hash"])
	obs["graph_hash"] = (world.get("graph") as CaveGraph).graph_hash()
	var bots := 0
	for r: Dictionary in m.mc.racers:
		if r["is_bot"]:
			bots += 1
	obs["bots"] = bots

	# Independent gravity: the host turns, the guest must see it and stay unturned.
	if role == "host":
		me.gravity.request_shift(Vector3.RIGHT)
		await get_tree().create_timer(1.5).timeout
		obs["my_gravity_after_shift"] = NetMatch.dir_index(me.gravity.gravity_dir)
		obs["my_charges_after_shift"] = me.gravity.charges
	else:
		await get_tree().create_timer(2.5).timeout
		obs["host_gravity_seen"] = NetMatch.dir_index(other.gravity.gravity_dir)
		obs["my_gravity"] = NetMatch.dir_index(me.gravity.gravity_dir)
		obs["my_charges"] = me.gravity.charges
		obs["host_charges_seen"] = other.gravity.charges

	# Both racers reach for the same box at the same race time.
	var box: MysteryBox = null
	var lowest := 1 << 30
	for n in WorldScope.nodes(world, "mystery_boxes"):
		var candidate := n as MysteryBox
		if candidate.box_index < lowest:
			lowest = candidate.box_index
			box = candidate
	var opener := {"rid": -1, "count": 0}
	box.opened.connect(func(r: PlayerController, _reward: String, _d: String) -> void:
		opener["rid"] = m.racers.find(r)
		opener["count"] = int(opener["count"]) + 1)
	await _until(func() -> bool: return m.mc.elapsed >= 5.0, 20.0)
	var spot := box.global_position + Vector3(0.0, 1.2, 0.8 if role == "host" else -0.8)
	me.global_position = spot
	NetManager.send_to_server("c_test_teleport", [spot])
	await get_tree().create_timer(0.3).timeout
	await _until(func() -> bool: return m.mc.elapsed >= 6.0, 5.0)
	box.interact(me)
	await get_tree().create_timer(1.5).timeout
	obs["box_open"] = box.is_open
	obs["box_opener_rid"] = opener["rid"]
	obs["box_open_events"] = opener["count"]

	# Prompt 2: the host reaches the exit first and waits as Qualified 1st; the guest follows,
	# which starts the Freedom Duel. Both fire over the network, then the guest drops mid-duel
	# and a bot takes its finalist over.
	var duel: FreedomDuel = world.get("duel")
	var finish := WorldScope.first(world, "finish_area") as Area3D
	var shots_by := {"me": 0, "other": 0, "hits_on_other": 0}
	duel.shot.connect(func(sh: PlayerController, _k: String, _f: Vector3, _t: Vector3, hit: PlayerController) -> void:
		if sh == me:
			shots_by["me"] += 1
		elif sh == other:
			shots_by["other"] += 1
		if hit == other:
			shots_by["hits_on_other"] += 1)
	await _until(func() -> bool: return m.mc.elapsed >= (8.0 if role == "host" else 10.0), 12.0)
	me.global_position = finish.global_position
	NetManager.send_to_server("c_test_teleport", [finish.global_position])
	await _until(func() -> bool: return bool(m.mc.racers[m.local_rid]["finished"]), 8.0)
	obs["my_place"] = int(m.mc.racers[m.local_rid]["place"])

	if role == "host":
		obs["qualified_1st"] = await _until(func() -> bool:
			return duel.finalist_a == me and duel.phase >= FreedomDuel.Phase.WAITING, 5.0)
		await get_tree().create_timer(1.0).timeout
		obs["waiting_in_arena"] = DuelArena.contains(me.global_position) and duel.phase == FreedomDuel.Phase.WAITING
	else:
		obs["qualified_2nd"] = await _until(func() -> bool: return duel.finalist_b == me, 8.0)

	obs["fight_seen"] = await _until(func() -> bool: return duel.phase == FreedomDuel.Phase.FIGHT, 20.0)
	await get_tree().create_timer(0.5).timeout
	obs["in_arena"] = DuelArena.contains(me.global_position)
	obs["my_duel_dof"] = me.duel_dof
	obs["other_duel_dof"] = duel.shown_dof(other)
	obs["my_hearts_at_fight"] = me.health.hearts

	if role == "guest":
		# Fire a burst at the host through the real network path, then vanish.
		for i in 8:
			var eye := me.head.global_position
			m.send_duel_fire("pulse", eye, (other.global_position - eye).normalized())
			await get_tree().create_timer(AppConfig.PULSE_COOLDOWN + 0.15).timeout
		await get_tree().create_timer(1.0).timeout
		obs["my_shots_confirmed"] = shots_by["me"]
		obs["hits_on_host"] = shots_by["hits_on_other"]
		obs["quit_mid_duel"] = true
		_write()
		get_tree().quit(0)
		return

	var guest_gone := func() -> bool:
		return String(m.mc.racers[other_rid]["name"]).ends_with("(bot)") \
			or bool(m.mc.racers[other_rid]["disconnected"])
	await _until(guest_gone, 25.0)
	obs["guest_after_drop"] = String(m.mc.racers[other_rid]["name"])
	obs["guest_shots_seen"] = shots_by["other"]
	obs["hearts_after_guest_fire"] = me.health.hearts
	obs["duel_still_running_after_drop"] = duel.phase == FreedomDuel.Phase.FIGHT or duel.phase == FreedomDuel.Phase.ENDED

	# Keep shooting at whoever holds the other finalist now, until the duel ends.
	var have_results := func() -> bool:
		return GameState.last_results_online and not GameState.last_results.is_empty()
	var end := Time.get_ticks_msec() + int((AppConfig.DUEL_HARD_LIMIT + 30.0) * 1000.0)
	while Time.get_ticks_msec() < end and not have_results.call():
		if duel.phase == FreedomDuel.Phase.FIGHT and float(duel.fighters.get(me, {}).get("pulse_cd", 0.0)) <= 0.0:
			var eye := me.head.global_position
			m.send_duel_fire("pulse", eye, (other.global_position + Vector3(0, 0.3, 0) - eye).normalized())
			duel.fighters[me]["pulse_cd"] = AppConfig.PULSE_COOLDOWN
		await get_tree().process_frame
	obs["my_shots_confirmed"] = shots_by["me"]
	obs["my_hits"] = shots_by["hits_on_other"]
	var results_seen: bool = have_results.call()
	obs["results_received"] = results_seen
	obs["duel_champion_seen"] = duel.champion.display_name if duel.champion != null else ""
	if results_seen:
		var names: Array = []
		for entry: Dictionary in GameState.last_results:
			names.append(entry["name"])
		obs["results_order"] = names
		obs["results_first_place"] = GameState.last_results[0]["name"]
		obs["results_first_duel_place"] = int(GameState.last_results[0].get("duel_place", 0))
		obs["results_second_duel_place"] = int(GameState.last_results[1].get("duel_place", 0))
	await get_tree().create_timer(RESULTS_WAIT).timeout
	obs["back_in_lobby_after_race"] = NetManager.in_room() and not bool(NetManager.lobby.get("in_match", true))
	obs["still_connected"] = NetManager.is_online()
	_finish("")


const RESULTS_WAIT := 8.0


func _humans() -> int:
	var n := 0
	for s: Dictionary in NetManager.lobby.get("slots", []):
		if not s["is_bot"]:
			n += 1
	return n


func _match() -> NetMatch:
	var m := NetManager.client_match
	return m if m != null and is_instance_valid(m) else null


func _until(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _finish(error: String) -> void:
	obs["error"] = error
	obs["states"] = _states
	_write()
	get_tree().quit(0 if error == "" else 2)


func _write() -> void:
	obs["states"] = _states
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(obs, "  "))
		f.close()
