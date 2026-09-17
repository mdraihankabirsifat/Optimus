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

## ART-012: the environment. Colours, stone, decor materials, lights and signature props all
## come from here; the geometry, hazards and boxes never depend on it.
var theme: CaveTheme = CaveTheme.stone_age()

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

	root.add_child(_make_batch("FloorBatch", _floor_slabs, theme.floor_colour, 0.18))
	root.add_child(_make_batch("CeilingBatch", _ceiling_slabs, theme.ceiling_colour, 0.18))
	root.add_child(_make_batch("WallBatch", _wall_slabs, theme.wall_colour, 0.14))
	root.add_child(_make_collision())
	root.add_child(_make_finish(graph))
	_add_lights(graph, root)
	if match_seed >= 0:
		_add_features(graph, root, match_seed)
		_add_gameplay_features(graph, root)
		_add_spawn_gates(graph, root)
		_stage_finish(graph, root)
		_stage_shafts(graph, root)
		_add_signature_props(graph, root)


## Pads, wind, pistons, spiders, crumbling covers, shortcut markers and landmarks.
func _add_gameplay_features(graph: CaveGraph, root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "GameplayFeatures"
	root.add_child(holder)
	var ids := 0
	for f: Dictionary in graph.features:
		var c: Vector3i = f["cell"]
		var node: Node3D = null
		match f["kind"]:
			"pad": node = BoostPad.create(c, int(f["axis"]))
			"wind": node = WindZone.create(c, int(f["axis"]), int(f["sign"]))
			"piston": node = PistonHazard.create(ids, c, int(f["phase"]))
			"spider": node = SpiderEnemy.create(ids, c, int(f["axis"]), int(f.get("span", 3)), int(f.get("shift", 0)))
			"crumble": node = CrumbleTile.create(c)
			"shortcut": node = _make_shortcut_marker(c)
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
	var floor_y := -CELL_SIZE * 0.5 + WALL_THICKNESS * 0.5
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
	cyl.height = CELL_SIZE - 5.0
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
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.8
		cyl.bottom_radius = 2.2
		cyl.height = CELL_SIZE
		cyl.radial_segments = 12
		beam.mesh = cyl
		beam.material_override = beam_mat
		beam.position = cell_to_world(c) + Vector3(0.0, CELL_SIZE * 0.5, 0.0)
		holder.add_child(beam)
		for k in 4:
			var lip := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(CELL_SIZE - 1.0, 0.12, 0.12) if k < 2 else Vector3(0.12, 0.12, CELL_SIZE - 1.0)
			lip.mesh = m
			lip.material_override = lip_mat
			var edge := CELL_SIZE * 0.5 - 0.6
			var offs := [Vector3(0, 0, edge), Vector3(0, 0, -edge), Vector3(edge, 0, 0), Vector3(-edge, 0, 0)]
			lip.position = cell_to_world(c) + Vector3(0.0, CELL_SIZE * 0.5, 0.0) + offs[k]
			holder.add_child(lip)


## FUN-004: a ring of upward chevrons under a shaft that saves a long walk. It says "this
## costs a Move and is worth it", nothing about where the exit is.
func _make_shortcut_marker(c: Vector3i) -> Node3D:
	var marker := Node3D.new()
	marker.position = cell_to_world(c) + Vector3(0.0, -CELL_SIZE * 0.5 + WALL_THICKNESS * 0.5 + 0.05, 0.0)
	var mat := _glow(Color(0.3, 0.85, 0.55), 0.9)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.9
	torus.outer_radius = 2.15
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
	var floor_y := -CELL_SIZE * 0.5 + WALL_THICKNESS * 0.5
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
				cyl.height = CELL_SIZE - WALL_THICKNESS
				col.mesh = cyl
				col.material_override = stone
				col.position = corners[k]
				node.add_child(col)
				var shape := CollisionShape3D.new()
				var cs := CylinderShape3D.new()
				cs.radius = 0.65
				cs.height = cyl.height
				shape.shape = cs
				shape.position = corners[k]
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
			root.position = centre + n * (CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5 - 0.25) \
				+ Vector3(0, floor_y + 2.4, 0)
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
			var height := 1.0 + float(v % 4) * 0.6
			root.position = centre + n * (CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5 - 0.02) \
				+ right * (float(v % 5) - 2.0) + Vector3(0, floor_y + height + 1.5, 0)
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
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = slabs.size()
	for i in slabs.size():
		mm.set_instance_transform(i, slabs[i])
		# ART-001: every slab a slightly different stone. Derived from position, not rolled,
		# so the builder still makes no choices of its own.
		var o := slabs[i].origin
		var h: int = absi(hash(Vector3i(roundi(o.x * 2.0), roundi(o.y * 2.0), roundi(o.z * 2.0))))
		var shade := 0.86 + float(h % 1000) / 1000.0 * 0.22
		var warmth := (float((h / 1000) % 100) / 100.0 - 0.5) * 0.08
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
					var x := float((h >> (k * 2)) % 7 - 3) * 0.8
					var z := float((h >> (k * 2 + 5)) % 7 - 3) * 0.8
					var node := _mesh(strand, mat, centre + Vector3(x, CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5 - strand_len * 0.5, z))
					node.rotation = Vector3(0.12 * float(k % 3 - 1), 0.0, 0.1 * float((k + 1) % 3 - 1))
					holder.add_child(node)
			"glowworms":
				if h % 2 != 0 or graph.is_linked(c, CaveGraph.DIR_UP):
					continue
				for k in 14:
					var hk: int = absi(hash(Vector2i(h, k)))
					glow_points.append(centre + Vector3(float(hk % 70) / 10.0 - 3.5,
						CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5 - 0.08, float((hk / 70) % 70) / 10.0 - 3.5))
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
					var node := _mesh(pipe, mat, centre + n * (CELL_SIZE * 0.5 - WALL_THICKNESS * 0.5 - 0.35)
						+ Vector3(0, -CELL_SIZE * 0.5 + 3.0, 0))
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
