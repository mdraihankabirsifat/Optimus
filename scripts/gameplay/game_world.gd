extends Node3D
## The race. Generates a seeded cave, builds it, places the racers, runs the match.
##
## Bots and remote players are not here yet; MatchController is already written for 2-5
## racers so they register alongside the local one without a rewrite.

## Leave true for a different cave every launch. Set false and pick a seed to reproduce a
## specific cave when chasing a bug.
@export var randomise_seed := true
@export var fixed_seed := 12345

var graph: CaveGraph
var seed_value: int

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
	match_controller.racer_finished.connect(_on_racer_finished)
	match_controller.match_ended.connect(_on_match_ended)
	match_controller.begin_countdown()


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
