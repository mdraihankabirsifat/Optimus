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
## Physics layers: 1 is cave geometry, 2 is racers.
const LAYER_WORLD := 1
const LAYER_RACERS := 2
## Stand-on-able surfaces get a warm tone and overheads a cool one, so a racer who has
## just rotated their gravity still has an absolute reference for which way world-up is.
const COLOUR_FLOOR := Color(0.58, 0.47, 0.36)
const COLOUR_CEILING := Color(0.34, 0.39, 0.52)
const COLOUR_WALL := Color(0.46, 0.45, 0.43)
const COLOUR_FINISH := Color(1.0, 0.68, 0.22)

## Slabs bucketed by "kind|level". One MultiMesh per bucket rather than three spanning
## the whole cave: the GL Compatibility renderer picks lights PER OBJECT, so a single
## batch covering every floor in the cave gets lit by whichever lights happen to sit
## nearest its centre instead of the ones next to the surface you are standing on.
var _buckets: Dictionary = {}
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

	for key: String in _buckets:
		var parts := key.split("|")
		var kind := parts[0]
		root.add_child(_make_batch(
			"Batch_%s" % key.replace("|", "_"), _buckets[key],
			"stone_%s" % kind, _surface_colour(kind), _surface_uv_scale(kind)))
	root.add_child(_make_collision())
	root.add_child(_make_finish(graph))
	_add_lights(graph, root)
	_add_detail(graph, root)


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

			var kind := "wall"
			match dir_index:
				CaveGraph.DIR_DOWN:
					kind = "floor"
				CaveGraph.DIR_UP:
					# Shared horizontal boundary: if a cell sits above it, the slab is that
					# cell's floor and should read as one.
					kind = "floor" if graph.has_cell(
						c + CaveGraph.DIRS[CaveGraph.DIR_UP]) else "ceiling"
			var bucket := "%s|%d" % [kind, c.y]
			if not _buckets.has(bucket):
				_buckets[bucket] = [] as Array[Transform3D]
			_buckets[bucket].append(xform)

			_collision.append([size, centre])


## Normalises a face so the boundary between two cells maps to one key from either side.
func _boundary_key(c: Vector3i, dir_index: int) -> String:
	if dir_index % 2 == 0:
		return "%d,%d,%d,%d" % [c.x, c.y, c.z, dir_index]
	var n: Vector3i = c + CaveGraph.DIRS[dir_index]
	return "%d,%d,%d,%d" % [n.x, n.y, n.z, dir_index - 1]


func _surface_colour(kind: String) -> Color:
	match kind:
		"floor": return COLOUR_FLOOR
		"ceiling": return COLOUR_CEILING
		_: return COLOUR_WALL


## Higher numbers tile the texture more often, so detail reads instead of smearing across
## a whole 8-unit slab.
func _surface_uv_scale(kind: String) -> float:
	return 0.42 if kind == "wall" else 0.45


func _slab_size(dir_index: int) -> Vector3:
	match dir_index:
		CaveGraph.DIR_PLUS_X, CaveGraph.DIR_MINUS_X:
			return Vector3(WALL_THICKNESS, CELL_SIZE, CELL_SIZE)
		CaveGraph.DIR_UP, CaveGraph.DIR_DOWN:
			return Vector3(CELL_SIZE, WALL_THICKNESS, CELL_SIZE)
		_:
			return Vector3(CELL_SIZE, CELL_SIZE, WALL_THICKNESS)


func _make_batch(name: String, slabs: Array[Transform3D], texture_set: String,
		colour: Color, uv_scale: float) -> MultiMeshInstance3D:
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
	node.material_override = _stone_material(texture_set, colour, uv_scale)
	return node


## Stone built from the generated texture set in assets/textures.
##
## The normal map is the part that matters. Without it every slab in the cave is lit dead
## flat regardless of how much geometry sits behind it, which is what made the first pass
## read as untextured boxes. Regenerate the maps with tools/gen_textures.py.
##
## Triplanar because the slabs are unit cubes scaled to size by the MultiMesh, so their
## UVs are stretched by wildly different amounts and a flat UV map would smear.
func _stone_material(texture_set: String, colour: Color, uv_scale: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.albedo_texture = _load_texture(texture_set, "albedo")

	var normal := _load_texture(texture_set, "normal")
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 2.2

	var rough := _load_texture(texture_set, "rough")
	if rough != null:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE

	var ao := _load_texture(texture_set, "ao")
	if ao != null:
		mat.ao_enabled = true
		mat.ao_texture = ao
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		# Cavity shading should darken the creases without flattening the lighting.
		mat.ao_light_affect = 0.35

	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.uv1_triplanar = true
	return mat


## Missing textures are survivable -- the cave still builds, just untextured -- so a
## teammate who has not run the generator yet is not blocked.
func _load_texture(texture_set: String, map: String) -> Texture2D:
	var path := "res://assets/textures/%s_%s.png" % [texture_set, map]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _make_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CaveCollision"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
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

	# Fills the cell rather than sitting in the middle of it. A 60% box let racers stand
	# on the ceiling or against a wall inside the finish cell without ever triggering it,
	# which meant a race that could not be won.
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL_SIZE * 0.95, CELL_SIZE * 0.95, CELL_SIZE * 0.95)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	area.collision_layer = 0
	area.collision_mask = LAYER_RACERS

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


