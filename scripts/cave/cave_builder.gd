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


## `match_seed` fixes mystery box outcomes. Pass -1 to build bare geometry with no
## hazards, boxes or decor (the gravity test chamber and some harnesses want that).
func build(graph: CaveGraph, parent: Node3D, match_seed: int = 0) -> void:
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
	if match_seed >= 0:
		_add_features(graph, root, match_seed)


## Fire, boxes and set dressing, exactly where the generator put them. Offsets are derived
## from the stored variant, never rolled here, so every machine builds the same cave.
func _add_features(graph: CaveGraph, root: Node3D, match_seed: int) -> void:
	var holder := Node3D.new()
	holder.name = "Features"
	root.add_child(holder)

	for i in graph.hazards.size():
		var h: Dictionary = graph.hazards[i]
		var fire := FireHazard.create(i, int(h["side"]))
		fire.position += cell_to_world(h["cell"])
		holder.add_child(fire)

	var finish_pos := cell_to_world(graph.finish_cell)
	for b: Dictionary in graph.boxes:
		var box := MysteryBox.create(int(b["index"]), match_seed, int(b["corner"]), finish_pos)
		box.position += cell_to_world(b["cell"])
		holder.add_child(box)

	var kit := _decor_kit()
	for d: Dictionary in graph.decor:
		var node := _make_decor(graph, d, kit)
		if node != null:
			holder.add_child(node)


func _decor_kit() -> Dictionary:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.40, 0.34, 0.28)
	rock.roughness = 1.0
	var moss := StandardMaterial3D.new()
	moss.albedo_color = Color(0.25, 0.42, 0.18)
	moss.emission_enabled = true
	moss.emission = Color(0.2, 0.5, 0.15)
	moss.emission_energy_multiplier = 0.25
	var ember := _glow(Color(1.0, 0.42, 0.1), 2.4)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.18, 0.09)
	var crystals: Array[StandardMaterial3D] = [
		_glow(Color(0.35, 0.8, 1.0), 1.8), _glow(Color(0.7, 0.4, 1.0), 1.8),
		_glow(Color(0.4, 1.0, 0.6), 1.6), _glow(Color(1.0, 0.45, 0.7), 1.6),
	]
	return {"rock": rock, "moss": moss, "ember": ember, "wood": wood,
		"flame": _glow(Color(1.0, 0.6, 0.15), 3.0), "crystals": crystals}


func _glow(colour: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	return m


func _make_decor(graph: CaveGraph, d: Dictionary, kit: Dictionary) -> Node3D:
	var c: Vector3i = d["cell"]
	var v: int = int(d["variant"])
	var kind: String = d["kind"]
	var centre := cell_to_world(c)
	var floor_y := -CELL_SIZE * 0.5 + WALL_THICKNESS * 0.5
	var ceil_y := CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5
	# Hug a wall so decor never blocks the corridor centre or a box corner.
	var side := v % 4
	var along := (float((v * 37 + c.x * 11 + c.z * 7) % 5) - 2.0) * 0.8
	var edge := CELL_SIZE * 0.5 - 1.1
	var offsets := [Vector3(edge, 0, along), Vector3(-edge, 0, along),
		Vector3(along, 0, edge), Vector3(along, 0, -edge)]
	var off: Vector3 = offsets[side]
	var has_floor := not graph.is_linked(c, CaveGraph.DIR_DOWN)
	var has_ceiling := not graph.is_linked(c, CaveGraph.DIR_UP)

	var root := Node3D.new()
	match kind:
		"stalagmite", "stalactite":
			var hanging := kind == "stalactite"
			if (hanging and not has_ceiling) or (not hanging and not has_floor):
				return null
			var h := 1.2 + float(v % 4) * 0.45
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.0 if not hanging else 0.35 + float(v % 3) * 0.1
			mesh.bottom_radius = 0.35 + float(v % 3) * 0.1 if not hanging else 0.0
			mesh.height = h
			mesh.radial_segments = 7
			root.add_child(_mesh(mesh, kit["rock"], Vector3(0, h * 0.5 if not hanging else -h * 0.5, 0)))
			root.position = centre + off + Vector3(0, ceil_y if hanging else floor_y, 0)
		"crystal":
			if not has_floor:
				return null
			var crystals: Array = kit["crystals"]
			var mat: StandardMaterial3D = crystals[v % crystals.size()]
			for k in 3:
				var prism := PrismMesh.new()
				prism.size = Vector3(0.35, 0.9 + 0.35 * k, 0.35)
				var shard := _mesh(prism, mat, Vector3(0.3 * (k - 1), prism.size.y * 0.5, 0.2 * (k % 2)))
				shard.rotation = Vector3(0.0, float(k) * 1.1, 0.25 * float(k - 1))
				root.add_child(shard)
			root.position = centre + off + Vector3(0, floor_y, 0)
		"moss":
			if not has_floor:
				return null
			var patch := CylinderMesh.new()
			patch.top_radius = 1.1 + 0.2 * float(v)
			patch.bottom_radius = patch.top_radius
			patch.height = 0.06
			patch.radial_segments = 10
			root.add_child(_mesh(patch, kit["moss"], Vector3(0, 0.03, 0)))
			root.position = centre + off * 0.8 + Vector3(0, floor_y, 0)
		"ember":
			if not has_floor:
				return null
			for k in 4:
				var pebble := SphereMesh.new()
				pebble.radius = 0.16 + 0.05 * float((v + k) % 3)
				pebble.height = pebble.radius * 1.4
				root.add_child(_mesh(pebble, kit["ember"],
					Vector3(0.45 * cos(k * 1.7), 0.08, 0.45 * sin(k * 1.7))))
			root.position = centre + off + Vector3(0, floor_y, 0)
		"torch":
			# A torch on a wall that actually exists, at head height.
			var wall_dirs := [CaveGraph.DIR_PLUS_X, CaveGraph.DIR_MINUS_X,
				CaveGraph.DIR_PLUS_Z, CaveGraph.DIR_MINUS_Z]
			var wall := -1
			for k in 4:
				var candidate: int = wall_dirs[(v + k) % 4]
				if not graph.is_linked(c, candidate):
					wall = candidate
					break
			if wall == -1:
				return null
			var n := Vector3(CaveGraph.DIRS[wall])
			var stick := CylinderMesh.new()
			stick.top_radius = 0.09
			stick.bottom_radius = 0.06
			stick.height = 0.8
			root.add_child(_mesh(stick, kit["wood"], Vector3.ZERO))
			var flame := SphereMesh.new()
			flame.radius = 0.2
			flame.height = 0.5
			root.add_child(_mesh(flame, kit["flame"], Vector3(0, 0.55, 0)))
			root.position = centre + n * (CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5 - 0.25) \
				+ Vector3(0, floor_y + 2.4, 0)
		_:
			return null
	return root


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


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
