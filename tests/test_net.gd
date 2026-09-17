extends Node
## NET-001..005 -- a real online Mixed Race over WebSockets, three processes on this machine:
##   a headless dedicated server (scenes/net/server.tscn, --test-mode)
##   a host client and a guest client (tests/net_probe.tscn), each a full game
## The host creates a Mixed room, fills it to 2 humans + 2 bots and starts on seed 4242.
## Both clients load the cave through the normal scenes. The host turns its gravity; both
## reach for the same mystery box at the same race time; the host reaches the exit and waits
## as Qualified 1st; the guest follows and the Freedom Duel starts; both fire over the network;
## the guest quits without warning mid-duel, forfeiting (a finalist has already finished the
## cave, so no bot takes it over); the server sends results and returns everyone to the room.
##
## --test-mode only lets the probes teleport, to reach a box and the exit without walking a
## maze. Every rule being tested is the production code path.
## Run: godot --headless res://tests/test_net.tscn

const PORT := 8931
const TIMEOUT := 260.0

var _passed := 0
var _failed := 0
var _pids: Array[int] = []


func _ready() -> void:
	await get_tree().process_frame
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var dir := OS.get_user_data_dir().path_join("net_test")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["host.json", "guest.json", "other.json", "code.txt"]:
		if FileAccess.file_exists(dir.path_join(f)):
			DirAccess.remove_absolute(dir.path_join(f))

	print("\n-- launching server, host and guest")
	_pids.append(OS.create_process(exe, ["--headless", "--path", project, "res://scenes/net/server.tscn",
		"--", "--port=%d" % PORT, "--test-mode"]))
	await get_tree().create_timer(4.0).timeout
	_check(OS.is_process_running(_pids[0]), "dedicated server is running")
	var common := ["--port=%d" % PORT, "--codefile=%s" % dir.path_join("code.txt")]
	_pids.append(OS.create_process(exe, ["--headless", "--path", project, "res://tests/net_probe.tscn", "--",
		"--role=host", "--out=%s" % dir.path_join("host.json")] + common))
	await get_tree().create_timer(2.0).timeout
	_pids.append(OS.create_process(exe, ["--headless", "--path", project, "res://tests/net_probe.tscn", "--",
		"--role=guest", "--out=%s" % dir.path_join("guest.json")] + common))

	_pids.append(OS.create_process(exe, ["--headless", "--path", project, "res://tests/net_probe.tscn", "--",
		"--role=other", "--out=%s" % dir.path_join("other.json")] + common))

	var end := Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < end and not FileAccess.file_exists(dir.path_join("host.json")):
		await get_tree().create_timer(1.0).timeout
	var server_alive := OS.is_process_running(_pids[0])

	var host := _read(dir.path_join("host.json"))
	var guest := _read(dir.path_join("guest.json"))
	var other := _read(dir.path_join("other.json"))

	print("-- connection and lobby")
	_check(host.get("error", "missing") == "", "host completed its script (%s)" % host.get("error", "no output"))
	_check(guest.get("connected", false) and host.get("connected", false), "both clients connected")
	_check("Connecting" in host.get("states", []) and "Connected" in host.get("states", []),
		"client shows Connecting then Connected")
	_check(guest.get("joined", "") == host.get("room_code", "?"), "guest joined the host's room by code")
	var slots: Array = host.get("lobby_before_start", {}).get("slots", [])
	var humans := 0
	var colours := {}
	for s: Dictionary in slots:
		humans += 0 if s["is_bot"] else 1
		colours[s["colour"]] = true
	_check(slots.size() == 4 and humans == 2, "lobby held 2 humans + 2 bots")
	_check(colours.size() == 4, "every racer had a distinct colour")

	print("-- same cave everywhere")
	_check(host.get("graph_hash_matches", false) and guest.get("graph_hash_matches", false),
		"each client's cave hash matches the server's")
	_check(host.get("graph_hash", 0) == guest.get("graph_hash", 1), "host and guest generated identical caves")
	_check(int(host.get("racer_count", 0)) == 4 and int(guest.get("racer_count", 0)) == 4, "4 racers on both")
	_check(int(host.get("bots", 0)) == 2 and int(guest.get("bots", 0)) == 2, "2 server-controlled bots on both")

	print("-- independent gravity, authoritative Moves")
	_check(int(host.get("my_gravity_after_shift", -1)) == CaveGraph.DIR_PLUS_X, "host turned to +X")
	_check(int(host.get("my_charges_after_shift", -1)) == 4, "host has 4 Moves after one shift")
	_check(int(guest.get("host_gravity_seen", -1)) == CaveGraph.DIR_PLUS_X, "guest sees the host on +X gravity")
	_check(int(guest.get("host_charges_seen", -1)) == 4, "guest sees the host's 4 Moves")
	_check(int(guest.get("my_gravity", -1)) == CaveGraph.DIR_DOWN and int(guest.get("my_charges", -1)) == 5,
		"guest's own gravity and Moves are untouched")

	print("-- one box, two hands")
	_check(host.get("box_open", false) and guest.get("box_open", false), "the box is open for both")
	_check(int(host.get("box_open_events", 0)) == 1 and int(guest.get("box_open_events", 0)) == 1,
		"each client saw it open exactly once")
	_check(int(host.get("box_opener_rid", -2)) == int(guest.get("box_opener_rid", -3))
		and int(host.get("box_opener_rid", -1)) >= 0, "both agree on the single opener")

	print("-- Prompt 3: arenas, synced rules, heart trade")
	_check(String(other.get("other_code", "")) != "" and other.get("other_code", "") != other.get("host_code", "+"),
		"a second arena on the same server gets its own code")
	_check(int(other.get("other_members", 0)) == 1 and int(other.get("other_members_later", 0)) == 1,
		"two clicks on Create Arena make one arena, and the two arenas stay separate")
	var notices := " ".join(other.get("notices", []))
	_check(notices.contains("letters or numbers") and notices.contains("No arena with code ZZZZ"),
		"a malformed code and an unknown code are refused with clear messages")
	_check(guest.get("guest_saw_rush_480", false), "the guest's lobby shows the host's Rush 8 minutes (and an invalid length was refused)")
	_check("Host" in guest.get("guest_saw_names", []) and "Guest" in guest.get("guest_saw_names", []),
		"both names appear in the guest's lobby")
	_check(guest.get("race_ruleset", "") == "rush" and int(guest.get("race_rush_seconds", 0)) == 480
		and is_equal_approx(float(guest.get("rush_limit_on_client", 0.0)), 480.0), "the race runs the host's rules on the guest")
	_check(is_equal_approx(float(guest.get("hearts_after_exchange", 0.0)), 4.0) and int(guest.get("moves_after_exchange", 0)) == 1,
		"a heart trade goes through the server once, even with a double press")

	print("-- qualification and the Freedom Duel over WebSockets")
	_check(int(host.get("my_place", 0)) == 1 and host.get("qualified_1st", false), "host reaches the exit first: Qualified 1st")
	_check(host.get("waiting_in_arena", false), "the host's own client moved it to the arena to wait")
	_check(int(guest.get("my_place", 0)) == 2 and guest.get("qualified_2nd", false), "guest arrives second: Qualified 2nd")
	_check(host.get("fight_seen", false) and guest.get("fight_seen", false), "both clients reach FIGHT from the server")
	_check(host.get("in_arena", false) and guest.get("in_arena", false), "both finalists are in the arena")
	_check(int(host.get("my_duel_dof", 0)) == 3 and int(guest.get("other_duel_dof", 0)) == 3,
		"Qualified 1st is 3DOF on both machines")
	_check(int(guest.get("my_duel_dof", 0)) == 2 and int(host.get("other_duel_dof", 0)) == 2,
		"Qualified 2nd is 2DOF on both machines")
	_check(int(guest.get("my_shots_confirmed", 0)) >= 3, "the server resolves the guest's shots and reports them back")
	_check(int(host.get("guest_shots_seen", -1)) >= int(guest.get("my_shots_confirmed", 99)),
		"the host sees every shot the guest's client saw confirmed")
	_check(guest.get("quit_mid_duel", false), "guest quit mid-duel")
	_check(int(guest.get("hits_on_host", 0)) >= 1, "the guest's shots hit the host through the server")
	_check(host.get("duel_end_reason", "") == "opponent left"
		and host.get("duel_champion_seen", "") == "Host", "a finalist who drops forfeits: the host is Champion")
	_check(server_alive, "server survived the disconnect")
	_check(host.get("results_received", false), "the duel ended and results reached the host")
	_check(int(host.get("results_first_duel_place", 0)) == 1 and int(host.get("results_second_duel_place", 0)) == 2,
		"results lead with the Champion, then the runner-up")
	_check(host.get("results_first_place", "-") == host.get("duel_champion_seen", "+"),
		"the Champion in the results is the one the duel crowned")
	_check(host.get("back_in_lobby_after_race", false) and host.get("still_connected", false),
		"host is back in the room, still connected")

	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	print("")
	print("==================================================")
	print("  NET (WebSocket)   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