## Torch lighting through the whole cave, tinted by depth.
##
## Each Y level gets its own light colour: deep levels burn warm amber, upper levels run
## pale and cold. In a game about moving vertically that gives a racer an instant read on
## how high they are without a single HUD element, and it stops 50-odd stone cells from
## looking like one continuous corridor.
const LEVEL_LIGHT: Array[Color] = [
	Color(1.00, 0.68, 0.36),
	Color(1.00, 0.84, 0.60),
	Color(0.82, 0.90, 1.00),
	Color(0.70, 0.88, 1.05),
]


func _add_lights(graph: CaveGraph, root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Torches"
	root.add_child(holder)

	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.72, 0.34)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.66, 0.28)
	flame.emission_energy_multiplier = 3.0
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var cells: Array = graph.cells.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y: return a.y < b.y
		if a.x != b.x: return a.x < b.x
		return a.z < b.z)

	var placed := 0
	for cell: Vector3i in cells:
		# Deterministic scatter, denser at junctions where players stop to decide.
		var junction := graph.degrees_of_freedom(cell) >= 3
		var step: int = 2 if junction else 3
		if (cell.x + cell.y * 2 + cell.z) % step != 0:
			continue

		var tint: Color = LEVEL_LIGHT[clampi(cell.y, 0, LEVEL_LIGHT.size() - 1)]
		var base := cell_to_world(cell) + Vector3(0.0, CELL_SIZE * 0.22, 0.0)

		var light := OmniLight3D.new()
		light.position = base
		light.light_color = tint
		light.light_energy = 4.4 if junction else 3.3
		light.omni_range = CELL_SIZE * 1.7
		light.omni_attenuation = 1.4
		# Shadows only at junctions: they are the expensive part and the places worth
		# spending it, since that is where geometry overlaps and depth needs reading.
		light.shadow_enabled = junction and placed % 3 == 0
		holder.add_child(light)

		var bulb := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.22
		m.height = 0.44
		bulb.mesh = m
		bulb.material_override = flame
		bulb.position = base
		holder.add_child(bulb)
		placed += 1


## Rubble, stalactites and wall studs scattered deterministically from the cave's own hash.
##
## Every surface in this cave is an axis-aligned slab, which reads as a stack of boxes no
## matter how good the material is. These pieces are purely visual -- no collision, so they
## can never block a route or wedge a racer -- and they exist to break the silhouette of a
## corridor so it looks carved rather than built.
func _add_detail(graph: CaveGraph, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = graph.graph_hash()

	var rubble: Array[Transform3D] = []
	var spikes: Array[Transform3D] = []
	var studs: Array[Transform3D] = []
	var half := CELL_SIZE * 0.5

	for c: Vector3i in graph.cells:
		var centre := cell_to_world(c)

		if not graph.is_linked(c, CaveGraph.DIR_DOWN):
			for i in rng.randi_range(1, 4):
				var p := centre + Vector3(
					rng.randf_range(-half + 1.0, half - 1.0), -half + 0.5,
					rng.randf_range(-half + 1.0, half - 1.0))
				rubble.append(_scatter(p, rng, rng.randf_range(0.35, 1.15)))

		if not graph.is_linked(c, CaveGraph.DIR_UP):
			for i in rng.randi_range(0, 3):
				var p := centre + Vector3(
					rng.randf_range(-half + 1.2, half - 1.2), half - 0.4,
					rng.randf_range(-half + 1.2, half - 1.2))
				var len := rng.randf_range(0.7, 2.1)
				spikes.append(Transform3D(
					Basis().scaled(Vector3(rng.randf_range(0.3, 0.6), len,
						rng.randf_range(0.3, 0.6))), p))

		# Shallow slabs pressed into the walls, so a flat face catches light unevenly.
		for dir_index: int in CaveGraph.FLAT_DIRS:
			if graph.is_linked(c, dir_index):
				continue
			if rng.randf() > 0.55:
				continue
			var normal := Vector3(CaveGraph.DIRS[dir_index])
			var along := Vector3(normal.z, 0.0, normal.x)
			var p := centre + normal * (half - 0.25) \
				+ along * rng.randf_range(-half + 1.5, half - 1.5) \
				+ Vector3(0.0, rng.randf_range(-half + 1.0, half - 1.0), 0.0)
			var thickness := normal.abs() * 0.5 + Vector3.ONE - normal.abs()
			studs.append(Transform3D(Basis().scaled(
				thickness * Vector3(rng.randf_range(1.2, 2.8), rng.randf_range(1.0, 2.6),
					rng.randf_range(1.2, 2.8))), p))

	var detail := Node3D.new()
	detail.name = "Detail"
	root.add_child(detail)
	detail.add_child(_detail_batch("Rubble", BoxMesh.new(), rubble, "stone_floor", COLOUR_FLOOR))
	detail.add_child(_detail_batch("Stalactites", _spike_mesh(), spikes, "stone_ceiling", COLOUR_CEILING))
	detail.add_child(_detail_batch("WallStuds", BoxMesh.new(), studs, "stone_wall", COLOUR_WALL))


## A chunk at a random orientation, so no two pieces read as the same box.
func _scatter(pos: Vector3, rng: RandomNumberGenerator, size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) \
		* Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)) \
		* Basis(Vector3.BACK, rng.randf_range(-0.5, 0.5))
	return Transform3D(basis.scaled(Vector3(size,
		size * rng.randf_range(0.5, 1.0), size * rng.randf_range(0.7, 1.3))), pos)


func _spike_mesh() -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 0
	return cone


func _detail_batch(name: String, mesh: Mesh, items: Array[Transform3D],
		texture_set: String, colour: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i])
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = _stone_material(texture_set, colour, 0.9)
	return node
