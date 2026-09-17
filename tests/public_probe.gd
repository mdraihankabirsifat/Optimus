extends Node
## Deployment check against a real public server. Two processes: one creates an arena, the
## other joins it with the code, both over the normal client path (NetManager).
##   godot --headless --path . res://tests/public_probe.tscn -- --role=host --codefile=C:/tmp/code.txt
##   godot --headless --path . res://tests/public_probe.tscn -- --role=guest --codefile=C:/tmp/code.txt
## --url=... overrides the server; by default it uses NetManager.default_server_url(), which is
## AppConfig.PUBLIC_SERVER_URL unless a local override is saved.

var role := "host"
var url := ""
var code_path := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"role": role = kv[1]
			"url": url = kv[1]
			"codefile": code_path = kv[1]
	if url == "":
		url = AppConfig.PUBLIC_SERVER_URL
	NetManager.notice.connect(func(text: String, is_error: bool) -> void:
		print("[%s] notice%s: %s" % [role, " (error)" if is_error else "", text]))
	_run()


func _run() -> void:
	print("[%s] connecting to %s" % [role, url])
	NetManager.connect_to_server(url, "Probe" + role.capitalize())
	# A free Render instance can take up to a minute to wake.
	if not await _until(func() -> bool: return NetManager.is_online(), 90.0):
		_done("FAILED: never connected (%s) %s" % [NetManager.state_name(), NetManager.last_error])
		return
	print("[%s] connected, latency pending" % role)
	if role == "host":
		NetManager.create_room("mixed")
		if not await _until(func() -> bool: return NetManager.in_room(), 20.0):
			_done("FAILED: arena was never created")
			return
		var code := String(NetManager.lobby["code"])
		print("[host] arena code %s" % code)
		var f := FileAccess.open(code_path, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		var joined := func() -> bool:
			var humans := 0
			for s: Dictionary in NetManager.lobby.get("slots", []):
				if not s["is_bot"]:
					humans += 1
			return humans >= 2
		if not await _until(joined, 90.0):
			_done("FAILED: nobody joined arena %s" % code)
			return
		var names: Array = []
		for s: Dictionary in NetManager.lobby["slots"]:
			names.append(s["name"])
		await get_tree().create_timer(2.0).timeout
		_done("OK: host arena %s now holds %s" % [code, names])
	else:
		if not await _until(func() -> bool: return FileAccess.file_exists(code_path), 120.0):
			_done("FAILED: no code to join")
			return
		var code := FileAccess.get_file_as_string(code_path).strip_edges()
		NetManager.join_room(code)
		if not await _until(func() -> bool: return NetManager.in_room(), 20.0):
			_done("FAILED: could not join %s" % code)
			return
		var names: Array = []
		for s: Dictionary in NetManager.lobby["slots"]:
			names.append(s["name"])
		await get_tree().create_timer(4.0).timeout
		_done("OK: guest joined arena %s by code, sees %s" % [NetManager.lobby["code"], names])


func _until(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _done(result: String) -> void:
	print("[%s] RESULT %s" % [role, result])
	if NetManager.in_room():
		NetManager.leave_room()
	await get_tree().create_timer(0.5).timeout
	NetManager.disconnect_from_server()
	get_tree().quit(0 if result.begins_with("OK") else 1)
