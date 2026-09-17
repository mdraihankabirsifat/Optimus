class_name DuelArena
extends Node3D
## The Freedom Duel arena: a compact hall under the cave where the two finalists fight.
##
## Everything is laid out on the arena's own X/Y/Z so the theme reads at a glance: a red X
## line and a blue Z line cross the floor, green Y beams rise in the corners. Two raised
## platforms give height to whoever can jump (3DOF); each has a ramp, so a 2DOF finalist
## can still get up, just slower. Low walls and pillars break the sight lines.
##
## Built once per race, far below the cave and never touching it. Placement is fixed --
## both finalists, and every machine online, see the same arena.

## Well below the deepest cave level (the Long preset tops out at y = 32) and inside
## AppConfig.WORLD_BOUNDS, so the out-of-bounds recovery never fires in here.
const ORIGIN := Vector3(40.0, -70.0, 40.0)
const HALF := 20.0
const WALL_HEIGHT := 10.0
const CEILING := 14.0
const PLATFORM_TOP := 2.2

const X_COLOUR := Color(1.0, 0.33, 0.30)
const Y_COLOUR := Color(0.40, 0.95, 0.50)
const Z_COLOUR := Color(0.35, 0.62, 1.0)

## Where each finalist starts, and which way they face (toward the middle).
var spawn_a := ORIGIN + Vector3(0.0, 1.0, -17.5)
var spawn_b := ORIGIN + Vector3(0.0, 1.0, 17.5)
## Freedom Core pedestals, in spawn order: centre first, then the high ground, then the ends.
var core_points: Array[Vector3] = []

var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _body: StaticBody3D


static func create(parent: Node) -> DuelArena:
	var arena := DuelArena.new()
	arena.name = "DuelArena"
	parent.add_child(arena)
	arena.global_position = ORIGIN
	arena._build()
	return arena


func _build() -> void:
	_floor_mat = _surface(Color(0.40, 0.42, 0.48), 0.08)
	_wall_mat = _surface(Color(0.52, 0.52, 0.58), 0.05)
	_trim_mat = _glow(Color(0.55, 0.85, 1.0), 1.6)
	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)

	# Shell: floor, ceiling, four walls. Thick, so nothing tunnels through at duel speeds.
	_block(Vector3(0, -0.5, 0), Vector3(HALF * 2 + 2, 1, HALF * 2 + 2), _floor_mat)
	_block(Vector3(0, CEILING + 0.5, 0), Vector3(HALF * 2 + 2, 1, HALF * 2 + 2), _wall_mat)
	for s in [-1.0, 1.0]:
		_block(Vector3(s * (HALF + 0.5), CEILING * 0.5, 0), Vector3(1, CEILING, HALF * 2 + 2), _wall_mat)
		_block(Vector3(0, CEILING * 0.5, s * (HALF + 0.5)), Vector3(HALF * 2 + 2, CEILING, 1), _wall_mat)

	# High ground on the X ends, each with a ramp running the opposite way round, so the
	# layout is the same from either spawn.
	for s in [-1.0, 1.0]:
		_block(Vector3(s * 13.0, PLATFORM_TOP * 0.5, 0), Vector3(10, PLATFORM_TOP, 12), _wall_mat)
		_trim(Vector3(s * 8.0, PLATFORM_TOP + 0.03, 0), Vector3(0.12, 0.06, 12))
		_ramp(Vector3(s * 13.0, 0, s * 6.0), s, 8.0)

	# Cover: four pillars around the centre and a low wall in front of each spawn.
	for p in [Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(-5, 0, 5), Vector3(5, 0, 5)]:
		_block(p + Vector3(0, 1.75, 0), Vector3(1.8, 3.5, 1.8), _wall_mat)
		_trim(p + Vector3(0, 3.52, 0), Vector3(1.9, 0.05, 1.9))
	for s in [-1.0, 1.0]:
		# Waist high: cover from shots at a crouching distance, but you can see over it.
		_block(Vector3(0, 0.6, s * 12.0), Vector3(7, 1.2, 0.8), _wall_mat)
		_trim(Vector3(0, 1.22, s * 12.0), Vector3(7.05, 0.05, 0.85))

	_axis_markings()
	_lights()

	core_points = [
		ORIGIN + Vector3(0, 1.1, 0),
		ORIGIN + Vector3(-13.0, PLATFORM_TOP + 1.1, 0),
		ORIGIN + Vector3(13.0, PLATFORM_TOP + 1.1, 0),
		ORIGIN + Vector3(-8.0, 1.1, 16.0),
		ORIGIN + Vector3(8.0, 1.1, -16.0),
	]
	for p: Vector3 in core_points:
		var pad := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.9
		cyl.bottom_radius = 1.1
		cyl.height = 0.12
		cyl.radial_segments = 16
		pad.mesh = cyl
		pad.material_override = _glow(Color(0.95, 0.8, 0.35), 0.6)
		add_child(pad)
		pad.global_position = p - Vector3(0, 1.04, 0)


