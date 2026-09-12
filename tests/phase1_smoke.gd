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

func _ready() -> void:
	await get_tree().process_frame
	_test_scene_loading()
	await _test_dof_enforcement()
	_test_save_rules()
	print("PHASE1_SMOKE_OK")
	get_tree().quit(0)

func _test_scene_loading() -> void:
	for path: String in SCENES:
		var packed := load(path) as PackedScene
		assert(packed != null, "Could not load " + path)
		var instance := packed.instantiate()
		assert(instance != null, "Could not instantiate " + path)
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
	assert(is_equal_approx(player.position.y, 400.0), "1 DOF allowed forbidden Y movement")
	assert(player.position.x > 500.0, "1 DOF did not allow X movement")
	var rotation_before := player.rotation
	Input.action_press("p1_rotate_right")
	await get_tree().physics_frame
	Input.action_release("p1_rotate_right")
	assert(is_equal_approx(player.rotation, rotation_before), "1 DOF allowed forbidden rotation")
	player.dof = 2
	var y_before := player.position.y
	Input.action_press("p1_down")
	await get_tree().physics_frame
	Input.action_release("p1_down")
	assert(player.position.y > y_before, "2 DOF did not allow Y movement")
	rotation_before = player.rotation
	Input.action_press("p1_rotate_right")
	await get_tree().physics_frame
	Input.action_release("p1_rotate_right")
	assert(is_equal_approx(player.rotation, rotation_before), "2 DOF allowed forbidden rotation")
	player.dof = 3
	Input.action_press("p1_rotate_right")
	await get_tree().physics_frame
	Input.action_release("p1_rotate_right")
	assert(player.rotation > rotation_before, "3 DOF did not allow rotation")
	player.queue_free()

func _test_save_rules() -> void:
	SaveManager.reset_data()
	assert(SaveManager.unlocked_level_count == 1)
	SaveManager.record_result("Easy", 1, 30, false)
	assert(SaveManager.get_high_score("Easy", 1) == 30)
	assert(SaveManager.unlocked_level_count == 1, "Failed attempt unlocked a level")
	var was_new := SaveManager.record_result("Easy", 1, 20, true)
	assert(not was_new, "Lower score replaced high score")
	assert(SaveManager.unlocked_level_count == 2, "Completed level did not unlock next")
