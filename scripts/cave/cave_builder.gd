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
## Clear half-width of an ordinary tunnel cell and of a chamber (spawn, finish, landmarks).
const TUNNEL_HALF := AppConfig.CAVE_TUNNEL_WIDTH * 0.5
const CHAMBER_HALF := CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5
## Every cell's floor, tunnel or chamber, sits at the same height relative to its centre.
## Chambers grow up and out from it, so every doorway between cells is flush: no ledges.
const FLOOR_Y := -TUNNEL_HALF

## ART-012: the environment. Colours, stone, decor materials, lights and signature props all
## come from here; the geometry, hazards and boxes never depend on it.
var theme: CaveTheme = CaveTheme.stone_age()

var _floor_slabs: Array[Transform3D] = []
var _ceiling_slabs: Array[Transform3D] = []
var _wall_slabs: Array[Transform3D] = []
var _collision: Array = []
## Sloped doorway funnels in chambers: [PackedVector3Array quad, PackedVector3Array hull].
var _funnels: Array = []
## How far into a chamber a doorway funnel reaches. 2.5 against the 1.5 step is about 31
## degrees: walkable in any gravity.
const FUNNEL_RUN := 2.5
var _seen_boundaries: Dictionary = {}


static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c) * CELL_SIZE


## Which logical cell a world position falls inside.
static func world_to_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		roundi(pos.x / CELL_SIZE), roundi(pos.y / CELL_SIZE), roundi(pos.z / CELL_SIZE))


## Where a racer should be placed to land in a cell: just above a tunnel floor, which is also
## safely inside a chamber (it falls the extra distance).
static func floor_position(c: Vector3i) -> Vector3:
	return cell_to_world(c) + Vector3(0.0, -TUNNEL_HALF + 1.0, 0.0)


## Spawn, finish and landmark cells are chambers; every other cell is a narrow tunnel.
static func is_chamber(graph: CaveGraph, c: Vector3i) -> bool:
	if c == graph.spawn_cell or c == graph.finish_cell:
		return true
	for f: Dictionary in graph.features:
		if f["kind"] == "landmark" and f["cell"] == c:
			return true
	return false


## Clear half-width of a cell's open space, which is also its ceiling height.
static func half_extent(graph: CaveGraph, c: Vector3i) -> float:
	return CHAMBER_HALF if is_chamber(graph, c) else TUNNEL_HALF


## `match_seed` fixes mystery box outcomes. Pass -1 to build bare geometry with no
## hazards, boxes or decor (the gravity test chamber and some harnesses want that).
func build(graph: CaveGraph, parent: Node3D, match_seed: int = 0) -> void:
	_collect_slabs(graph)

	var root := Node3D.new()
	root.name = "Cave"
	parent.add_child(root)

	root.add_child(_make_batch("FloorBatch", _floor_slabs, theme.floor_colour, 0.18))
	root.add_child(_make_batch("CeilingBatch", _ceiling_slabs, theme.ceiling_colour, 0.18))
	root.add_child(_make_batch("WallBatch", _wall_slabs, theme.wall_colour, 0.14))
	root.add_child(_make_collision())
	if not _funnels.is_empty():
		root.add_child(_make_funnel_mesh())
	root.add_child(_make_finish(graph))
	_add_lights(graph, root)
	if match_seed >= 0:
		_add_features(graph, root, match_seed)
		_add_gameplay_features(graph, root)
		_add_spawn_gates(graph, root)
		_stage_finish(graph, root)
		_stage_shafts(graph, root)
		_add_signature_props(graph, root)
	_add_rock_dressing(graph, root)


