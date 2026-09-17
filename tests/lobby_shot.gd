extends Node
## Visual check of the Play screen, Settings and a live online lobby at two resolutions.
## Needs a window and a server on 8940:
##   godot --headless --path . -- --server --port=8940
##   godot res://tests/lobby_shot.tscn      (writes tests/shots/menu_*.png)

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]


func _ready() -> void:
	# Shots must be at the requested size even if this machine's settings say fullscreen.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for size in SIZES:
		DisplayServer.window_set_size(size)
		await get_tree().create_timer(0.4).timeout
		for scene: String in ["mode_select", "settings"]:
			var node: Node = load("res://scenes/ui/%s.tscn" % scene).instantiate()
			add_child(node)
			await get_tree().create_timer(0.5).timeout
			_shot("menu_%s_%d" % [scene, size.y])
			node.queue_free()
			await get_tree().process_frame

	GameState.online_mode = "mixed"
	var lobby: Node = load("res://scenes/ui/online_lobby.tscn").instantiate()
	add_child(lobby)
	NetManager.connect_to_server("ws://127.0.0.1:8940", "Sifat")
	var t := 0.0
	while not NetManager.is_online() and t < 15.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	NetManager.create_room("mixed")
	await get_tree().create_timer(1.0).timeout
	NetManager.host_action("slots", 5)
	NetManager.host_action("fill_bots")
	NetManager.host_action("theme", "jungle")
	await get_tree().create_timer(1.0).timeout
	for size in SIZES:
		DisplayServer.window_set_size(size)
		await get_tree().create_timer(0.6).timeout
		_shot("menu_online_lobby_%d" % size.y)
	get_tree().quit()


func _shot(file: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % file)
	print("saved ", file)
