extends Node

const SCENES: Array[String] = [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/play_menu.tscn",
	"res://scenes/ui/settings_menu.tscn",
	"res://scenes/ui/mode_select.tscn",
	"res://scenes/ui/level_select.tscn",
	"res://scenes/ui/about_menu.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/player/player.tscn",
	"res://scenes/game/energy_node.tscn",
	"res://scenes/game/hazard.tscn",
	"res://scenes/game/prototype_arena.tscn",
]

var failures: int = 0
var save_existed: bool
var settings_existed: bool
var save_backup: PackedByteArray
var settings_backup: PackedByteArray

func _ready() -> void:
	_backup_user_data()
	await get_tree().process_frame
	_test_scene_loading()
	await _test_dof_enforcement()
	_test_save_and_settings()
	await _test_arena_flow()
	_restore_user_data()
	if failures == 0:
		print("PHASE1_SMOKE_OK")
	else:
		push_error("PHASE1_SMOKE_FAILED: %d checks failed" % failures)
	get_tree().quit(failures)

func _check(condition: bool, message: String = "Check failed") -> void:
	if not condition:
		failures += 1
		push_error(message)

func _backup_user_data() -> void:
	save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	settings_existed = FileAccess.file_exists(SettingsManager.SETTINGS_PATH)
	if save_existed:
		save_backup = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)
	if settings_existed:
		settings_backup = FileAccess.get_file_as_bytes(SettingsManager.SETTINGS_PATH)

func _restore_user_data() -> void:
	_restore_file(SaveManager.SAVE_PATH, save_existed, save_backup)
	_restore_file(SettingsManager.SETTINGS_PATH, settings_existed, settings_backup)

func _restore_file(path: String, existed: bool, backup: PackedByteArray) -> void:
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_scene_loading() -> void:
	for path: String in SCENES:
		var packed := load(path) as PackedScene
		_check(packed != null, "Could not load " + path)
		var instance := packed.instantiate()
		_check(instance != null, "Could not instantiate " + path)
		instance.free()

func _test_dof_enforcement() -> void:
	var player := load("res://scenes/player/player.tscn").instantiate() as DOFPlayer
	player.player_id = 1
	player.position = Vector2(500, 400)
	add_child(player)
	player.dof = 1
	Input.action_press("p1_up")
	Input.action_press("p1_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("p1_up")
	Input.action_release("p1_right")
	_check(is_equal_approx(player.position.y, 400.0), "1 DOF allowed forbidden Y movement")
	_check(player.position.x > 500.0, "1 DOF did not allow X movement")
	var rotation_before := player.rotation
	Input.action_press("p1_rotate_right")
	await get_tree().physics_frame
	Input.action_release("p1_rotate_right")
	_check(is_equal_approx(player.rotation, rotation_before), "1 DOF allowed forbidden rotation")
	player.dof = 2
	var y_before := player.position.y
	Input.action_press("p1_down")
	await get_tree().physics_frame
	Input.action_release("p1_down")
	_check(player.position.y > y_before, "2 DOF did not allow Y movement")
	rotation_before = player.rotation
	Input.action_press("p1_rotate_right")
	await get_tree().physics_frame
	Input.action_release("p1_rotate_right")
	_check(is_equal_approx(player.rotation, rotation_before), "2 DOF allowed forbidden rotation")
	player.dof = 3
	Input.action_press("p1_rotate_right")
	await get_tree().physics_frame
	Input.action_release("p1_rotate_right")
	_check(player.rotation > rotation_before, "3 DOF did not allow rotation")
	player.queue_free()

func _test_save_and_settings() -> void:
	SaveManager.reset_data()
	_check(SaveManager.unlocked_level_count == 1)
	SaveManager.record_result("Easy", 1, 30, false)
	_check(SaveManager.get_high_score("Easy", 1) == 30)
	_check(SaveManager.unlocked_level_count == 1, "Failed attempt unlocked a level")
	var was_new := SaveManager.record_result("Easy", 1, 20, true)
	_check(not was_new, "Lower score replaced high score")
	_check(SaveManager.unlocked_level_count == 2, "Completed level did not unlock next")
	SaveManager.load_data()
	_check(SaveManager.get_high_score("Easy", 1) == 30, "High score did not persist")
	_check(SaveManager.unlocked_level_count == 2, "Unlock did not persist")
	var malformed := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	_check(malformed != null, "Could not create malformed-save fixture")
	malformed.store_string("this is not valid ConfigFile data [")
	malformed.close()
	SaveManager.load_data()
	_check(SaveManager.unlocked_level_count == 1, "Malformed save did not restore defaults")
	_check(SaveManager.high_scores.is_empty(), "Malformed save retained scores")
	SettingsManager.values.master_volume = 0.37
	SettingsManager.values.master_muted = true
	SettingsManager.save_settings()
	SettingsManager.values.master_volume = 0.9
	SettingsManager.values.master_muted = false
	SettingsManager.load_settings()
	_check(is_equal_approx(float(SettingsManager.values.master_volume), 0.37), "Volume did not persist")
	_check(bool(SettingsManager.values.master_muted), "Mute did not persist")

func _test_arena_flow() -> void:
	var arena: Variant = load("res://scenes/game/prototype_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	_check(arena.players.size() == 2, "Arena did not create two players")
	arena.players[0].take_damage(100)
	_check(arena.players[0].health == 0, "Health could not reach zero")
	_check(arena.game_finished, "Zero health did not finish the game")
	arena.queue_free()
	await get_tree().process_frame
	var timed_arena: Variant = load("res://scenes/game/prototype_arena.tscn").instantiate()
	add_child(timed_arena)
	await get_tree().process_frame
	timed_arena._pause()
	_check(get_tree().paused, "Pause did not stop the tree")
	timed_arena._resume()
	_check(not get_tree().paused, "Resume did not restart the tree")
	timed_arena.time_remaining = 0.0
	timed_arena._process(0.1)
	_check(timed_arena.game_finished, "Timer expiration did not finish the game")
	timed_arena.queue_free()
