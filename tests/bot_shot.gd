extends Node
## Visual check: bots racing in their own gravity frames.

var _world: Node3D

func _ready() -> void:
	_world = load("res://scenes/game/game_world.tscn").instantiate()
	_world.randomise_seed = false
	_world.fixed_seed = 4242
	_world.bot_count = 4
	add_child(_world)
	await get_tree().process_frame
	var player: PlayerController = get_tree().get_first_node_in_group("local_player")

	await _wait(5.0)
	# Follow the pack so the bots are actually in frame.
	for shot in 3:
		var target: Node3D = _world.bots[shot % _world.bots.size()]
		player.global_position = target.global_position + Vector3(0, 1.5, 5.0)
		await _wait(1.2)
		_shot("bots_%02d" % (shot + 1))
	get_tree().quit()

func _wait(seconds: float) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(seconds).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % name)
	print("saved ", name)
