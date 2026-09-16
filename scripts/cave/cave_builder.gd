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
## Surfaces are tinted by the WORLD AXIS they face, not by how they look in isolation.
##
## The theme is degrees of freedom along X, Y and Z, so the cave states it directly: every
## floor is sand, every X-facing wall is teal, every Z-facing wall is violet. After a
## gravity shift a racer can read their new orientation off the colours around them without
## a single HUD element, which is the difference between the mechanic feeling clever and
## feeling disorienting.
const COLOUR_FLOOR := Color(0.82, 0.64, 0.42)
const COLOUR_CEILING := Color(0.24, 0.26, 0.40)
const COLOUR_WALL_X := Color(0.40, 0.58, 0.57)
const COLOUR_WALL_Z := Color(0.52, 0.46, 0.60)
const COLOUR_FINISH := Color(1.0, 0.72, 0.26)

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
			_texture_set(kind), _surface_colour(kind), _surface_uv_scale(kind)))
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

			var kind := "wallx" if dir_index <= CaveGraph.DIR_MINUS_X else "wallz"
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
		"wallx": return COLOUR_WALL_X
		_: return COLOUR_WALL_Z


func _texture_set(kind: String) -> String:
	match kind:
		"floor": return "stone_floor"
		"ceiling": return "stone_ceiling"
		_: return "stone_wall"


## Higher numbers tile the texture more often, so detail reads instead of smearing across
## a whole 8-unit slab.
func _surface_uv_scale(kind: String) -> float:
	return 0.45 if kind == "floor" or kind == "ceiling" else 0.42


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
		mat.normal_scale = 0.85

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
		mat.ao_light_affect = 0.15

	mat.roughness = 0.85
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
	mat.emission_energy_multiplier = 4.5

	# The exit is hidden by design, but once it is in line of sight it has to be
	# unmistakable. A short pillar read as scenery; this is a full-height column plus a
	# beam running to the ceiling, so it is visible down a corridor and through a shaft
	# from another level rather than only when you are standing on it.
	var column := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, CELL_SIZE * 0.55, 1.6)
	column.mesh = box
	column.material_override = mat
	column.position = Vector3(0.0, -CELL_SIZE * 0.5 + CELL_SIZE * 0.275, 0.0)
	area.add_child(column)

	var beam := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.35
	shaft.bottom_radius = 0.9
	shaft.height = CELL_SIZE
	shaft.radial_segments = 8
	beam.mesh = shaft
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(COLOUR_FINISH.r, COLOUR_FINISH.g, COLOUR_FINISH.b, 0.28)
	beam_mat.emission_enabled = true
	beam_mat.emission = COLOUR_FINISH
	beam_mat.emission_energy_multiplier = 5.0
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.mesh.material = beam_mat
	beam.position = Vector3.ZERO
	area.add_child(beam)

	var light := OmniLight3D.new()
	light.light_color = COLOUR_FINISH
	light.light_energy = 9.0
	light.omni_range = CELL_SIZE * 3.6
	light.position = Vector3(0.0, -CELL_SIZE * 0.5 + 4.5, 0.0)
	area.add_child(light)
	return area


## Torch lighting through the whole cave, tinted by depth.
##
## Each Y level gets its own light colour: deep levels burn warm amber, upper levels run
## pale and cold. In a game about moving vertically that gives a racer an instant read on
## how high they are without a single HUD element, and it stops 50-odd stone cells from
## looking like one continuous corridor.
## Near-white with only a slight bias per level. The surfaces already carry a strong
## colour code by axis; saturated lights on top of that would be two colour systems
## fighting over the same read, and orientation is the one that matters.
const LEVEL_LIGHT: Array[Color] = [
	Color(1.00, 0.90, 0.78),
	Color(1.00, 0.95, 0.88),
	Color(0.92, 0.96, 1.00),
	Color(0.88, 0.94, 1.00),
]


func _add_lights(graph: CaveGraph, root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Torches"
	root.add_child(holder)

	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.72, 0.34)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.66, 0.28)
	flame.emission_energy_multiplier = 4.0
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
		light.light_energy = 5.0 if junction else 3.8
		light.omni_range = CELL_SIZE * 2.6
		light.omni_attenuation = 1.5
		# Feeds the volumetric fog so each torch throws a visible shaft of light rather
		# than just brightening the stone around it.
		light.light_specular = 0.25
		# Shadows only at junctions: they are the expensive part and the places worth
		# spending it, since that is where geometry overlaps and depth needs reading.
		light.shadow_enabled = junction and placed % 3 == 0
		light.shadow_blur = 1.0
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


## Rock props scattered deterministically from the cave's own hash.
##
## The meshes come from tools/gen_rocks.py, built in Blender from primitives plus
## displacement. Every surface in this cave is an axis-aligned slab, which reads as a stack
## of boxes no matter how good the material is; these pieces break that silhouette so a
## corridor looks carved rather than built.
##
## All of it is visual only -- no collision -- so nothing here can block a route or wedge a
## racer. If the models are missing the cave still builds, just plainer, so a teammate who
## has not run the generator is never blocked.
const BOULDER_VARIANTS := 5
const PANEL_VARIANTS := 4
const SPIKE_VARIANTS := 3
const RUBBLE_VARIANTS := 4


