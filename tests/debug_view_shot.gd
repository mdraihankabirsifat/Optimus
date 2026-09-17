extends Node
## Visual check of the developer overlay (F3) partway through a bot race.
## Needs a window: godot res://tests/debug_view_shot.tscn  (writes tests/shots/debug_view.png)

func _ready() -> void:
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = 4242
	world.bot_count = 2
	add_child(world)
	await get_tree().process_frame
	var player: PlayerController = world.get("_player")
	player.set_physics_process(false)
	# Lift the camera above the cave so the whole graph is in view.
	var cam := Camera3D.new()
	world.add_child(cam)
	var graph: CaveGraph = world.graph
	var centre := Vector3.ZERO
	for c: Vector3i in graph.cells:
		centre += CaveBuilder.cell_to_world(c)
	centre /= float(graph.cell_count())
	cam.global_position = centre + Vector3(-30, 55, 45)
	cam.look_at(centre, Vector3.UP)
	cam.make_current()
	await get_tree().create_timer(9.0).timeout
	var view := world.get_node("CaveDebugView") as CaveDebugView
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.pressed = true
	view._unhandled_input(ev)
	await get_tree().create_timer(0.6).timeout
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/debug_view.png")
	print("saved debug_view")
	get_tree().quit()
