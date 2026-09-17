extends Node
## BOT-011 -- physical bot races, many seeds, no human. Unlike test_bot (pure logic), bots
## here drive real bodies through real geometry, so it catches bots that plan well but get
## stuck on walls, shafts or hazards.
## Run fast:  godot --headless --fixed-fps 60 res://tests/bot_physical.tscn -- seeds=12 walls=1
##   seeds=N   how many caves (default 10)
##   walls=0/1 allow 90-degree wall-walk planning (default: the planner's own default)
##   skill=0-2 (default 2)
## Exits non-zero if fewer than 75% of bots finish, which would mean bots are getting stuck.

const RACE_LIMIT := 150.0
const BOTS := 4

var _seeds := 10
var _skill := 2
var _walls := -1


func _ready() -> void:
	await get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"seeds": _seeds = int(kv[1])
			"skill": _skill = int(kv[1])
			"walls": _walls = int(kv[1])
	if _walls >= 0:
		BotPlanner.wall_walks_enabled = _walls == 1
	print("\nphysical bot races: %d caves x %d bots, skill %d, wall-walks %s"
		% [_seeds, BOTS, _skill, "on" if BotPlanner.wall_walks_enabled else "off"])

	var finished := 0
	var total := 0
	var times: Array[float] = []
	var moves := 0
	var side_shifts := 0
	for i in _seeds:
		var s := 1000 + i * 37
		var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
		world.randomise_seed = false
		world.fixed_seed = s
		world.bot_count = BOTS
		world.bot_skill = _skill
		# Measures cave traversal only; the Freedom Duel would stop the field at two finishers.
		world.duel_enabled = false
		add_child(world)
		await get_tree().process_frame
		# No human in these races. Eliminating the local player would start the offline
		# "end soon after you are done" grace, so it is frozen at spawn instead.
		var player: PlayerController = world.get("_player")
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		var mc: MatchController = world.match_controller
		var shifts := {"side": 0}
		for b: Node3D in world.bots:
			(b as PlayerController).gravity.shift_started.connect(func(d: Vector3) -> void:
				if absf(d.y) < 0.5:
					shifts["side"] += 1)
		var start := Time.get_ticks_msec()
		# Seconds each bot has gone without moving 1.5 units: the stall a watchdog must explain.
		var stall := {}
		var anchor := {}
		for b: Node3D in world.bots:
			stall[b] = 0.0
			anchor[b] = b.global_position
		while mc.phase != MatchController.Phase.ENDED and mc.elapsed < RACE_LIMIT:
			await get_tree().physics_frame
			for b: Node3D in world.bots:
				if b.global_position.distance_to(anchor[b]) > 1.5:
					anchor[b] = b.global_position
					stall[b] = 0.0
				else:
					stall[b] += 1.0 / 60.0
			if Time.get_ticks_msec() - start > 240000:
				break
			var open_bots := 0
			for r: Dictionary in mc.racers:
				if r["is_bot"] and not r["finished"] and not r["eliminated"]:
					open_bots += 1
			if open_bots == 0 and mc.phase == MatchController.Phase.RACING:
				break
		var line := "  seed %d:" % s
		for r: Dictionary in mc.racers:
			if not r["is_bot"]:
				continue
			total += 1
			if r["finished"]:
				finished += 1
				times.append(float(r["finish_time"]))
				line += "  %s %s" % [r["name"], MatchController.format_time(r["finish_time"])]
			else:
				var body := r["body"] as PlayerController
				var bc: BotController = body.get_node("BotController")
				var why := "eliminated" if r["eliminated"] else "stuck %.0fs" % stall[body]
				line += "  %s DNF@%s[%s g%d m%d h%.1f %s]" % [r["name"], CaveBuilder.world_to_cell(body.global_position), why,
					bc._grav(), body.gravity.charges, body.health.hearts, bc.debug_state()]
			moves += int(world.stats[r["name"]]["moves_used"])
		side_shifts += int(shifts["side"])
		print(line)
		world.queue_free()
		await get_tree().process_frame

	var avg := 0.0
	for t in times:
		avg += t
	avg = avg / maxf(1.0, float(times.size()))
	print("\n  finished %d / %d (%.0f%%), average time %s, Moves used %d (%d sideways)"
		% [finished, total, 100.0 * finished / maxf(1.0, total), MatchController.format_time(avg), moves, side_shifts])
	get_tree().quit(0 if float(finished) / maxf(1.0, total) >= 0.75 else 1)
