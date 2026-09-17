class_name CaveMetrics
extends RefCounted
## Shape statistics over many caves: how corridor-like, how looped, how layered. Used by
## tests/test_cave.gd to hold the generator to its cave-not-house targets, and by
## tests/cave_metrics.tscn to compare generator versions.

var caves := 0
var cells := 0
var junctions := 0
var dead_ends := 0
var cycles := 0
var run_total := 0
var runs := 0
var longest_run := 0
var levels := 0
var spine_ups := 0
var spine_downs := 0
var caves_up_and_down := 0
var caves_three_levels := 0
var junction_gap_total := 0
var junction_gaps := 0
## Prompt 3 navigability: hops from spawn to exit, fewest Moves needed, and how much of the
## cave is off the shortest route (branches and detours a racer can wander into).
var route_hops := 0
var min_moves := 0
var off_route_cells := 0
## Distribution of route lengths, for reporting spread rather than one lucky seed.
var route_list: Array[int] = []


func add(g: CaveGraph) -> void:
	caves += 1
	cells += g.cell_count()
	var from_spawn := g.distances_from(g.spawn_cell)
	var to_exit := g.distances_from(g.finish_cell)
	var hops: int = int(from_spawn.get(g.finish_cell, 0))
	route_hops += hops
	route_list.append(hops)
	min_moves += CaveValidator.min_moves_to_finish(g)
	for c: Vector3i in g.cells:
		if int(from_spawn.get(c, 0)) + int(to_exit.get(c, 0)) > hops:
			off_route_cells += 1
	cycles += g.cycle_count()
	var ys := {}
	for c: Vector3i in g.cells:
		ys[c.y] = true
		var degree := g.degree(c)
		if degree >= 3:
			junctions += 1
		elif degree == 1 and c != g.spawn_cell and c != g.finish_cell:
			dead_ends += 1
	levels += ys.size()
	if ys.size() >= 3:
		caves_three_levels += 1
	var run_stats := straight_runs(g)
	for r: int in run_stats:
		run_total += r
		runs += 1
		longest_run = maxi(longest_run, r)
	var ups := 0
	var downs := 0
	for i in range(1, g.spine.size()):
		var dy := g.spine[i].y - g.spine[i - 1].y
		if dy > 0:
			ups += 1
		elif dy < 0:
			downs += 1
	spine_ups += ups
	spine_downs += downs
	if ups > 0 and downs > 0:
		caves_up_and_down += 1
	var gaps := junction_gaps_along_spine(g)
	for gap: int in gaps:
		junction_gap_total += gap
		junction_gaps += 1


## Lengths, in cells, of maximal straight horizontal corridor runs: chains of cells that
## each connect only forward and back along one axis.
static func straight_runs(g: CaveGraph) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	for c: Vector3i in g.sorted_cells():
		var axis := g.straight_axis(c)
		if axis == -1 or seen.has(c):
			continue
		var d: Vector3i = CaveGraph.DIRS[axis]
		var start := c
		while g.straight_axis(start - d) == axis:
			start -= d
		var length := 0
		var cur := start
		while g.straight_axis(cur) == axis:
			seen[cur] = true
			length += 1
			cur += d
		out.append(length)
	return out


## Hops between consecutive junctions (degree 3+) along the guaranteed route.
static func junction_gaps_along_spine(g: CaveGraph) -> Array[int]:
	var out: Array[int] = []
	var last := -1
	for i in g.spine.size():
		if g.degree(g.spine[i]) >= 3:
			if last >= 0 and i - last > 0:
				out.append(i - last)
			last = i
	return out


func average_run() -> float:
	return float(run_total) / maxf(1.0, float(runs))


func average_junction_gap() -> float:
	return float(junction_gap_total) / maxf(1.0, float(junction_gaps))


func report() -> String:
	var n := maxf(1.0, float(caves))
	return "\n".join([
		"caves %d" % caves,
		"cells/cave %.1f   junctions/cave %.1f   dead ends/cave %.1f   cycles/cave %.1f"
			% [cells / n, junctions / n, dead_ends / n, cycles / n],
		"junction share %.0f%%" % [100.0 * junctions / maxf(1.0, float(cells))],
		"route hops avg %.1f (min %d, median %d, max %d)   Moves needed avg %.2f   off-route cells %.0f%%"
			% [route_hops / n, _pct(0.0), _pct(0.5), _pct(1.0), min_moves / n, 100.0 * off_route_cells / maxf(1.0, float(cells))],
		"straight run avg %.2f cells, longest %d" % [average_run(), longest_run],
		"spine hops between junctions avg %.2f" % average_junction_gap(),
		"levels/cave %.2f   caves with 3+ levels %d   spine ups %.2f downs %.2f   caves climbing AND descending %d"
			% [levels / n, caves_three_levels, spine_ups / n, spine_downs / n, caves_up_and_down],
	])


func _pct(q: float) -> int:
	if route_list.is_empty():
		return 0
	var sorted := route_list.duplicate()
	sorted.sort()
	return sorted[clampi(roundi(q * float(sorted.size() - 1)), 0, sorted.size() - 1)]
