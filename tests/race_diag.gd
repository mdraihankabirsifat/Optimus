extends Node
## Runs a full bot race headless and prints the result. Use it to sanity-check bot
## behaviour after touching the planner, the cave, or the match rules.
## Run: godot --headless res://tests/race_diag.tscn

@export var cave_seed: int = 4242
@export var bots: int = 4
## Pass `-- skill=0` to watch Easy bots.
@export var skill: int = 2

var _world: Node3D
var _t := 0.0

func _ready() -> void:
	_world = load("res://scenes/game/game_world.tscn").instantiate()
	_world.randomise_seed = false
	_world.fixed_seed = cave_seed
	_world.bot_count = bots
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("skill="):
			skill = int(arg.trim_prefix("skill="))
		if arg.begins_with("seed="):
			cave_seed = int(arg.trim_prefix("seed="))
			_world.fixed_seed = cave_seed
	_world.bot_skill = skill
	add_child(_world)
	await get_tree().process_frame

	_world.match_controller.racer_finished.connect(
		func(n: String, p: int, t: float) -> void:
			print("  %d. %-5s %s" % [p, n, MatchController.format_time(t)]))

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 180.0:
		return
	print("\n  unfinished after 180s:")
	for b: Node3D in _world.bots:
		var c: BotController = b.get_node("BotController")
		print("    %-5s at %s, %d cells seen, %d Moves left" % [
			c.display_name, CaveBuilder.world_to_cell(b.global_position),
			c.knowledge.discovered.cell_count(),
			b.get_node("GravityController").charges])
	get_tree().quit()