## Which way a finalist at `spawn` should face: straight at the arena's centre.
func facing_basis(spawn: Vector3) -> Basis:
	var to_centre := ORIGIN - spawn
	to_centre.y = 0.0
	return Basis.looking_at(to_centre.normalized(), Vector3.UP)


## Next point to walk to on the way to `goal`. The high ground is reached by its ramp: walk
## to the ramp foot, then up. Everything on the floor is a straight line.
func waypoint(from: Vector3, goal: Vector3) -> Vector3:
	var g := goal - ORIGIN
	var f := from - ORIGIN
	if g.y < PLATFORM_TOP * 0.6 or f.y > PLATFORM_TOP * 0.6:
		return goal
	var side := signf(g.x) if absf(g.x) > 0.1 else 1.0
	var foot := ORIGIN + Vector3(side * 13.0, 0.0, side * 15.5)
	var top := ORIGIN + Vector3(side * 13.0, PLATFORM_TOP, side * 4.5)
	var on_ramp := absf(f.x - side * 13.0) < 2.2 and f.z * side > 5.0 and f.z * side < 15.0
	if on_ramp or Vector2(from.x - foot.x, from.z - foot.z).length() < 1.5:
		return top
	return foot


## True if a point is inside the arena hall. Tests and the camera use it.
static func contains(p: Vector3) -> bool:
	var local := p - ORIGIN
	return absf(local.x) <= HALF + 1.0 and absf(local.z) <= HALF + 1.0 \
		and local.y >= -1.5 and local.y <= CEILING + 1.0


