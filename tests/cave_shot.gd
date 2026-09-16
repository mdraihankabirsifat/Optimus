extends Node
## Visual check of generated cave geometry at several points along the guaranteed route.

var _cave: Node3D
var _player: PlayerController

func _ready() -> void:
	_cave = load("res://scenes/game/game_world.tscn").instantiate()
	_cave.randomise_seed = false
	_cave.fixed_seed = 4242
	add_child(_cave)
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("local_player")

	await _wait(50)
	_shot("cave_01_spawn")

	var spine: Array = _cave.graph.spine
	_teleport(spine[spine.size() / 3])
	await _wait(50)
	_shot("cave_02_midway")

	# Stand on the cell a racer actually arrives from, facing the exit.
	var approach: Vector3i = spine[spine.size() - 2] if spine.size() > 1 else _cave.graph.finish_cell
	_teleport(approach)
	_player.look_at(CaveBuilder.cell_to_world(_cave.graph.finish_cell), Vector3.UP)
	await _wait(50)
	_shot("cave_03_finish")

	# Stand next to a hazard so it can actually be judged.
	if not _cave.graph.hazards.is_empty():
		var h: Dictionary = _cave.graph.hazards[0]
		_teleport(h["cell"])
		_player.global_position += Vector3(2.8, 0, 2.8)
		_player.look_at(CaveBuilder.cell_to_world(h["cell"]), Vector3.UP)
		await _wait(60)
		_shot("cave_04_hazard")
	get_tree().quit()

func _teleport(cell: Vector3i) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = CaveBuilder.floor_position(cell) + Vector3(0, 1.5, 0)

func _wait(n: int) -> void:
	for i in n:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().process_frame

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % name)
	print("saved ", name)