## Pads, wind, pistons, spiders, crumbling covers, shortcut markers and landmarks.
func _add_gameplay_features(graph: CaveGraph, root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "GameplayFeatures"
	root.add_child(holder)
	var ids := 0
	for f: Dictionary in graph.features:
		var c: Vector3i = f["cell"]
		var h := half_extent(graph, c)
		var node: Node3D = null
		match f["kind"]:
			"pad": node = BoostPad.create(c, int(f["axis"]), h)
			"wind": node = WindZone.create(c, int(f["axis"]), int(f["sign"]), h)
			"piston": node = PistonHazard.create(ids, c, int(f["phase"]), h)
			"spider": node = SpiderEnemy.create(ids, c, int(f["axis"]), int(f.get("span", 3)), int(f.get("shift", 0)), h)
			"crumble": node = CrumbleTile.create(c)
			"shortcut": node = _make_shortcut_marker(c, h)
			"landmark": node = _make_landmark(graph, c, int(f["variant"]))
		ids += 1
		if node != null:
			holder.add_child(node)


func _add_spawn_gates(graph: CaveGraph, root: Node3D) -> void:
	for dir_index: int in CaveGraph.FLAT_DIRS:
		if graph.is_linked(graph.spawn_cell, dir_index):
			root.add_child(SpawnGate.create(graph.spawn_cell, dir_index))


## ART-009 / VFX-006: the exit should feel like an arrival. Standing stones, a pale beam
## rising from the pillar, embers drifting up. All of it stays inside the finish cell, so it
## is only ever seen by someone who has already found the way in.
func _stage_finish(graph: CaveGraph, root: Node3D) -> void:
	var stage := Node3D.new()
	stage.name = "FinishStage"
	stage.position = cell_to_world(graph.finish_cell)
	root.add_child(stage)
	var floor_y := FLOOR_Y
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.42, 0.36, 0.3)
	var rune := _glow(COLOUR_FINISH, 1.2)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var slab := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.7, 1.6 + 0.4 * float(i % 2), 0.35)
		slab.mesh = m
		slab.material_override = stone
		slab.position = Vector3(cos(a) * 3.0, floor_y + m.size.y * 0.5, sin(a) * 3.0)
		slab.rotation.y = -a + PI * 0.5
		stage.add_child(slab)
		var glyph := MeshInstance3D.new()
		var g := BoxMesh.new()
		g.size = Vector3(0.25, 0.5, 0.05)
		glyph.mesh = g
		glyph.material_override = rune
		glyph.position = Vector3(0.0, 0.2, -0.2)
		slab.add_child(glyph)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 0.9
	cyl.height = maxf(1.0, CHAMBER_HALF - FLOOR_Y - 4.0)
	beam.mesh = cyl
	beam.material_override = _beam_material(COLOUR_FINISH, 0.08)
	beam.position.y = floor_y + 4.0 + cyl.height * 0.5
	stage.add_child(beam)
	var embers := CPUParticles3D.new()
	embers.amount = 30
	embers.lifetime = 2.6
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 2.4
	embers.direction = Vector3(0, 1, 0)
	embers.gravity = Vector3(0, 0.5, 0)
	embers.initial_velocity_min = 0.3
	embers.initial_velocity_max = 1.0
	var spark := BoxMesh.new()
	spark.size = Vector3.ONE * 0.08
	spark.material = _glow(COLOUR_FINISH, 1.5)
	embers.mesh = spark
	embers.position.y = floor_y + 1.0
	stage.add_child(embers)


## LEVEL-012: every shaft gets a pale column of light through it and glowing lips on the
## opening above, so vertical routes read as deliberate moments from a distance.
func _stage_shafts(graph: CaveGraph, root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Shafts"
	root.add_child(holder)
	var beam_mat := _beam_material(Color(0.6, 0.8, 1.0), 0.025)
	var lip_mat := _glow(Color(0.35, 0.65, 0.95), 0.7)
	for c: Vector3i in graph.sorted_cells():
		if not graph.is_linked(c, CaveGraph.DIR_UP):
			continue
		var h := half_extent(graph, c)
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = TUNNEL_HALF - 0.3
		cyl.bottom_radius = TUNNEL_HALF - 0.6
		cyl.height = CELL_SIZE
		cyl.radial_segments = 12
		beam.mesh = cyl
		beam.material_override = beam_mat
		beam.position = cell_to_world(c) + Vector3(0.0, CELL_SIZE * 0.5, 0.0)
		holder.add_child(beam)
		for k in 4:
			var lip := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(TUNNEL_HALF * 2.0, 0.12, 0.12) if k < 2 else Vector3(0.12, 0.12, TUNNEL_HALF * 2.0)
			lip.mesh = m
			lip.material_override = lip_mat
			var edge := TUNNEL_HALF - 0.06
			var offs := [Vector3(0, 0, edge), Vector3(0, 0, -edge), Vector3(edge, 0, 0), Vector3(-edge, 0, 0)]
			lip.position = cell_to_world(c) + Vector3(0.0, h - 0.06, 0.0) + offs[k]
			holder.add_child(lip)


## FUN-004: a ring of upward chevrons under a shaft that saves a long walk. It says "this
## costs a Move and is worth it", nothing about where the exit is.
func _make_shortcut_marker(c: Vector3i, h: float = CHAMBER_HALF) -> Node3D:
	var marker := Node3D.new()
	marker.position = cell_to_world(c) + Vector3(0.0, FLOOR_Y + 0.05, 0.0)
	var mat := _glow(Color(0.3, 0.85, 0.55), 0.9)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = minf(1.9, h - 0.35)
	torus.outer_radius = minf(2.15, h - 0.1)
	ring.mesh = torus
	ring.material_override = mat
	marker.add_child(ring)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var arrow := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.6, 0.8, 0.1)
		arrow.mesh = prism
		arrow.material_override = mat
		arrow.position = Vector3(cos(a) * 1.2, 0.45, sin(a) * 1.2)
		arrow.rotation.y = -a
		marker.add_child(arrow)
	var label := Label3D.new()
	label.text = "SHORTCUT"
	label.font_size = 48
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.55, 1.0, 0.75)
	label.outline_size = 8
	label.position.y = 1.6
	marker.add_child(label)
	return marker


