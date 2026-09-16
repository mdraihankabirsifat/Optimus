extends Node
## Dedicated server entry point. Run headless with --server after the "--" separator:
##
##     godot --headless --path . -- --server --port=8910          (from source)
##     SixWaysDown.exe --headless -- --server --port=8910          (exported build)
##
## From source, passing this scene directly also works:
##     godot --headless --path . res://scenes/net/server.tscn -- --port=8910
##
## Port order of precedence: --port=N, then the PORT environment variable (Render sets
## this), then AppConfig.DEFAULT_SERVER_PORT. --test-mode lets the automated network test
## teleport racers; never pass it to a public server.

func _ready() -> void:
	var port := AppConfig.DEFAULT_SERVER_PORT
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		port = int(env_port)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			var value := arg.trim_prefix("--port=")
			if value.is_valid_int():
				port = int(value)
		elif arg == "--test-mode":
			NetManager.test_mode = true
			print("[server] TEST MODE: harness teleports allowed")
	if NetManager.start_server(port) != OK:
		get_tree().quit(1)
		return
	# A dedicated server should never throttle itself for a window that does not exist.
	Engine.max_fps = 60
