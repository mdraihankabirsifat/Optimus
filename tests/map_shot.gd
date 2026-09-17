extends Node
## Visual check of the map, the mini-map and a clue marker, after the Prompt 4 follow-up.
## Run (windowed): godot res://tests/map_shot.tscn   -> tests/shots/map_*.png

func _ready() -> void:
	await get_tree().process_frame
	GameState.prepare_match(4242, 1)
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _wait(4.5)
	var player: PlayerController = get_tree().get_first_node_in_group("local_player")
	var hud: RaceHUD = world.hud

	# Walk a while so there is something to draw: follow the graph from the spawn.
	var graph: CaveGraph = world.graph
	var cell: Vector3i = graph.spawn_cell
	var seen := {cell: true}
	for step in 26:
		var options: Array[Vector3i] = []
		for d: int in CaveGraph.FLAT_DIRS:
			if graph.is_linked(cell, d) and not seen.has(cell + CaveGraph.DIRS[d]):
				options.append(cell + CaveGraph.DIRS[d])
		if options.is_empty():
			break
		cell = options[step % options.size()]
		seen[cell] = true
		player.global_position = CaveBuilder.cell_to_world(cell) + Vector3(0, 1.2, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
	await _wait(0.6)
	_shot("map_01_minimap")

	hud.on_clue(player, Vector3(0.7071, 0, -0.7071), 1, 6)
	await _wait(0.4)
	_shot("map_02_clue")

	hud.toggle_map()
	await _wait(0.5)
	_shot("map_03_full")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % shot_name)
	print("saved ", shot_name)
