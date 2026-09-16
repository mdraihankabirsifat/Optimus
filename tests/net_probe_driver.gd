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

	if role == "guest":
		# Drop out mid-race without a goodbye; the server must cope.
		await _until(func() -> bool: return m.mc.elapsed >= 9.0, 10.0)
		obs["quit_mid_race"] = true
		_write()
		get_tree().quit(0)
		return

	var finish := WorldScope.first(world, "finish_area") as Area3D
	await _until(func() -> bool: return m.mc.elapsed >= 8.0, 10.0)
	me.global_position = finish.global_position
	NetManager.send_to_server("c_test_teleport", [finish.global_position])
	await _until(func() -> bool: return bool(m.mc.racers[m.local_rid]["finished"]), 8.0)
	obs["my_place"] = int(m.mc.racers[m.local_rid]["place"])

	var guest_gone := func() -> bool:
		return String(m.mc.racers[other_rid]["name"]).ends_with("(bot)") \
			or bool(m.mc.racers[other_rid]["disconnected"])
	await _until(guest_gone, 15.0)
	obs["guest_after_drop"] = String(m.mc.racers[other_rid]["name"])
	obs["guest_disconnected_flag"] = bool(m.mc.racers[other_rid]["disconnected"])

	# Every human is done: the server ends the race after the grace period.
	var have_results := func() -> bool:
		return GameState.last_results_online and not GameState.last_results.is_empty()
	var results_seen: bool = await _until(have_results, AppConfig.LOCAL_RESOLVED_GRACE + 15.0)
	obs["results_received"] = results_seen
	if results_seen:
		var names: Array = []
		for entry: Dictionary in GameState.last_results:
			names.append(entry["name"])
		obs["results_order"] = names
		obs["results_first_place"] = GameState.last_results[0]["name"]
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
