extends Node
## Visual check of menus, the race HUD, hazards, boxes and results.
## Run (windowed): godot res://tests/ui_shot.tscn   -> tests/shots/ui_*.png

func _ready() -> void:
	await get_tree().process_frame
	for path: String in ["main_menu", "lobby", "how_to_play", "about"]:
		var screen: Node = load("res://scenes/ui/%s.tscn" % path).instantiate()
		add_child(screen)
		await _wait(0.5)
		_shot("ui_%s" % path)
		screen.queue_free()

	GameState.prepare_match(4242, 3)
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await _wait(1.2)
	_shot("ui_race_countdown")
	await _wait(3.0)
	var player: PlayerController = get_tree().get_first_node_in_group("local_player")
	Input.action_press("gravity_mod")
	await _wait(0.3)
	_shot("ui_race_g_preview")
	Input.action_release("gravity_mod")

	var fire: Node3D = get_tree().get_nodes_in_group("hazards")[0]
	_look_from(player, fire.global_position + Vector3(0, 0, 5.5), fire.global_position)
	await _wait(0.6)
	_shot("ui_fire")

	var box: MysteryBox = get_tree().get_nodes_in_group("mystery_boxes")[0]
	var to_centre := CaveBuilder.cell_to_world(CaveBuilder.world_to_cell(box.global_position)) - box.global_position
	to_centre.y = 0.0
	_look_from(player, box.global_position + to_centre.normalized() * 2.6 + Vector3(0, 0.6, 0), box.global_position)
	await _wait(0.5)
	_shot("ui_box_prompt")
	# Force a clue on the HUD so the arrow can be judged.
	world.hud.on_clue(player, Vector3(1, 0, 0), 1)
	player.health.apply_damage(1.5, "shot")
	box.interact(player)
	await _wait(0.4)
	_shot("ui_box_opened")

	player.health.apply_damage(3.0, "shot2")
	await _wait(0.3)
	_shot("ui_low_health")
	player.health.eliminate()
	await _wait(3.0)
	_shot("ui_spectating")
	world.match_controller.force_end()
	await _wait(4.5)
	_shot("ui_results")
	get_tree().quit()


func _look_from(player: PlayerController, from: Vector3, target: Vector3) -> void:
	player.global_position = from
	player.velocity = Vector3.ZERO
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	player.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	player.head.rotation.x = -0.35


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % shot_name)
	print("saved ", shot_name)
