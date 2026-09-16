extends Node3D
## Playable procedural cave. Generates from a seed, builds geometry, drops the racer at
## the spawn chamber. This is the Phase 2 harness -- match rules, hazards and bots are not
## here yet. MatchController replaces this scene under MATCH-001.

## Leave true to get a different cave every launch. Set false and pick a seed to reproduce
## a specific cave when chasing a bug.
@export var randomise_seed := true
@export var fixed_seed := 12345

var graph: CaveGraph
var seed_value: int

@onready var _player: PlayerController = $Player


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
