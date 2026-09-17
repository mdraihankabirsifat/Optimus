extends Node
## Debug probe: one bot race, bot state printed every second.
## Run: godot --headless --fixed-fps 60 res://tests/bot_probe.tscn -- seed=1000

func _ready() -> void:
	await get_tree().process_frame
	var s := 1000
	var secs := 12
	var rush := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			s = int(arg.trim_prefix("seed="))
		if arg.begins_with("secs="):
			secs = int(arg.trim_prefix("secs="))
		if arg.begins_with("rush="):
			rush = int(arg.trim_prefix("rush="))
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = s
	world.bot_count = 4
	world.duel_enabled = false
	world.bot_skill = 2
	if rush > 0:
		world.ruleset = AppConfig.RULESET_RUSH
		world.rush_seconds = rush
	add_child(world)
	await get_tree().process_frame
	(world.get("_player") as PlayerController).set_physics_process(false)
	for bb: Node3D in world.bots:
		var body := bb as PlayerController
		body.health.damaged.connect(func(amount: float, source: String) -> void:
			print("DAMAGE %s %.1f from %s at cell %s hearts %.1f t=%.1f" % [body.display_name, amount, source,
				CaveBuilder.world_to_cell(body.global_position), body.health.hearts, world.match_controller.elapsed]))
	var g: CaveGraph = world.graph
	print("spawn %s finish %s" % [g.spawn_cell, g.finish_cell])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("cell="):
			var parts := arg.trim_prefix("cell=").split(",")
			var c := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			for dc in [Vector3i.ZERO, Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
				var n: Vector3i = c + dc
				if not g.has_cell(n):
					continue
				var links := []
				for d in 6:
					if g.is_linked(n, d):
						links.append(CaveGraph.DIRS[d])
				print("cell %s chamber %s links %s" % [n, CaveBuilder.is_chamber(g, n), links])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ray="):
			await get_tree().physics_frame
			var parts := arg.trim_prefix("ray=").split(",")
			var from := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			var to := from + Vector3(float(parts[3]), float(parts[4]), float(parts[5]))
			var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
			if not hit.is_empty():
				var col: Node = hit["collider"]
				var sh: CollisionShape3D = col.shape_owner_get_owner(col.shape_find_owner(hit["shape"]))
				print("ray hit %s at %s shape pos %s %s" % [col.name, hit["position"], sh.global_position, sh.shape.size if sh.shape is BoxShape3D else (sh.shape as ConvexPolygonShape3D).points])
			for f: Dictionary in g.features:
				if f["cell"] in [Vector3i(0,0,2), Vector3i(0,0,3)]:
					print("feature ", f)
			for b: Dictionary in g.boxes if "boxes" in g else []:
				print("box ", b)
	for t in secs:
		await get_tree().create_timer(1.0).timeout
		if t % 5 != 4:
			continue
		for b: Node3D in world.bots:
			var body := b as PlayerController
			var c: BotController = b.get_node("BotController")
			print("t=%d %s grav %s pos %s cell %s floor %s vel %s input %s path %s enabled %s | %s" % [t, c.display_name, body.gravity.gravity_dir,
				body.global_position, CaveBuilder.world_to_cell(body.global_position), body.is_on_floor(),
				body.velocity, body.move_input, c.get("_path").slice(0, 3), body.input_enabled, c.debug_state()])
	get_tree().quit()
