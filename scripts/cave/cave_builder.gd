class_name CaveBuilder
extends RefCounted
## Turns a CaveGraph into visible, walkable geometry. Makes no generation decisions --
## if you find yourself wanting randomness here, it belongs in CaveGenerator instead.
##
## Each cell is an 8x8x8 pocket of air. A wall slab is emitted on every cell face that has
## no connection, deduplicated so a boundary shared by two cells produces one slab rather
## than two coplanar ones.
##
## Visuals use three MultiMeshInstance3D batches (one draw call each) and collision is a
## single StaticBody3D holding box shapes, which keeps a ~250-slab cave cheap enough for
## the web export.

const CELL_SIZE := 8.0
const WALL_THICKNESS := 1.0
## Stand-on-able surfaces get a warm tone and overheads a cool one, so a racer who has
## just rotated their gravity still has an absolute reference for which way world-up is.
const COLOUR_FLOOR := Color(0.58, 0.47, 0.36)
const COLOUR_CEILING := Color(0.34, 0.39, 0.52)
const COLOUR_WALL := Color(0.46, 0.45, 0.43)
const COLOUR_FINISH := Color(1.0, 0.68, 0.22)

var _floor_slabs: Array[Transform3D] = []
var _ceiling_slabs: Array[Transform3D] = []
var _wall_slabs: Array[Transform3D] = []
var _collision: Array = []
var _seen_boundaries: Dictionary = {}


static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c) * CELL_SIZE


## Which logical cell a world position falls inside.
static func world_to_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		roundi(pos.x / CELL_SIZE), roundi(pos.y / CELL_SIZE), roundi(pos.z / CELL_SIZE))


## Where a racer's feet should land when spawning into a cell.
static func floor_position(c: Vector3i) -> Vector3:
	return cell_to_world(c) + Vector3(0.0, -CELL_SIZE * 0.5 + 1.0, 0.0)


func build(graph: CaveGraph, parent: Node3D) -> void:
	_collect_slabs(graph)

	var root := Node3D.new()
	root.name = "Cave"
	parent.add_child(root)

	root.add_child(_make_batch("FloorBatch", _floor_slabs, COLOUR_FLOOR, 0.18))
	root.add_child(_make_batch("CeilingBatch", _ceiling_slabs, COLOUR_CEILING, 0.18))
	root.add_child(_make_batch("WallBatch", _wall_slabs, COLOUR_WALL, 0.14))
	root.add_child(_make_collision())
	root.add_child(_make_finish(graph))
	_add_lights(graph, root)


func _collect_slabs(graph: CaveGraph) -> void:
	for c: Vector3i in graph.cells:
		for dir_index in 6:
			if graph.is_linked(c, dir_index):
				continue
			var key := _boundary_key(c, dir_index)
			if _seen_boundaries.has(key):
				continue
			_seen_boundaries[key] = true

			var size := _slab_size(dir_index)
			var centre: Vector3 = cell_to_world(c) \
				+ Vector3(CaveGraph.DIRS[dir_index]) * (CELL_SIZE * 0.5)
			var xform := Transform3D(Basis().scaled(size), centre)

			match dir_index:
				CaveGraph.DIR_DOWN:
					_floor_slabs.append(xform)
				CaveGraph.DIR_UP:
					# Shared horizontal boundary: if a cell sits above it, the slab is that
					# cell's floor and should read as one.
					if graph.has_cell(c + CaveGraph.DIRS[CaveGraph.DIR_UP]):
						_floor_slabs.append(xform)
					else:
						_ceiling_slabs.append(xform)
				_:
					_wall_slabs.append(xform)

			_collision.append([size, centre])


## Normalises a face so the boundary between two cells maps to one key from either side.
func _boundary_key(c: Vector3i, dir_index: int) -> String:
	if dir_index % 2 == 0:
		return "%d,%d,%d,%d" % [c.x, c.y, c.z, dir_index]
	var n: Vector3i = c + CaveGraph.DIRS[dir_index]
	return "%d,%d,%d,%d" % [n.x, n.y, n.z, dir_index - 1]


func _slab_size(dir_index: int) -> Vector3:
	match dir_index:
		CaveGraph.DIR_PLUS_X, CaveGraph.DIR_MINUS_X:
			return Vector3(WALL_THICKNESS, CELL_SIZE, CELL_SIZE)
		CaveGraph.DIR_UP, CaveGraph.DIR_DOWN:
			return Vector3(CELL_SIZE, WALL_THICKNESS, CELL_SIZE)
		_:
			return Vector3(CELL_SIZE, CELL_SIZE, WALL_THICKNESS)


func _make_batch(name: String, slabs: Array[Transform3D], colour: Color,
		noise_scale: float) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = slabs.size()
	for i in slabs.size():
		mm.set_instance_transform(i, slabs[i])

	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = _stone_material(colour, noise_scale)
	return node


## Procedural stone. Generated from noise at load time rather than shipped as a texture --
## no files to license or credit, and nothing added to the web build's download size.
func _stone_material(colour: Color, uv_scale: float) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 5

	# Raw noise runs the full 0-1 range, which multiplies the albedo down to black in the
	# troughs and reads as camouflage rather than rock. Compressing it to 0.74-1.0 leaves a
	# mottle that suggests surface detail without fighting the colour coding.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.74, 0.74, 0.74))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))

	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.width = 256
	tex.height = 256
	tex.seamless = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.uv1_triplanar = true
	mat.roughness = 0.95
	return mat


func _make_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CaveCollision"
	for entry: Array in _collision:
		var shape := BoxShape3D.new()
		shape.size = entry[0]
		var node := CollisionShape3D.new()
		node.shape = shape
		node.position = entry[1]
		body.add_child(node)
	return body


func _make_finish(graph: CaveGraph) -> Area3D:
	var area := Area3D.new()
	area.name = "FinishArea"
	area.position = cell_to_world(graph.finish_cell)
	area.add_to_group("finish_area")

	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL_SIZE * 0.6, CELL_SIZE * 0.6, CELL_SIZE * 0.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOUR_FINISH
	mat.emission_enabled = true
	mat.emission = COLOUR_FINISH
	mat.emission_energy_multiplier = 2.5

	# A pillar standing on the cell floor rather than a cube floating at its centre, so it
	# reads as a landmark down a corridor instead of swallowing the camera on arrival.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 4.0, 2.0)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = Vector3(0.0, -CELL_SIZE * 0.5 + 2.0, 0.0)
	area.add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = COLOUR_FINISH
	light.light_energy = 4.0
	light.omni_range = CELL_SIZE * 2.5
	light.position = Vector3(0.0, -CELL_SIZE * 0.5 + 4.5, 0.0)
	area.add_child(light)
	return area


## Sparse lighting along the guaranteed route. GL Compatibility limits how many lights can
## affect one object, so this stays deliberately thin and leans on ambient instead.
func _add_lights(graph: CaveGraph, root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Lights"
	root.add_child(holder)

	var step: int = maxi(1, graph.spine.size() / 6)
	for i in range(0, graph.spine.size(), step):
		var light := OmniLight3D.new()
		light.position = cell_to_world(graph.spine[i]) + Vector3(0.0, 1.5, 0.0)
		light.light_energy = 2.4
		light.omni_range = CELL_SIZE * 1.8
		light.light_color = Color(1.0, 0.92, 0.78)
		holder.add_child(light)
