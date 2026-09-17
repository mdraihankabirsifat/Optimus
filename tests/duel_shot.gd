extends Node
## Screenshots of the Freedom Duel: Qualified 1st waiting, the fight from a finalist's eyes,
## and the spectator view. Run windowed: godot --path . --resolution 1280x720 res://tests/duel_shot.tscn

func _ready() -> void:
	await get_tree().process_frame
	var tag := "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = 4242
	world.bot_count = 2
	add_child(world)
	await get_tree().process_frame
	var mc: MatchController = world.match_controller
	mc._advance_countdown(10.0)
	var player: PlayerController = world.local_player()
	for b: Node3D in world.bots:
		b.get_node("BotController").set_physics_process(false)
	mc._on_finish_body_entered(player)
	await _wait(1.0)
	_shot("duel_01_waiting_%s" % tag)
	mc._on_finish_body_entered(world.bots[0])
	await _wait(2.0)
	_shot("duel_02_intro_%s" % tag)
	await _wait(3.5)
	world.bots[0].get_node("BotController").set_physics_process(true)
	world.duel.core_active = false
	world.duel._core_timer = 0.5
	await _wait(3.0)
	_shot("duel_03_fight_%s" % tag)
	world.local_player().health.hearts = 0.5
	var foe: PlayerController = world.bots[0]
	world.duel.fighters[foe]["pulse_cd"] = 0.0
	var eye := foe.head.global_position
	world.duel.fire(foe, "pulse", eye, (player.global_position - eye).normalized())
	await _wait(1.0)
	_shot("duel_04_end_%s" % tag)
	world.queue_free()
	await _wait(0.3)

	# Spectator: the local racer never qualifies.
	world = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	world.fixed_seed = 4242
	world.bot_count = 3
	add_child(world)
	await get_tree().process_frame
	mc = world.match_controller
	mc._advance_countdown(10.0)
	mc._on_finish_body_entered(world.bots[0])
	mc._on_finish_body_entered(world.bots[1])
	await _wait(8.0)
	_shot("duel_05_spectator_%s" % tag)
	get_tree().quit()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % shot_name)
	print("saved ", shot_name)
