extends Node
## Visual check of every cave feature: one screenshot each, searching seeds until found.
## Run (windowed): godot res://tests/feature_shot.tscn   -> tests/shots/feature_*.png

const KINDS := ["pad", "wind", "piston", "spider", "crumble", "shortcut", "landmark"]
const SEEDS := [4242, 777, 90210, 1, 2, 3, 5, 8, 13, 21]


func _ready() -> void:
	await get_tree().process_frame
	var wanted := {}
	for k in KINDS:
		wanted[k] = true
	var did_staging := false
	for sd in SEEDS:
		if wanted.is_empty() and did_staging:
			break
		GameState.prepare_match(sd, 1)
		var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
		get_tree().root.add_child(world)
		get_tree().current_scene = world
		await _wait(0.4)
		var player: PlayerController = get_tree().get_first_node_in_group("local_player")
		world.hud.visible = false
		if not did_staging:
			did_staging = true
			_look(player, world.graph.spawn_cell, Vector3(0, 0, 0))
			await _wait(0.4)
			_shot("feature_spawn_gates")
			_look(player, world.graph.finish_cell, Vector3(0, 0, 0))
			await _wait(0.4)
			_shot("feature_finish")
		for f: Dictionary in world.graph.features:
			var kind: String = f["kind"]
			if not wanted.has(kind):
				continue
			if kind == "landmark" and int(f["variant"]) > 0:
				continue
			wanted.erase(kind)
			_look(player, f["cell"], Vector3.ZERO)
			await _wait(1.6 if kind == "piston" else 0.6)
			_shot("feature_%s" % kind)
		world.queue_free()
		await _wait(0.2)
	print("not found: ", wanted.keys())
	get_tree().quit()


## Stand in the cell, back against one wall, looking across it slightly downward.
func _look(player: PlayerController, cell: Vector3i, _unused: Vector3) -> void:
	var centre := CaveBuilder.cell_to_world(cell)
	player.global_position = centre + Vector3(0.0, -2.2, 3.3)
	player.velocity = Vector3.ZERO
	player.global_basis = Basis.IDENTITY
	player.head.rotation.x = -0.25
	player.input_enabled = false


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % shot_name)
	print("saved ", shot_name)
