extends Node3D
## The race. Generates a seeded cave, builds it, places the racers, runs the match.
##
## Bots and remote players are not here yet; MatchController is already written for 2-5
## racers so they register alongside the local one without a rewrite.

## Leave true for a different cave every launch. Set false and pick a seed to reproduce a
## specific cave when chasing a bug.
@export var randomise_seed := true
@export var fixed_seed := 12345
## 1-4 bots, giving 2-5 total racers. Every match needs at least two.
@export_range(1, 4) var bot_count: int = 2

const BOT_COLOURS: Array[Color] = [
	Color(0.95, 0.45, 0.30),
	Color(0.50, 0.85, 0.45),
	Color(0.85, 0.60, 0.95),
	Color(0.95, 0.85, 0.35),
]
const BOT_NAMES: Array[String] = ["Rook", "Vex", "Nim", "Kilo"]

var graph: CaveGraph
var seed_value: int
var bots: Array[Node3D] = []

@onready var _player: PlayerController = $Player
@onready var match_controller: MatchController = $MatchController


func _ready() -> void:
	add_to_group("cave_root")

	seed_value = fixed_seed
	if randomise_seed:
		seed_value = randi() % 1000000

	var generator := CaveGenerator.new()
	graph = generator.generate(seed_value)
	if graph == null:
		push_error("Cave generation failed after %d attempts: %s"
			% [generator.attempts_used, generator.last_failure])
		return

	CaveBuilder.new().build(graph, self)
	_player.global_position = CaveBuilder.floor_position(graph.spawn_cell)

	print("seed %d | %d cells | %d hops to exit | %d Moves required | %d loops" % [
		seed_value,
		graph.cell_count(),
		int(graph.distances_from(graph.spawn_cell).get(graph.finish_cell, -1)),
		graph.spine_climb_cost(),
		graph.cycle_count(),
	])

	match_controller.register_racer(_player, "You")
	_spawn_bots()
	match_controller.racer_finished.connect(_on_racer_finished)
	match_controller.match_ended.connect(_on_match_ended)
	match_controller.begin_countdown()


## Bots spawn in a ring around the shared starting chamber so nobody begins inside
## anyone else, and every racer starts the same distance from the exit.
func _spawn_bots() -> void:
	var scene: PackedScene = load("res://scenes/bots/bot_player.tscn")
	var origin := CaveBuilder.floor_position(graph.spawn_cell)
	var count: int = clampi(bot_count, 1, 4)

	for i in count:
		var bot: Node3D = scene.instantiate()
		add_child(bot)
		var angle := TAU * float(i) / float(count)
		bot.global_position = origin + Vector3(cos(angle), 0.0, sin(angle)) * 1.8

		var controller: BotController = bot.get_node("BotController")
		controller.setup(graph, BOT_NAMES[i], BOT_COLOURS[i], i + 1)
		match_controller.register_racer(bot, BOT_NAMES[i], true)
		bots.append(bot)


func _on_racer_finished(racer_name: String, place: int, time: float) -> void:
	print("%s finished #%d in %s" % [racer_name, place, MatchController.format_time(time)])


func _on_match_ended(results: Array) -> void:
	print("--- results ---")
	for entry: Dictionary in results:
		if entry["finished"]:
			print("  #%d  %s  %s"
				% [entry["place"], entry["name"], MatchController.format_time(entry["finish_time"])])
		elif entry["eliminated"]:
			print("  --  %s  ELIMINATED at %s"
				% [entry["name"], MatchController.format_time(entry["elimination_time"])])
		else:
			print("  --  %s  DNF" % entry["name"])


## Degrees of Freedom at the racer's current cell: how many axes offer travel here.
## This is the theme stated as a number, and it is why the HUD shows it.
func player_degrees_of_freedom() -> int:
	if graph == null or _player == null:
		return 0
	return graph.degrees_of_freedom(CaveBuilder.world_to_cell(_player.global_position))


func player_cell() -> Vector3i:
	if _player == null:
		return Vector3i.ZERO
	return CaveBuilder.world_to_cell(_player.global_position)