## ART-005: three one-off chambers so a cave has places people can name.
func _make_landmark(graph: CaveGraph, c: Vector3i, variant: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Landmark%d" % variant
	node.position = cell_to_world(c)
	var floor_y := FLOOR_Y
	var corner := CELL_SIZE * 0.5 - 1.2
	var corners := [Vector3(corner, 0, corner), Vector3(-corner, 0, corner),
		Vector3(corner, 0, -corner), Vector3(-corner, 0, -corner)]
	match variant % 3:
		0:  # Crystal hollow
			var mat := _glow(Color(0.3, 0.6, 0.85), 0.9)
			for k in 4:
				for j in 4:
					var shard := MeshInstance3D.new()
					var prism := PrismMesh.new()
					prism.size = Vector3(0.5, 1.2 + 0.6 * float(j), 0.5)
					shard.mesh = prism
					shard.material_override = mat
					shard.position = corners[k] + Vector3(0.3 * cos(j * 1.9), floor_y + prism.size.y * 0.5, 0.3 * sin(j * 1.9))
					shard.rotation = Vector3(0.2 * sin(j), float(j), 0.25 * cos(j))
					node.add_child(shard)
				# One solid box per corner cluster, matching the shards' footprint.
				node.add_child(_solid_box(Vector3(1.2, 2.4, 1.2), corners[k] + Vector3(0, floor_y + 1.2, 0)))
			var core := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			core.mesh = sphere
			core.material_override = _glow(Color(0.55, 0.85, 1.0), 1.6)
			core.position.y = 0.8
			node.add_child(core)
		1:  # Pillar hall: corner columns that really are solid
			var stone := StandardMaterial3D.new()
			stone.albedo_color = Color(0.5, 0.45, 0.4)
			var body := StaticBody3D.new()
			body.collision_layer = LAYER_WORLD
			body.collision_mask = 0
			node.add_child(body)
			for k in 4:
				var col := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.55
				cyl.bottom_radius = 0.7
				cyl.height = CHAMBER_HALF - FLOOR_Y
				col.mesh = cyl
				col.material_override = stone
				col.position = corners[k] + Vector3(0.0, (CHAMBER_HALF + FLOOR_Y) * 0.5, 0.0)
				node.add_child(col)
				var shape := CollisionShape3D.new()
				var cs := CylinderShape3D.new()
				cs.radius = 0.65
				cs.height = cyl.height
				shape.shape = cs
				shape.position = corners[k] + Vector3(0.0, (CHAMBER_HALF + FLOOR_Y) * 0.5, 0.0)
				body.add_child(shape)
			var fallen := MeshInstance3D.new()
			var drum := CylinderMesh.new()
			drum.top_radius = 0.5
			drum.bottom_radius = 0.5
			drum.height = 3.2
			fallen.mesh = drum
			fallen.material_override = stone
			fallen.rotation.z = PI * 0.5
			fallen.position = Vector3(0.0, floor_y + 0.5, corner - 0.2)
			node.add_child(fallen)
		2:  # Still pool
			var water := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 2.6
			disc.bottom_radius = 2.6
			disc.height = 0.05
			disc.radial_segments = 32
			water.mesh = disc
			var wmat := StandardMaterial3D.new()
			wmat.albedo_color = Color(0.1, 0.3, 0.4, 0.75)
			wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wmat.metallic = 0.6
			wmat.roughness = 0.05
			wmat.emission_enabled = true
			wmat.emission = Color(0.1, 0.45, 0.55)
			wmat.emission_energy_multiplier = 0.6
			water.material_override = wmat
			water.position.y = floor_y + 0.04
			node.add_child(water)
			var rock := StandardMaterial3D.new()
			rock.albedo_color = Color(0.38, 0.33, 0.28)
			for k in 12:
				var a := TAU * float(k) / 12.0
				var pebble := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.3 + 0.1 * float(k % 3)
				sm.height = sm.radius * 1.2
				pebble.mesh = sm
				pebble.material_override = rock
				pebble.position = Vector3(cos(a) * 2.8, floor_y + 0.1, sin(a) * 2.8)
				node.add_child(pebble)
	return node


func _beam_material(colour: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(colour, alpha)
	return m


## Fire, boxes and set dressing, exactly where the generator put them. Offsets are derived
## from the stored variant, never rolled here, so every machine builds the same cave.
func _add_features(graph: CaveGraph, root: Node3D, match_seed: int) -> void:
	var holder := Node3D.new()
	holder.name = "Features"
	root.add_child(holder)

	for i in graph.hazards.size():
		var h: Dictionary = graph.hazards[i]
		var fire := FireHazard.create(i, int(h["side"]), half_extent(graph, h["cell"]))
		fire.position += cell_to_world(h["cell"])
		holder.add_child(fire)

	var finish_pos := cell_to_world(graph.finish_cell)
	for b: Dictionary in graph.boxes:
		var box := MysteryBox.create(int(b["index"]), match_seed, int(b["corner"]), finish_pos,
			half_extent(graph, b["cell"]))
		box.position += cell_to_world(b["cell"])
		holder.add_child(box)

	var kit := _decor_kit()
	for d: Dictionary in graph.decor:
		var node := _make_decor(graph, d, kit)
		if node != null:
			holder.add_child(node)


func _decor_kit() -> Dictionary:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = theme.rock_colour
	rock.roughness = 1.0
	var moss := StandardMaterial3D.new()
	moss.albedo_color = theme.moss_colour
	moss.emission_enabled = true
	moss.emission = theme.moss_colour.lightened(0.1)
	moss.emission_energy_multiplier = theme.moss_glow
	var ember := _glow(Color(0.9, 0.35, 0.08), 1.3)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.18, 0.09)
	var crystals: Array[StandardMaterial3D] = []
	for colour: Color in theme.crystal_colours:
		crystals.append(_glow(colour, 0.8))
	var crack := StandardMaterial3D.new()
	crack.albedo_color = Color(0.08, 0.06, 0.05)
	var streaks: Array[StandardMaterial3D] = [
		_glow(Color(0.35, 0.55, 0.5), 0.25), _glow(Color(0.6, 0.4, 0.25), 0.2), _glow(Color(0.5, 0.5, 0.6), 0.2),
	]
	return {"rock": rock, "moss": moss, "ember": ember, "wood": wood,
		"flame": _glow(theme.flame_colour, 1.6), "crystals": crystals,
		"torch_cone": _beam_material(theme.torch_light_colour, 0.02), "crack": crack, "streaks": streaks}


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
	var h := half_extent(graph, c)
	var floor_y := FLOOR_Y
	var ceil_y := h
	# Hug a wall so decor never blocks the corridor centre or a box corner.
	var side := v % 4
	var along := (float((v * 37 + c.x * 11 + c.z * 7) % 5) - 2.0) * 0.8 * (h / CHAMBER_HALF)
	var edge := h - 0.8
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
				root.free()  # nothing to place here; do not leak the node
				return null
			# Prompt 3: spikes are solid and sharp, so they live only in landmark chambers. In
			# a 4-unit tunnel one would close the wall or ceiling line a racer walks, and the
			# spawn and exit chambers stay free of anything that hurts.
			if not is_chamber(graph, c) or c == graph.spawn_cell or c == graph.finish_cell:
				root.free()  # nothing to place here; do not leak the node
				return null
			var spike := 1.2 + float(v % 4) * 0.45
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.0 if not hanging else 0.35 + float(v % 3) * 0.1
			mesh.bottom_radius = 0.35 + float(v % 3) * 0.1 if not hanging else 0.0
			mesh.height = spike
			mesh.radial_segments = 7
			root.add_child(_mesh(mesh, kit["rock"], Vector3(0, spike * 0.5 if not hanging else -spike * 0.5, 0)))
			root.add_child(SpikeHazard.create(absi(hash(c)) % 100000 * 2 + (1 if hanging else 0), spike,
				0.35 + float(v % 3) * 0.1, hanging))
			root.position = centre + off + Vector3(0, ceil_y if hanging else floor_y, 0)
		"crystal":
			if not has_floor or not is_chamber(graph, c):
				root.free()  # nothing to place here; do not leak the node
				return null
			var crystals: Array = kit["crystals"]
			var mat: StandardMaterial3D = crystals[v % crystals.size()]
			for k in 3:
				var prism := PrismMesh.new()
				prism.size = Vector3(0.35, 0.9 + 0.35 * k, 0.35)
				var shard := _mesh(prism, mat, Vector3(0.3 * (k - 1), prism.size.y * 0.5, 0.2 * (k % 2)))
				shard.rotation = Vector3(0.0, float(k) * 1.1, 0.25 * float(k - 1))
				root.add_child(shard)
			# Solid like it looks: one box around the cluster. Crystals are not hazards.
			root.add_child(_solid_box(Vector3(0.95, 1.45, 0.6), Vector3(0, 0.72, 0.1)))
			root.position = centre + off + Vector3(0, floor_y, 0)
		"moss":
			if not has_floor:
				root.free()  # nothing to place here; do not leak the node
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
				root.free()  # nothing to place here; do not leak the node
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
				root.free()  # nothing to place here; do not leak the node
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
			# VFX-007 / VFX-013: a flickering flame and a faint cone of light down the wall.
			var fire := CPUParticles3D.new()
			fire.amount = 14
			fire.lifetime = 0.5
			fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			fire.emission_sphere_radius = 0.12
			fire.direction = Vector3(0, 1, 0)
			fire.spread = 15.0
			fire.gravity = Vector3(0, 2.0, 0)
			fire.initial_velocity_min = 0.4
			fire.initial_velocity_max = 1.0
			fire.scale_amount_min = 0.6
			fire.scale_amount_max = 1.0
			var ember := BoxMesh.new()
			ember.size = Vector3.ONE * 0.1
			ember.material = kit["flame"]
			fire.mesh = ember
			fire.position.y = 0.6
			root.add_child(fire)
			var cone := MeshInstance3D.new()
			var cone_mesh := CylinderMesh.new()
			cone_mesh.top_radius = 0.2
			cone_mesh.bottom_radius = 1.6
			cone_mesh.height = 2.6
			cone_mesh.radial_segments = 10
			cone.mesh = cone_mesh
			cone.material_override = kit["torch_cone"]
			cone.position = Vector3(0, -0.6, 0) - n * 0.7
			root.add_child(cone)
			root.position = centre + n * (h - 0.25) \
				+ Vector3(0, floor_y + minf(2.4, h - FLOOR_Y - 1.2), 0)
		"walldetail":
			# ART-003: a crack or a mineral streak on a wall that actually exists.
			var walls := [CaveGraph.DIR_PLUS_X, CaveGraph.DIR_MINUS_X, CaveGraph.DIR_PLUS_Z, CaveGraph.DIR_MINUS_Z]
			var wall := -1
			for k in 4:
				var candidate: int = walls[(v + k) % 4]
				if not graph.is_linked(c, candidate):
					wall = candidate
					break
			if wall == -1:
				root.free()  # nothing to place here; do not leak the node
				return null
			var n := Vector3(CaveGraph.DIRS[wall])
			var right := n.cross(Vector3.UP).normalized()
			var streak := v % 3 == 0
			var mat: StandardMaterial3D = kit["streaks"][v % 3] if streak else kit["crack"]
			var segments := 1 if streak else 4
			var p := Vector3.ZERO
			for k in segments:
				var seg := MeshInstance3D.new()
				var m := BoxMesh.new()
				m.size = Vector3(0.18, 3.5, 0.03) if streak else Vector3(0.07, 1.1, 0.03)
				seg.mesh = m
				seg.material_override = mat
				var tilt := 0.0 if streak else (0.5 if k % 2 == 0 else -0.45)
				seg.basis = Basis.looking_at(-n, Vector3.UP) * Basis(Vector3(0, 0, 1), tilt)
				seg.position = p
				root.add_child(seg)
				p += Vector3.DOWN * 0.95 + right * (0.45 if k % 2 == 0 else -0.4)
			var height := minf(1.0 + float(v % 4) * 0.6 + 1.5, h - FLOOR_Y - 0.4)
			root.position = centre + n * (h - 0.02) \
				+ right * (float(v % 5) - 2.0) * (h / CHAMBER_HALF) + Vector3(0, floor_y + height, 0)
		_:
			root.free()  # nothing to place here; do not leak the node
			return null
	return root


func _solid_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	return body


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


func _collect_slabs(graph: CaveGraph) -> void:
	for c: Vector3i in graph.sorted_cells():
		var h := half_extent(graph, c)
		var centre := cell_to_world(c)
		# The open core of the cell. Floor always at FLOOR_Y; chambers are wider and taller.
		var lo := Vector3(-h, FLOOR_Y, -h)
		var hi := Vector3(h, h, h)
		for d in 6:
			var axis := d / 2  # 0 x, 1 y, 2 z
			var sgn := 1.0 if d % 2 == 0 else -1.0
			if not graph.is_linked(c, d):
				_face(centre, axis, sgn, lo, hi, 0.0)
				continue
			# A linked face: a doorway the size of a tunnel. A bigger core gets a frame around it.
			if _core_larger_than_tunnel(lo, hi, axis):
				_face(centre, axis, sgn, lo, hi, TUNNEL_HALF)
				_funnel(graph, c, centre, axis, sgn, lo, hi)
			_connector(centre, axis, sgn, lo, hi)


func _core_larger_than_tunnel(lo: Vector3, hi: Vector3, axis: int) -> bool:
	for k in 3:
		if k == axis:
			continue
		if lo[k] < -TUNNEL_HALF - 0.01 or hi[k] > TUNNEL_HALF + 0.01:
			return true
	return false


## The rock face of a cell's open core on one side. `hole` > 0 leaves a doorway of that
## half-size centred on the cell axis. Faces overlap at edges so no crack of void shows:
## Y faces reach over the X edges, Z faces over both.
func _face(centre: Vector3, axis: int, sgn: float, lo: Vector3, hi: Vector3, hole: float) -> void:
	var t := WALL_THICKNESS
	var elo := lo
	var ehi := hi
	if axis == 1:
		elo.x -= t
		ehi.x += t
	elif axis == 2:
		elo.x -= t
		ehi.x += t
		elo.y -= t
		ehi.y += t
	var others := [0, 1, 2]
	others.erase(axis)
	var u: int = others[0]
	var v: int = others[1]
	var depth := (hi[axis] if sgn > 0.0 else -lo[axis]) + t * 0.5
	if hole <= 0.0:
		_emit(centre, axis, sgn, depth, t, u, elo[u], ehi[u], v, elo[v], ehi[v])
		return
	_emit(centre, axis, sgn, depth, t, u, hole, ehi[u], v, elo[v], ehi[v])
	_emit(centre, axis, sgn, depth, t, u, elo[u], -hole, v, elo[v], ehi[v])
	_emit(centre, axis, sgn, depth, t, u, -hole, hole, v, hole, ehi[v])
	_emit(centre, axis, sgn, depth, t, u, -hole, hole, v, elo[v], -hole)


## The short tunnel from a cell's core out to the cell boundary, where the neighbour's own
## connector meets it. Four walls around a tunnel-sized opening. It starts at the core's
## open edge: starting past the core's wall thickness would leave a band open, and a racer
## walking the wall falls into it.
func _connector(centre: Vector3, axis: int, sgn: float, lo: Vector3, hi: Vector3) -> void:
	var t := WALL_THICKNESS
	var start: float = hi[axis] if sgn > 0.0 else -lo[axis]
	var end := CELL_SIZE * 0.5
	if end - start < 0.01:
		return
	var others := [0, 1, 2]
	others.erase(axis)
	var u: int = others[0]
	var v: int = others[1]
	var hc := TUNNEL_HALF
	for side in [1.0, -1.0]:
		# Walls normal to u span v fully (with corners); walls normal to v fill between them.
		_box(centre, axis, sgn, start, end, u, side * (hc + t * 0.5), t, v, 0.0, (hc + t) * 2.0)
		_box(centre, axis, sgn, start, end, v, side * (hc + t * 0.5), t, u, 0.0, hc * 2.0)


## A slab lying across a face: along the face normal at `depth`, spanning [a0,a1] on axis u
## and [b0,b1] on axis v.
func _emit(centre: Vector3, axis: int, sgn: float, depth: float, t: float,
		u: int, a0: float, a1: float, v: int, b0: float, b1: float) -> void:
	if a1 - a0 < 0.01 or b1 - b0 < 0.01:
		return
	var size := Vector3.ZERO
	var pos := Vector3.ZERO
	size[axis] = t
	pos[axis] = sgn * depth
	size[u] = a1 - a0
	pos[u] = (a0 + a1) * 0.5
	size[v] = b1 - b0
	pos[v] = (b0 + b1) * 0.5
	_add_slab(centre + pos, size, axis, sgn)


## A connector wall: runs along `axis` from start to end, sits at offset `at` on axis n with
## thickness t, and is `width` wide (centred on `mid`) on axis w.
func _box(centre: Vector3, axis: int, sgn: float, start: float, end: float,
		n: int, at: float, t: float, w: int, mid: float, width: float) -> void:
	var size := Vector3.ZERO
	var pos := Vector3.ZERO
	size[axis] = end - start
	pos[axis] = sgn * (start + end) * 0.5
	size[n] = t
	pos[n] = at
	size[w] = width
	pos[w] = mid
	_add_slab(centre + pos, size, n, signf(at))


## Sort a slab by which way its open side faces, so floors read warm and ceilings cool.
func _add_slab(pos: Vector3, size: Vector3, normal_axis: int, sgn: float) -> void:
	var xform := Transform3D(Basis().scaled(size), pos)
	if normal_axis == 1:
		# A slab below open space is a floor; above it, a ceiling.
		if sgn < 0.0:
			_floor_slabs.append(xform)
		else:
			_ceiling_slabs.append(xform)
	else:
		_wall_slabs.append(xform)
	_collision.append([size, pos])


func _make_batch(name: String, slabs: Array[Transform3D], colour: Color,
		noise_scale: float) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = slabs.size()
	for i in slabs.size():
		mm.set_instance_transform(i, slabs[i])
		# ART-001: every slab a slightly different stone. Derived from position, not rolled,
		# so the builder still makes no choices of its own.
		# One shade per cell, not per slab: per-slab shading striped tunnel floors like planks.
		var cell := world_to_cell(slabs[i].origin)
		var h: int = absi(hash(cell))
		var shade := 0.92 + float(h % 1000) / 1000.0 * 0.12
		var warmth := (float((h / 1000) % 100) / 100.0 - 0.5) * 0.05
		mm.set_instance_color(i, Color(shade + warmth, shade, shade - warmth))

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
	noise.frequency = theme.stone_frequency
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

	var bump_noise := FastNoiseLite.new()
	bump_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	bump_noise.frequency = theme.bump_frequency
	var bump := NoiseTexture2D.new()
	bump.noise = bump_noise
	bump.as_normal_map = true
	bump.bump_strength = theme.bump_strength
	bump.width = 256
	bump.height = 256
	bump.seamless = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.normal_enabled = true
	mat.normal_texture = bump
	mat.normal_scale = 0.7
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.uv1_triplanar = true
	mat.roughness = theme.roughness
	return mat


## A chamber is wider and taller than the tunnels leaving it, and a racer can walk any of its
## six faces. Where a face meets a doorway that difference is a 1.5 m ledge -- a wall to
## someone walking the ceiling toward it. Each doorway gets a funnel of four sloped sides
## from the chamber's full cross-section down to the tunnel mouth, so every face runs into
## the tunnel on a ramp. A side that is already flush (the shared floor) is left out, and so
## is a side facing another doorway -- sloping across it would block that tunnel's mouth.
func _funnel(graph: CaveGraph, c: Vector3i, centre: Vector3, axis: int, sgn: float, lo: Vector3, hi: Vector3) -> void:
	var depth: float = hi[axis] if sgn > 0.0 else -lo[axis]
	var start := depth - FUNNEL_RUN
	var others := [0, 1, 2]
	others.erase(axis)
	var t := TUNNEL_HALF
	for k: int in others:
		var m: int = others[0] if others[1] == k else others[1]
		for q in [1.0, -1.0]:
			var bound: float = hi[k] if q > 0.0 else lo[k]
			if absf(bound - q * t) < 0.01 or graph.is_linked(c, k * 2 + (0 if q > 0.0 else 1)):
				continue
			var pts := PackedVector3Array()
			for spec in [[start, bound, lo[m]], [start, bound, hi[m]], [depth, q * t, t], [depth, q * t, -t]]:
				var p := Vector3.ZERO
				p[axis] = sgn * float(spec[0])
				p[k] = float(spec[1])
				p[m] = float(spec[2])
				pts.append(centre + p)
			var hull := PackedVector3Array(pts)
			var back := Vector3.ZERO
			back[k] = q * WALL_THICKNESS * 0.6
			for p: Vector3 in pts:
				hull.append(p + back)
			_funnels.append([pts, hull, centre])


func _make_funnel_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in _funnels:
		var q: PackedVector3Array = f[0]
		var centre: Vector3 = f[2]
		var n := (q[1] - q[0]).cross(q[3] - q[0]).normalized()
		var mid := (q[0] + q[1] + q[2] + q[3]) * 0.25
		# Face the chamber's inside.
		var flip := n.dot(centre - mid) < 0.0
		if flip:
			n = -n
		var order := [0, 1, 2, 0, 2, 3] if not flip else [0, 2, 1, 0, 3, 2]
		for i: int in order:
			st.set_color(Color.WHITE)
			st.set_normal(n)
			st.add_vertex(q[i])
	var node := MeshInstance3D.new()
	node.name = "DoorwayFunnels"
	node.mesh = st.commit()
	node.material_override = _stone_material(theme.wall_colour, 0.14)
	return node


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
	for f: Array in _funnels:
		var hull := ConvexPolygonShape3D.new()
		hull.points = f[1]
		var node := CollisionShape3D.new()
		node.shape = hull
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
	mesh.position = Vector3(0.0, FLOOR_Y + 2.0, 0.0)
	area.add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = COLOUR_FINISH
	light.light_energy = 4.0
	light.omni_range = CELL_SIZE * 2.5
	light.position = Vector3(0.0, FLOOR_Y + 4.0, 0.0)
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
		light.light_energy = theme.route_light_energy
		light.omni_range = CELL_SIZE * 1.8
		light.light_color = theme.route_light_colour
		holder.add_child(light)


## ART-012: the one prop each environment adds on top of the shared decor. Placement is a
## pure function of the cell, never random, so every machine dresses the cave identically.
func _add_signature_props(graph: CaveGraph, root: Node3D) -> void:
	if theme.signature_props == "":
		return
	var holder := Node3D.new()
	holder.name = "ThemeProps"
	root.add_child(holder)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme.prop_colour
	mat.roughness = 0.9
	if theme.prop_glow > 0.0:
		mat.emission_enabled = true
		mat.emission = theme.prop_colour
		mat.emission_energy_multiplier = theme.prop_glow
	var glow_points: Array[Vector3] = []
	for c: Vector3i in graph.sorted_cells():
		if c == graph.spawn_cell or c == graph.finish_cell:
			continue
		var h: int = absi(hash(Vector4i(c.x, c.y, c.z, 91)))
		var centre := cell_to_world(c)
		var half := half_extent(graph, c)
		match theme.signature_props:
			"roots":
				if h % 3 != 0 or graph.is_linked(c, CaveGraph.DIR_UP):
					continue
				for k in 3 + h % 3:
					var strand_len := 1.2 + float((h >> (k * 3)) % 5) * 0.35
					var strand := CylinderMesh.new()
					strand.top_radius = 0.09
					strand.bottom_radius = 0.02
					strand.height = strand_len
					strand.radial_segments = 5
					var x := float((h >> (k * 2)) % 7 - 3) * 0.8 * (half / CHAMBER_HALF)
					var z := float((h >> (k * 2 + 5)) % 7 - 3) * 0.8 * (half / CHAMBER_HALF)
					var node := _mesh(strand, mat, centre + Vector3(x, half - strand_len * 0.5, z))
					node.rotation = Vector3(0.12 * float(k % 3 - 1), 0.0, 0.1 * float((k + 1) % 3 - 1))
					holder.add_child(node)
			"glowworms":
				if h % 2 != 0 or graph.is_linked(c, CaveGraph.DIR_UP):
					continue
				for k in 14:
					var hk: int = absi(hash(Vector2i(h, k)))
					glow_points.append(centre + Vector3((float(hk % 70) / 70.0 - 0.5) * (half * 2.0 - 0.3),
						half - 0.08, (float((hk / 70) % 70) / 70.0 - 0.5) * (half * 2.0 - 0.3)))
			"pipes":
				if h % 2 != 0:
					continue
				for wall: int in [CaveGraph.DIR_PLUS_X, CaveGraph.DIR_MINUS_X, CaveGraph.DIR_PLUS_Z, CaveGraph.DIR_MINUS_Z]:
					if graph.is_linked(c, wall):
						continue
					var n := Vector3(CaveGraph.DIRS[wall])
					var pipe := CylinderMesh.new()
					pipe.top_radius = 0.28
					pipe.bottom_radius = 0.28
					pipe.height = CELL_SIZE
					pipe.radial_segments = 10
					var node := _mesh(pipe, mat, centre + n * (half - 0.35)
						+ Vector3(0, half - 0.9, 0))
					# Lie along the wall: X walls run pipes along Z, Z walls along X.
					node.rotation = Vector3(PI * 0.5, 0, 0) if absf(n.x) > 0.5 else Vector3(0, 0, PI * 0.5)
					holder.add_child(node)
					break
	if not glow_points.is_empty():
		var dot := SphereMesh.new()
		dot.radius = 0.05
		dot.height = 0.1
		dot.radial_segments = 4
		dot.rings = 2
		dot.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = dot
		mm.instance_count = glow_points.size()
		for i in glow_points.size():
			mm.set_instance_transform(i, Transform3D(Basis(), glow_points[i]))
		var inst := MultiMeshInstance3D.new()
		inst.name = "GlowWorms"
		inst.multimesh = mm
		holder.add_child(inst)


## Prompt 2, believable cave: breaks up the box. Lumpy rock where walls meet floor and
## ceiling, bulges on flat walls, rubble along the floor edges. Visual only -- collision
## stays the simple slabs, so none of this can snag a racer or change a route. Placement is a
## pure function of the cell, so every machine dresses the cave identically.
func _add_rock_dressing(graph: CaveGraph, root: Node3D) -> void:
	var edge_rocks: Array[Transform3D] = []
	var rubble: Array[Transform3D] = []
	for c: Vector3i in graph.sorted_cells():
		var h := half_extent(graph, c)
		var centre := cell_to_world(c)
		var hash_base: int = absi(hash(Vector4i(c.x, c.y, c.z, 7)))
		var walls: Array[int] = []
		for d: int in CaveGraph.FLAT_DIRS:
			if not graph.is_linked(c, d):
				walls.append(d)
		var has_floor := not graph.is_linked(c, CaveGraph.DIR_DOWN)
		var has_ceiling := not graph.is_linked(c, CaveGraph.DIR_UP)
		for wi in walls.size():
			var n := Vector3(CaveGraph.DIRS[walls[wi]])
			var along := Vector3(absf(n.z), 0.0, absf(n.x))
			var k0: int = hash_base >> (wi * 3)
			# Rock along the ceiling edge of this wall.
			if has_ceiling:
				for j in 2:
					var r := 0.7 + float((k0 >> j) % 5) * 0.12
					var pos := centre + n * h + Vector3(0.0, h, 0.0) + along * (float((k0 >> (j + 2)) % 7) - 3.0) * (h / 3.2)
					edge_rocks.append(_rock_xform(pos, Vector3(r * 1.6, r * 0.8, r), float(k0 % 17) * 0.37 + float(j)))
			# Rock along the floor edge, lower and flatter so it never reads as a step.
			if has_floor:
				var r2 := 0.45 + float((k0 >> 5) % 4) * 0.1
				var pos2 := centre + n * h + Vector3(0.0, FLOOR_Y, 0.0) + along * (float((k0 >> 7) % 5) - 2.0) * (h / 2.2)
				edge_rocks.append(_rock_xform(pos2, Vector3(r2 * 1.8, r2 * 0.6, r2), float(k0 % 13) * 0.51))
				# Rubble: a few small stones near this wall.
				for j in 3:
					var q: int = absi(hash(Vector3i(k0, j, 3)))
					var rr := 0.1 + float(q % 5) * 0.04
					var off := n * (h - 0.35 - float(q % 3) * 0.12) + along * (float(q % 9) - 4.0) * (h / 5.0)
					rubble.append(_rock_xform(centre + off + Vector3(0.0, FLOOR_Y + rr * 0.4, 0.0),
						Vector3(rr * 1.3, rr * 0.8, rr), float(q % 11) * 0.6))
			# A bulge in the middle of a flat wall now and then.
			if (k0 >> 9) % 3 == 0:
				var rb := 0.9 + float((k0 >> 11) % 4) * 0.2
				var mid_y := (h + FLOOR_Y) * 0.5 + (float((k0 >> 13) % 5) - 2.0) * 0.3
				var posb := centre + n * (h + rb * 0.55) + Vector3(0.0, mid_y, 0.0) + along * (float((k0 >> 15) % 5) - 2.0) * 0.5
				edge_rocks.append(_rock_xform(posb, Vector3(rb, rb * 1.3, rb * 1.1), float(k0 % 23) * 0.3))
	root.add_child(_rock_batch("RockEdges", edge_rocks, theme.rock_colour.lerp(theme.wall_colour, 0.5)))
	root.add_child(_rock_batch("Rubble", rubble, theme.rock_colour))


func _rock_xform(pos: Vector3, scale: Vector3, spin: float) -> Transform3D:
	var basis := Basis(Vector3.UP, spin) * Basis(Vector3.RIGHT, spin * 0.37)
	return Transform3D(basis.scaled(scale), pos)


func _rock_batch(node_name: String, xforms: Array[Transform3D], colour: Color) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var q: int = absi(hash(xforms[i].origin))
		var shade := 0.8 + float(q % 100) / 100.0 * 0.3
		mm.set_instance_color(i, Color(shade, shade, shade))
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	var mat := _stone_material(colour, 0.35)
	mat.normal_scale = 1.0
	node.material_override = mat
	return node
