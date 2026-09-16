extends Node
## SHIP-008: frame time, draw calls and object counts on the heaviest setup (Long cave,
## four bots). Run windowed: godot res://tests/perf_probe.tscn -- size=2 bots=4
## An M4 hides problems, so read the draw-call and object numbers, not just the FPS.

func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	await get_tree().process_frame
	var size := 2
	var bots := 4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("size="):
			size = int(arg.trim_prefix("size="))
		if arg.begins_with("bots="):
			bots = int(arg.trim_prefix("bots="))
	GameState.cave_size = size
	GameState.prepare_match(4242, bots)
	var gen_start := Time.get_ticks_usec()
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	print("world build: %.0f ms" % ((Time.get_ticks_usec() - gen_start) / 1000.0))
	print("startup to world: %.0f ms (audio synthesis happens in autoloads before this)" % ((Time.get_ticks_usec() - t0) / 1000.0))
	await get_tree().create_timer(0.2).timeout
	var frames := 0
	var worst := 0.0
	var total := 0.0
	var last := Time.get_ticks_usec()
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		frames += 1
		total += dt
		if dt > 25.0:
			print("  hitch %.0f ms at race time %.2f" % [dt, world.match_controller.elapsed])
		worst = maxf(worst, dt)
	print("frames %d  avg %.2f ms  worst %.2f ms  fps %.0f" % [frames, total / frames, worst, 1000.0 * frames / total])
	print("draw calls %d  objects %d  primitives %d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("nodes %d  physics bodies %d  static mem %.0f MB" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	get_tree().quit()
