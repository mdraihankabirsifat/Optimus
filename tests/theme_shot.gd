extends Node
## ART-012 visual check: the same cave (seed 4242) in every environment, from the same spot.
## Needs a window: godot res://tests/theme_shot.tscn   (writes tests/shots/theme_*.png)

const SEED := 4242


func _ready() -> void:
	for id: String in CaveTheme.IDS:
		var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
		world.randomise_seed = false
		world.fixed_seed = SEED
		world.bot_count = 2
		world.theme_id = id
		add_child(world)
		await get_tree().process_frame
		var player: PlayerController = world.get("_player")
		var spine: Array = world.graph.spine
		var cell: Vector3i = spine[spine.size() / 2]
		player.global_position = CaveBuilder.floor_position(cell) + Vector3(0, 0.5, 0)
		player.set_physics_process(false)
		player.head.rotation.x = 0.28
		for i in 70:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute("res://tests/shots")
		get_viewport().get_texture().get_image().save_png("res://tests/shots/theme_%s.png" % id)
		print("saved theme_", id)
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