func _add_detail(graph: CaveGraph, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = graph.graph_hash()

	# variant key -> transforms
	var boulders := {}
	var panels := {}
	var spikes := {}
	var rubble := {}
	var half := CELL_SIZE * 0.5

	for c: Vector3i in graph.cells:
		var centre := cell_to_world(c)

		if not graph.is_linked(c, CaveGraph.DIR_DOWN):
			for i in rng.randi_range(1, 3):
				var p := centre + Vector3(rng.randf_range(-half + 1.2, half - 1.2),
					-half + 0.45, rng.randf_range(-half + 1.2, half - 1.2))
				_bucket(boulders, rng.randi() % BOULDER_VARIANTS,
					_upright(p, rng, rng.randf_range(0.5, 1.4)))
			for i in rng.randi_range(2, 5):
				var p2 := centre + Vector3(rng.randf_range(-half + 0.8, half - 0.8),
					-half + 0.25, rng.randf_range(-half + 0.8, half - 0.8))
				_bucket(rubble, rng.randi() % RUBBLE_VARIANTS,
					_upright(p2, rng, rng.randf_range(0.3, 0.8)))

		if not graph.is_linked(c, CaveGraph.DIR_UP):
			for i in rng.randi_range(0, 3):
				var p3 := centre + Vector3(rng.randf_range(-half + 1.4, half - 1.4),
					half - 0.3, rng.randf_range(-half + 1.4, half - 1.4))
				# The spike models point up, so flip them to hang.
				var basis := Basis(Vector3.FORWARD, PI) * Basis(Vector3.UP,
					rng.randf_range(0.0, TAU))
				var size := rng.randf_range(0.5, 1.15)
				_bucket(spikes, rng.randi() % SPIKE_VARIANTS,
					Transform3D(basis.scaled(Vector3(size, rng.randf_range(0.6, 1.5), size)), p3))

		# Slabs pressed onto blank wall faces so a flat face catches light unevenly.
		for dir_index: int in CaveGraph.FLAT_DIRS:
			if graph.is_linked(c, dir_index):
				continue
			for i in rng.randi_range(1, 3):
				var normal := Vector3(CaveGraph.DIRS[dir_index])
				var along := Vector3(normal.z, 0.0, normal.x)
				var p4 := centre + normal * (half - 0.35) \
					+ along * rng.randf_range(-half + 1.6, half - 1.6) \
					+ Vector3(0.0, rng.randf_range(-half + 1.4, half - 1.4), 0.0)
				# Panel meshes lie flat with +Y as their face normal; stand one up against
				# the wall by pointing that axis back into the cell.
				var up := -normal
				var fwd := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.BACK
				fwd = (fwd - up * fwd.dot(up)).normalized()
				var right := fwd.cross(up).normalized()
				var b := Basis(right, up, -fwd).rotated(up, rng.randf_range(0.0, TAU))
				var sc := rng.randf_range(1.4, 2.6)
				var axis := "wallx" if dir_index <= CaveGraph.DIR_MINUS_X else "wallz"
				_bucket(panels, "%s|%d" % [axis, rng.randi() % PANEL_VARIANTS],
					Transform3D(b.scaled(Vector3(sc, rng.randf_range(0.6, 1.2), sc)), p4))

	var detail := Node3D.new()
	detail.name = "Detail"
	root.add_child(detail)
	_emit_props(detail, boulders, "boulder", "stone_floor", COLOUR_FLOOR)
	_emit_props(detail, rubble, "rubble", "stone_floor", COLOUR_FLOOR)
	_emit_props(detail, spikes, "stalactite", "stone_ceiling", COLOUR_CEILING)
	_emit_panels(detail, panels)


## Panels are keyed "axis|variant" so each one is emitted in its own wall's colour.
func _emit_panels(parent: Node3D, store: Dictionary) -> void:
	for key: String in store:
		var parts := key.split("|")
		var axis := parts[0]
		var mesh := _prop_mesh("wall_panel_%02d" % int(parts[1]))
		if mesh == null:
			continue
		var items: Array[Transform3D] = store[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i])
		var node := MultiMeshInstance3D.new()
		node.name = "panel_%s" % key.replace("|", "_")
		node.multimesh = mm
		node.material_override = _stone_material("stone_wall", _surface_colour(axis), 0.8)
		parent.add_child(node)


func _bucket(store: Dictionary, variant: Variant, xform: Transform3D) -> void:
	if not store.has(variant):
		store[variant] = [] as Array[Transform3D]
	store[variant].append(xform)


## A prop standing on a surface: random spin about up, slight tilt, uneven scale.
func _upright(pos: Vector3, rng: RandomNumberGenerator, size: float) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) \
		* Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)) \
		* Basis(Vector3.BACK, rng.randf_range(-0.3, 0.3))
	return Transform3D(basis.scaled(Vector3(size,
		size * rng.randf_range(0.6, 1.1), size * rng.randf_range(0.8, 1.2))), pos)


func _emit_props(parent: Node3D, store: Dictionary, prefix: String,
		texture_set: String, colour: Color) -> void:
	for variant: int in store:
		var mesh := _prop_mesh("%s_%02d" % [prefix, variant])
		if mesh == null:
			continue
		var items: Array[Transform3D] = store[variant]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i])
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%02d" % [prefix, variant]
		node.multimesh = mm
		node.material_override = _stone_material(texture_set, colour, 0.8)
		parent.add_child(node)


## Pull the mesh out of an imported glTF scene. Cached, since the same handful of props is
## instanced hundreds of times.
static var _prop_cache: Dictionary = {}

func _prop_mesh(name: String) -> Mesh:
	if _prop_cache.has(name):
		return _prop_cache[name]
	var path := "res://assets/models/%s.glb" % name
	if not ResourceLoader.exists(path):
		_prop_cache[name] = null
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		_prop_cache[name] = null
		return null
	var inst := scene.instantiate()
	var found: Mesh = null
	for child in inst.get_children():
		if child is MeshInstance3D:
			found = (child as MeshInstance3D).mesh
			break
	inst.free()
	_prop_cache[name] = found
	return found
