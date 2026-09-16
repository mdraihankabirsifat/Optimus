extends Node
## UI-001..009 -- every screen loads, and a menu-launched race reaches the results screen.
## Run: godot --headless res://tests/test_flow.tscn

const SCREENS := [
	"res://scenes/ui/splash.tscn", "res://scenes/ui/main_menu.tscn", "res://scenes/ui/lobby.tscn",
	"res://scenes/ui/settings.tscn", "res://scenes/ui/how_to_play.tscn", "res://scenes/ui/about.tscn",
	"res://scenes/ui/credits.tscn", "res://scenes/ui/results.tscn", "res://scenes/ui/loading.tscn",
]

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame

	print("\n-- every screen instantiates")
	for path: String in SCREENS:
		var packed: PackedScene = load(path)
		_check(packed != null, "loads %s" % path)
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		add_child(node)
		await get_tree().process_frame
		_check(node.get_child_count() > 0, "builds content %s" % path.get_file())
		node.queue_free()
		await get_tree().process_frame

	_test_rules_without_a_scene()
	await _test_time_trial()

	print("-- a race launched from the lobby")
	GameState.prepare_match(4242, 3)
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	# The world must be the current scene, or routing to results would free this test.
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await get_tree().process_frame
	_check(world.seed_value == 4242, "uses the lobby seed")
	_check(world.bots.size() == 3, "spawns the lobby's bot count")
	_check(world.hud != null, "has a HUD")
	_check(get_tree().get_nodes_in_group("mystery_boxes").size() > 0, "cave has mystery boxes")
	_check(get_tree().get_nodes_in_group("hazards").size() > 0, "cave has fire")
	_check(GameState.stats.size() == 4, "stats registered for every racer")

	var mc: MatchController = world.match_controller
	await get_tree().create_timer(AppConfig.MATCH_COUNTDOWN_SECONDS + 0.5).timeout
	_check(mc.phase == MatchController.Phase.RACING, "countdown reaches GO")

	# Open one box as the local player and confirm the outcome sticks.
	var boxes := get_tree().get_nodes_in_group("mystery_boxes")
	if not boxes.is_empty():
		var box: MysteryBox = boxes[0]
		var player: PlayerController = get_tree().get_first_node_in_group("local_player")
		box.interact(player)
		_check(box.is_open, "box opens")
		_check(int(GameState.stats["You"]["boxes"]) == 1, "box counted in stats")

	world.pause_menu.open()
	_check(get_tree().paused, "pause menu pauses")
	world.pause_menu.close()
	_check(not get_tree().paused, "resume unpauses")

	mc.force_end()
	_check(mc.phase == MatchController.Phase.ENDED, "force_end ends the race")
	_check(GameState.last_results.size() == 4, "results recorded")
	await get_tree().create_timer(game_world_delay()).timeout
	var scene := get_tree().current_scene
	_check(scene != null and scene.scene_file_path.ends_with("results.tscn"), "routes to results")

	print("==================================================")
	print("  UI FLOW   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_rules_without_a_scene() -> void:
	print("-- second chance, records, daily seed, ghost file")
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	world.randomise_seed = false
	add_child(world)
	var p: PlayerController = get_tree().get_first_node_in_group("local_player")
	var h := p.health
	h.set_damage_enabled(true)
	h.grant_second_chance()
	h.apply_damage(9.0, "test")
	_check(not h.is_eliminated and is_equal_approx(h.hearts, 0.5), "second chance leaves half a heart")
	_check(not h.has_second_chance, "second chance is used up")
	world.queue_free()

	_check(GameState.daily_seed() == GameState.daily_seed(), "daily seed is stable within a day")
	var key_seed := 987654
	SettingsManager.best_times.erase(SettingsManager.cave_key(key_seed, 1))
	SettingsManager.best_times.erase(SettingsManager.cave_key(key_seed, 1) + ":board")
	_check(SettingsManager.submit_cave_time(50.0, key_seed, 1), "first time on a cave is a record")
	_check(not SettingsManager.submit_cave_time(60.0, key_seed, 1), "a slower time is not")
	_check(SettingsManager.submit_cave_time(40.0, key_seed, 1), "a faster time is")
	_check(SettingsManager.leaderboard(key_seed, 1).size() == 3, "board keeps every time")

	var frames := [[Vector3.ZERO, Quaternion.IDENTITY], [Vector3(1, 0, 0), Quaternion.IDENTITY]]
	GhostRacer.save(key_seed, 1, frames)
	var ghost := GhostRacer.load_for(key_seed, 1)
	_check(ghost != null, "ghost reloads from disk")
	if ghost != null:
		ghost.free()
	DirAccess.remove_absolute(GhostRacer.path_for(key_seed, 1))
	# Leave the real player's records exactly as they were.
	SettingsManager.best_times.erase(SettingsManager.cave_key(key_seed, 1))
	SettingsManager.best_times.erase(SettingsManager.cave_key(key_seed, 1) + ":board")
	SettingsManager.save_settings()


func _test_time_trial() -> void:
	print("-- time trial with no bots")
	GameState.prepare_match(31337, 0)
	var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	_check(world.bots.is_empty(), "no bots spawn")
	_check(world.match_controller.racers.size() == 1, "one racer registered")
	world.match_controller.force_end()
	world.queue_free()
	await get_tree().process_frame


func game_world_delay() -> float:
	return 2.5 + SceneRouter.FADE_TIME * 2.0 + 0.8


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL: ", what)
