extends Node
## Visual check of the countdown and racing HUD.

var _world: Node3D

func _ready() -> void:
	_world = load("res://scenes/game/game_world.tscn").instantiate()
	_world.randomise_seed = false
	_world.fixed_seed = 4242
	add_child(_world)
	await get_tree().process_frame

	await _wait(0.4)
	_shot("match_01_countdown")
	await _wait(4.0)
	_shot("match_02_racing")
	get_tree().quit()

## Wall-clock, not frame counts. A 120 Hz display makes frame counting mean half the
## time you expect, which silently broke earlier captures.
func _wait(seconds: float) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(seconds).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/shots")
	get_viewport().get_texture().get_image().save_png("res://tests/shots/%s.png" % name)
	print("saved ", name)
