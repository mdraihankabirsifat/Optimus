extends Node
## NET-002 / NET-005 -- lobby rules as pure data, no sockets.
## Run: godot --headless res://tests/test_net_lobby.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame

	print("\n-- racer counts: 2 to 5, at least one human")
	var room := LobbyState.new("ABCD", LobbyState.MODE_MIXED)
	_check(room.add_human(11, "Sifat") == "", "host joins")
	_check(room.host_id == 11, "first human hosts")
	_check(room.start_problem() != "", "one racer cannot start")
	_check(room.add_bot() == "", "add a bot in Mixed")
	_check(room.start_problem() == "", "1 human + 1 bot can start (2 racers)")
	for total in range(2, 6):
		var r := LobbyState.new("T%d" % total, LobbyState.MODE_MIXED)
		r.add_human(1, "Host")
		r.set_total_slots(total)
		r.fill_with_bots()
		_check(r.members.size() == total and r.start_problem() == "",
			"%d racers: fill with bots reaches %d and can start" % [total, total])
	_check(room.set_total_slots(9) == "" and room.total_slots == LobbyState.MAX_RACERS, "slots clamp to 5")
	_check(room.set_total_slots(1) == "" and room.total_slots == LobbyState.MIN_RACERS, "slots clamp to 2")

	print("-- 2 humans + 2 bots")
	var mixed := LobbyState.new("MIXD", LobbyState.MODE_MIXED)
	mixed.add_human(1, "Atul")
	mixed.add_human(2, "Sakib")
	mixed.set_total_slots(4)
	mixed.fill_with_bots()
	_check(mixed.human_count() == 2 and mixed.bot_count() == 2, "2 humans and 2 bots seated")
	_check(mixed.start_problem() != "", "cannot start while a guest is not ready")
	mixed.set_ready(2, true)
	_check(mixed.start_problem() == "", "starts once everyone is ready")
	var roster := mixed.roster()
	_check(roster.size() == 4, "roster lists all four")
	var rids_ok := true
	for i in roster.size():
		rids_ok = rids_ok and int(roster[i]["rid"]) == i
	_check(rids_ok, "racer ids are slot order")
	var colours := {}
	for entry: Dictionary in roster:
		colours[entry["colour"]] = true
	_check(colours.size() == 4, "no two racers share a colour")

	print("-- a human always outranks a bot for a seat")
	var full := LobbyState.new("FULL", LobbyState.MODE_MIXED)
	full.add_human(1, "Host")
	full.set_total_slots(3)
	full.fill_with_bots()
	_check(full.add_human(5, "Late") == "", "joining a room full of bots replaces a bot")
	_check(full.human_count() == 2 and full.members.size() == 3, "still three racers, two human")
	full.fill_with_bots()
	full.add_bot()
	full.set_total_slots(3)
	_check(full.add_human(6, "Human3") == "" and full.add_human(7, "Human4") != "",
		"once every seat is human, the room is full")

	print("-- Online Race is humans only")
	var online := LobbyState.new("ONLN", LobbyState.MODE_ONLINE)
	online.add_human(1, "A")
	_check(online.add_bot() != "", "cannot add a bot")
	_check(online.fill_with_bots() != "", "cannot fill with bots")
	online.add_human(2, "B")
	online.set_ready(2, true)
	_check(online.start_problem() == "", "two humans can start")
	for i in 3:
		online.set_total_slots(5)
		online.add_human(10 + i, "P%d" % i)
		online.set_ready(10 + i, true)
	_check(online.human_count() == 5 and online.start_problem() == "", "five humans can start")
	_check(online.add_human(99, "Sixth") != "", "a sixth human is turned away")
	mixed.set_mode(LobbyState.MODE_ONLINE)
	_check(mixed.bot_count() == 0, "switching to Online removes bots")

	print("-- host leaves, disconnects, mid-race joins")
	var h := LobbyState.new("HOST", LobbyState.MODE_MIXED)
	h.add_human(1, "First")
	h.add_human(2, "Second")
	h.remove_member(1)
	_check(h.host_id == 2, "host passes to the next human")
	h.remove_member(2)
	_check(h.is_empty_of_humans(), "room with no humans is empty")
	var racing := LobbyState.new("RACE", LobbyState.MODE_MIXED)
	racing.add_human(1, "A")
	racing.in_match = true
	_check(racing.add_human(2, "B") != "", "cannot join mid-race")
	_check(racing.start_problem() != "", "cannot start a second race at once")

	print("-- sanitising")
	# Prompt 3: names are plain text, 1-20 characters, any language.
	_check(LobbyState.sanitize_name("  <b>Robo</b>\n") == "bRobo/b", "markup brackets and control characters stripped")
	_check(LobbyState.sanitize_name("[color=red]X[/color]") == "color=redX/color", "BBCode brackets stripped")
	_check(LobbyState.sanitize_name("") == "Racer", "empty name gets a default")
	_check(LobbyState.name_problem("") != "" and LobbyState.name_problem("   \t\n") != "", "blank names are refused with a message")
	_check(LobbyState.name_problem("Sifat") == "", "an ordinary name is fine")
	_check(LobbyState.sanitize_name("abcdefghijklmnopqrstuvwxyz").length() == 20, "names capped at 20")
	_check(LobbyState.sanitize_name("Rāhim  সাকিব ✨") == "Rāhim সাকিব ✨", "Unicode kept, runs of spaces collapsed")
	_check(LobbyState.normalize_code(" ab-cd ") == "ABCD", "codes upper-cased and cleaned")
	_check(LobbyState.normalize_code("O0I1") == "", "ambiguous characters are not code characters")
	var dup := LobbyState.new("DUPE", LobbyState.MODE_MIXED)
	dup.add_human(1, "Sam")
	dup.add_human(2, "sam")
	_check(String(dup.find(2)["name"]) != "sam" and String(dup.find(2)["name"]).begins_with("sam"),
		"duplicate names are made unique")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var code := LobbyState.random_code(rng)
	_check(code.length() == LobbyState.CODE_LENGTH and LobbyState.normalize_code(code) == code,
		"random codes are valid codes")

	print("")
	print("==================================================")
	print("  NET LOBBY   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
