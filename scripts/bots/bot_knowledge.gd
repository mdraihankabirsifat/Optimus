class_name BotKnowledge
extends RefCounted
## What one bot has personally discovered. This is the entire anti-cheat design.
##
## THIS FILE MUST NEVER HOLD A REFERENCE TO THE REAL CaveGraph. It is fed primitive
## observations -- a cell, its connection mask, whether the finish is visible from it --
## by whoever is driving the bot. It cannot look anything up for itself, so a planner
## reading this object cannot accidentally see the whole cave.
##
## If you ever find yourself wanting to pass the real graph in here to make something
## easier, that is the moment the race stops being fair. See docs/MVP_SCOPE.md.

## Cells the bot has actually stood in and observed, with their connection masks.
var discovered := CaveGraph.new()
## Cell -> number of times the bot has been there. Drives the revisit penalty.
var visits: Dictionary = {}
## Set only when the finish is genuinely observed. Until then the bot has no idea.
var exit_cell: Vector3i = Vector3i.ZERO
var exit_found: bool = false
## Cells where the bot has seen something that hurts. Planner treats them as expensive,
## not forbidden -- sometimes the only way on is through the fire.
var hazard_cells: Dictionary = {}
## A clue this bot earned from a box it opened itself: the same coarse compass direction and
## above/below hint a human sees on the HUD. Never a cell, never a distance.
var has_clue: bool = false
var clue_direction: Vector3 = Vector3.ZERO
var clue_vertical: int = 0
## The cell observed last tick. Without this, a bot standing still would count a new visit
## every physics frame and inflate the revisit penalty into the thousands.
var _last_cell: Vector3i = Vector3i(-9999, -9999, -9999)

## Prompt 3: passages this bot physically failed to get through, and until when (its own
## clock). Temporary on purpose: a racer standing in a doorway is gone a moment later.
var blocked: Dictionary = {}
var now: float = 0.0


func block_edge(cell: Vector3i, dir_index: int, seconds: float) -> void:
	blocked["%s|%d" % [cell, dir_index]] = now + seconds


func is_blocked(cell: Vector3i, dir_index: int) -> bool:
	var key := "%s|%d" % [cell, dir_index]
	if not blocked.has(key):
		return false
	if float(blocked[key]) <= now:
		blocked.erase(key)
		return false
	return true


## Record what the bot can see from where it is standing: this cell and which of its six
## faces are open. It learns that neighbours exist, but not what is inside them.
func observe(cell: Vector3i, connection_mask: int, finish_here: bool = false) -> void:
	discovered.add_cell(cell)
	discovered.cells[cell] = connection_mask
	if cell != _last_cell:
		visits[cell] = int(visits.get(cell, 0)) + 1
		_last_cell = cell

	if finish_here and not exit_found:
		exit_found = true
		exit_cell = cell


func observe_clue(direction: Vector3, vertical: int) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	has_clue = true
	clue_direction = flat.normalized()
	clue_vertical = clampi(vertical, -1, 1)


func observe_hazard(cell: Vector3i) -> void:
	hazard_cells[cell] = true


func is_hazard(cell: Vector3i) -> bool:
	return hazard_cells.has(cell)


func has_seen(cell: Vector3i) -> bool:
	return discovered.has_cell(cell)


func visit_count(cell: Vector3i) -> int:
	return int(visits.get(cell, 0))


## Cells the bot knows are reachable from somewhere it has been, but has never entered.
## These are the only places worth walking to when the exit is still unknown.
func frontiers() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var seen := {}
	for cell: Vector3i in discovered.cells:
		for dir_index in 6:
			if not discovered.is_linked(cell, dir_index):
				continue
			var neighbour: Vector3i = cell + CaveGraph.DIRS[dir_index]
			if discovered.has_cell(neighbour) or seen.has(neighbour):
				continue
			seen[neighbour] = true
			out.append(neighbour)
	return out


func has_unexplored() -> bool:
	return not frontiers().is_empty()
