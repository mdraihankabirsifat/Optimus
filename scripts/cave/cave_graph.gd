class_name CaveGraph
extends RefCounted
## Pure data model of the cave. No nodes, no geometry, no randomness.
##
## A cell is a Vector3i lattice position holding an 8x8x8 pocket of air. A cell stores a
## 6-bit mask of which neighbours it connects to. Keeping this separate from geometry is
## what makes generation testable headlessly and cheap to send over the network -- a match
## ships a seed, not a level.
##
## See docs/ARCHITECTURE.md.

## Direction indices. opposite(i) == i ^ 1, so pairs must stay adjacent in this array.
const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const DIR_PLUS_X := 0
const DIR_MINUS_X := 1
const DIR_UP := 2
const DIR_DOWN := 3
const DIR_PLUS_Z := 4
const DIR_MINUS_Z := 5

## Horizontal directions only -- used by the spine walk.
const FLAT_DIRS: Array[int] = [DIR_PLUS_X, DIR_MINUS_X, DIR_PLUS_Z, DIR_MINUS_Z]

var cells: Dictionary = {}
var spawn_cell := Vector3i.ZERO
var finish_cell := Vector3i.ZERO
## The guaranteed spawn-to-finish route. Solvability is proven on this, by construction.
var spine: Array[Vector3i] = []

## Placement data decided by the generator and consumed by the builder. Pure data:
## the builder never chooses where anything goes.
## Fire patches: {"cell": Vector3i, "side": int 0-3}. `side` leaves one edge of the cell
## clear so a fire is a cost, never a wall.
var hazards: Array[Dictionary] = []
## Mystery boxes: {"cell": Vector3i, "corner": int 0-3, "index": int}
var boxes: Array[Dictionary] = []
## Set dressing: {"cell": Vector3i, "kind": String, "variant": int}
## kinds: stalagmite, stalactite, crystal, moss, torch, ember
var decor: Array[Dictionary] = []
## Gameplay features beyond fire and boxes: {"cell": Vector3i, "kind": String, ...}
## kinds: pad {axis}, wind {axis, sign}, piston {phase}, spider {axis},
## crumble (the floor of this cell over a shaft), shortcut (vertical link from this cell up),
## landmark {variant}. See CaveGenerator._place_features.
var features: Array[Dictionary] = []


## True when the cell is a straight horizontal corridor along one axis and nothing else.
## Returns the axis (DIR_PLUS_X or DIR_PLUS_Z) or -1.
func straight_axis(c: Vector3i) -> int:
	if not cells.has(c):
		return -1
	var mask := int(cells[c])
	if mask == (1 << DIR_PLUS_X) | (1 << DIR_MINUS_X):
		return DIR_PLUS_X
	if mask == (1 << DIR_PLUS_Z) | (1 << DIR_MINUS_Z):
		return DIR_PLUS_Z
	return -1


func features_at(c: Vector3i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in features:
		if f["cell"] == c:
			out.append(f)
	return out


## Number of open faces at a cell (its degree in the graph).
func degree(c: Vector3i) -> int:
	if not cells.has(c):
		return 0
	return _popcount(int(cells[c]))


func has_vertical_link(c: Vector3i) -> bool:
	return is_linked(c, DIR_UP) or is_linked(c, DIR_DOWN)


## Cells in a stable order, so anything iterating them is deterministic across machines.
func sorted_cells() -> Array:
	var keys: Array = cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x: return a.x < b.x
		if a.y != b.y: return a.y < b.y
		return a.z < b.z)
	return keys


static func opposite(dir_index: int) -> int:
	return dir_index ^ 1


func add_cell(c: Vector3i) -> void:
	if not cells.has(c):
		cells[c] = 0


func has_cell(c: Vector3i) -> bool:
	return cells.has(c)


func cell_count() -> int:
	return cells.size()


## Connect two adjacent cells in both directions. Returns false if they are not neighbours.
func link(a: Vector3i, b: Vector3i) -> bool:
	var delta := b - a
	var dir_index := DIRS.find(delta)
	if dir_index == -1:
		return false
	add_cell(a)
	add_cell(b)
	cells[a] = int(cells[a]) | (1 << dir_index)
	cells[b] = int(cells[b]) | (1 << opposite(dir_index))
	return true


func is_linked(c: Vector3i, dir_index: int) -> bool:
	if not cells.has(c):
		return false
	return (int(cells[c]) & (1 << dir_index)) != 0


func linked_neighbours(c: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not cells.has(c):
		return out
	for i in 6:
		if is_linked(c, i):
			out.append(c + DIRS[i])
	return out


func edge_count() -> int:
	var half := 0
	for c: Vector3i in cells:
		half += _popcount(int(cells[c]))
	@warning_ignore("integer_division")
	return half / 2


## Degrees of Freedom at this cell: how many of the three translational axes offer travel.
## This is the number the HUD shows as "DOF n" and it is the theme made literal.
func degrees_of_freedom(c: Vector3i) -> int:
	if not cells.has(c):
		return 0
	var mask := int(cells[c])
	var dof := 0
	if mask & 0b000011: dof += 1  # X axis
	if mask & 0b001100: dof += 1  # Y axis
	if mask & 0b110000: dof += 1  # Z axis
	return dof


## Breadth-first hop distance from origin to every reachable cell.
func distances_from(origin: Vector3i) -> Dictionary:
	var dist := {origin: 0}
	var queue: Array[Vector3i] = [origin]
	var head := 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		for n: Vector3i in linked_neighbours(c):
			if not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist


func is_fully_connected() -> bool:
	if cells.is_empty():
		return false
	return distances_from(spawn_cell).size() == cells.size()


## Independent cycles in a connected graph: E - V + 1.
## At least one is required so racers can loop back by a different route.
func cycle_count() -> int:
	return edge_count() - cell_count() + 1


## Upward transitions along the spine. Each one costs a Move charge, because an 8-unit
## climb cannot be jumped -- the racer must reorient gravity. This is the number that must
## stay within the starting charge budget.
func spine_climb_cost() -> int:
	var climbs := 0
	for i in range(1, spine.size()):
		if spine[i].y > spine[i - 1].y:
			climbs += 1
	return climbs


func vertical_link_count() -> int:
	var count := 0
	for c: Vector3i in cells:
		if is_linked(c, DIR_UP):
			count += 1
	return count


## Highest degrees-of-freedom value present anywhere in the cave.
func max_degrees_of_freedom() -> int:
	var best := 0
	for c: Vector3i in cells:
		best = maxi(best, degrees_of_freedom(c))
	return best


## Order-independent hash used in the multiplayer handshake. Two peers whose graph hashes
## differ are not playing the same cave and must not race.
func graph_hash() -> int:
	var keys: Array = cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x: return a.x < b.x
		if a.y != b.y: return a.y < b.y
		return a.z < b.z)
	var h := 17
	for c: Vector3i in keys:
		h = (h * 31 + c.x) & 0x7FFFFFFF
		h = (h * 31 + c.y) & 0x7FFFFFFF
		h = (h * 31 + c.z) & 0x7FFFFFFF
		h = (h * 31 + int(cells[c])) & 0x7FFFFFFF
	h = (h * 31 + spawn_cell.x + spawn_cell.y * 7 + spawn_cell.z * 13) & 0x7FFFFFFF
	h = (h * 31 + finish_cell.x + finish_cell.y * 7 + finish_cell.z * 13) & 0x7FFFFFFF
	return h


func _popcount(v: int) -> int:
	var n := 0
	var x := v
	while x != 0:
		n += x & 1
		x >>= 1
	return n