func _axis_markings() -> void:
	# Floor lines through the centre: X red, Z blue. Y green, straight up in each corner.
	_glow_box(Vector3(0, 0.02, 0), Vector3(HALF * 2, 0.04, 0.16), X_COLOUR)
	_glow_box(Vector3(0, 0.02, 0), Vector3(0.16, 0.04, HALF * 2), Z_COLOUR)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_glow_box(Vector3(cx * (HALF - 0.3), CEILING * 0.5, cz * (HALF - 0.3)), Vector3(0.18, CEILING, 0.18), Y_COLOUR)
	_axis_label("X", Vector3(HALF - 0.6, 4.5, 0), X_COLOUR, Vector3.LEFT)
	_axis_label("X", Vector3(-HALF + 0.6, 4.5, 0), X_COLOUR, Vector3.RIGHT)
	_axis_label("Z", Vector3(0, 4.0, HALF - 0.6), Z_COLOUR, Vector3.FORWARD)
	_axis_label("Z", Vector3(0, 4.0, -HALF + 0.6), Z_COLOUR, Vector3.BACK)
	_axis_label("Y", Vector3(HALF - 1.2, CEILING - 1.5, HALF - 1.2), Y_COLOUR, Vector3(-1, 0, -1).normalized())
	_axis_label("Y", Vector3(-HALF + 1.2, CEILING - 1.5, -HALF + 1.2), Y_COLOUR, Vector3(1, 0, 1).normalized())
	# A title over each spawn, facing into the hall.
	var title := Label3D.new()
	title.text = "FREEDOM DUEL"
	title.font_size = 180
	title.outline_size = 24
	title.modulate = Color(0.95, 0.85, 0.6)
	title.pixel_size = 0.01
	add_child(title)
	title.position = Vector3(0, 10.5, HALF - 0.55)
	title.basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP).rotated(Vector3.UP, PI)
	var title2 := title.duplicate() as Label3D
	add_child(title2)
	title2.position = Vector3(0, 10.5, -HALF + 0.55)
	title2.basis = Basis.looking_at(Vector3.BACK, Vector3.UP).rotated(Vector3.UP, PI)
	# Glowing trim along the foot of every wall.
	for s in [-1.0, 1.0]:
		_trim(Vector3(s * (HALF - 0.02), 0.25, 0), Vector3(0.05, 0.12, HALF * 2))
		_trim(Vector3(0, 0.25, s * (HALF - 0.02)), Vector3(HALF * 2, 0.12, 0.05))


func _axis_label(text: String, pos: Vector3, colour: Color, facing: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 320
	label.outline_size = 30
	label.modulate = colour
	label.pixel_size = 0.01
	label.shaded = false
	add_child(label)
	label.position = pos
	# Label3D shows its front along +Z; face it into the hall.
	label.basis = Basis.looking_at(-facing, Vector3.UP)


func _lights() -> void:
	var points := [Vector3(0, 9, 0), Vector3(-13, 8, 0), Vector3(13, 8, 0), Vector3(0, 7, -14), Vector3(0, 7, 14)]
	for i in points.size():
		var light := OmniLight3D.new()
		light.position = points[i]
		light.omni_range = 34.0 if i == 0 else 22.0
		light.light_energy = 3.2 if i == 0 else 2.2
		light.light_color = Color(0.85, 0.9, 1.0) if i == 0 else Color(1.0, 0.9, 0.75)
		add_child(light)


func _ramp(foot_centre: Vector3, side: float, length: float) -> void:
	# Runs along Z from the platform edge (z = side * 6) out to z = side * (6 + length).
	var rise := PLATFORM_TOP
	var angle := atan2(rise, length)
	var slab_len := sqrt(length * length + rise * rise)
	var mid := Vector3(foot_centre.x, rise * 0.5 - 0.2, side * (6.0 + length * 0.5))
	var basis := Basis(Vector3.RIGHT, angle * side)
	_block(mid, Vector3(4.0, 0.4, slab_len + 0.3), _floor_mat, basis)
	_trim_rotated(mid + basis * Vector3(1.95, 0.22, 0), Vector3(0.08, 0.05, slab_len), basis)
	_trim_rotated(mid + basis * Vector3(-1.95, 0.22, 0), Vector3(0.08, 0.05, slab_len), basis)


func _block(pos: Vector3, size: Vector3, mat: Material, basis: Basis = Basis()) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	mesh.basis = basis
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = pos
	shape.basis = basis
	_body.add_child(shape)


func _glow_box(pos: Vector3, size: Vector3, colour: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _glow(colour, 2.2)
	mesh.position = pos
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _trim(pos: Vector3, size: Vector3) -> void:
	_trim_rotated(pos, size, Basis())


func _trim_rotated(pos: Vector3, size: Vector3, basis: Basis) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _trim_mat
	mesh.position = pos
	mesh.basis = basis
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _surface(colour: Color, variation: float) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0 - variation * 3.0, 1.0 - variation * 3.0, 1.0 - variation * 3.0))
	ramp.set_color(1, Color.WHITE)
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.seamless = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	mat.roughness = 0.8
	return mat


static func _glow(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
