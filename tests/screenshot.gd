extends Node
## Temporary visual harness: loads the test chamber, captures before/after a 180 shift.

var _chamber: Node
var _player: PlayerController

func _ready() -> void:
	_chamber = load("res://scenes/game/test_chamber.tscn").instantiate()
	add_child(_chamber)
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player = get_tree().get_first_node_in_group("local_player")

	await _wait(40)
	_shot("01_start")

	_player.gravity.request_inversion()
	await _wait(110)
	_shot("02_inverted")

	_player.gravity.request_shift(Vector3.RIGHT)
	await _wait(130)
	_shot("03_wall")

	get_tree().quit()

func _wait(frames: int) -> void:
	for i in frames:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().process_frame

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	img.save_png("res://tests/shots/%s.png" % name)
	print("saved ", name, "  gravity=", _player.gravity.gravity_dir,
		"  pos=", _player.global_position.snappedf(0.1))
