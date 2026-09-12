extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	print("Physical arrow codes: ", KEY_UP, " / ", KEY_DOWN)
	var arena := preload("res://scenes/game/prototype_arena_3d.tscn").instantiate() as PrototypeArena3D
	add_child(arena)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds")
		get_viewport().get_texture().get_image().save_png("res://builds/prototype_3d.png")
	await get_tree().physics_frame
	check(arena.players.size() == 2, "Two players must spawn")
	var player := arena.players[0]
	player.set_physics_process(false)
	for dof: int in range(1, 4):
		player.dof = dof
		player.position = Vector3(-8, 0.05, 2)
		player.rotation = Vector3.ZERO
		for frame: int in 10:
			await get_tree().physics_frame
			player.apply_motion(Vector2(1, 1), 1, 1.0 / 60.0)
		check(player.position.x > -8, "All DOFs allow world X")
		check(is_equal_approx(player.position.y, 0.05), "Ground height must stay locked")
		check(is_equal_approx(player.position.z, 2.0) if dof == 1 else player.position.z > 2, "Ground Z constraint")
		check(is_zero_approx(player.rotation.y) if dof < 3 else player.rotation.y > 0, "Yaw constraint")
	player.dof = 1
	player.position = Vector3(10, 0.05, 2)
	for frame: int in 40:
		await get_tree().physics_frame
		player.apply_motion(Vector2.RIGHT, 0, 1.0 / 60.0)
	check(player.position.x < 10.3, "Wall collision stops the robot")
	player.position = Vector3(-6.8, 0.05, 0)
	arena.station_cooldowns.fill(0.0)
	arena._harvest(0, 0.5)
	check(arena.scores[0] >= 10, "Restricted role can score on its lane")
	player.dof = 3
	player.rotation.y = 0
	arena.station_cooldowns.fill(0.0)
	var score_before := arena.scores[0]
	arena._harvest(0, 2.0)
	check(arena.scores[0] == score_before, "3 DOF needs to face the station")
	player.rotation.y = -PI / 2
	arena._harvest(0, 2.0)
	check(arena.scores[0] > score_before, "3 DOF can harvest when facing the station")
	player.take_damage(10)
	player.take_damage(10)
	check(player.health == 90, "Damage cooldown rejects repeated hits")
	arena.toggle_pause()
	var time_before := arena.time_remaining
	await get_tree().process_frame
	check(get_tree().paused and arena.time_remaining == time_before, "Pause freezes timer")
	arena.toggle_pause()
	check(not get_tree().paused, "Resume works")
	arena.time_remaining = 0
	arena._physics_process(0.01)
	check(arena.finished and not player.input_enabled, "Timer ends round and disables input")
	arena.queue_free()
	await get_tree().process_frame
	var damaged_arena := preload("res://scenes/game/prototype_arena_3d.tscn").instantiate() as PrototypeArena3D
	add_child(damaged_arena)
	damaged_arena.players[0].take_damage(100)
	check(damaged_arena.finished, "Zero health ends the round")
	damaged_arena.queue_free()
	await get_tree().process_frame
	print("PROTOTYPE_3D_SMOKE_OK" if failures == 0 else "PROTOTYPE_3D_SMOKE_FAILED")
	get_tree().quit(failures)
