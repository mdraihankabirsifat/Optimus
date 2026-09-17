class_name FreedomCoreVisual
extends Node3D
## The Freedom Core as the finalists see it: a spinning gold crystal inside three rings, one
## per axis, with its own light so it reads from anywhere in the arena. Visual only; the
## pickup itself is a distance check in FreedomDuel.

var _crystal: MeshInstance3D
var _rings: Array[MeshInstance3D] = []
var _t := 0.0


func _ready() -> void:
	_crystal = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = 0.38
	gem.height = 0.95
	gem.radial_segments = 4
	gem.rings = 2
	_crystal.mesh = gem
	_crystal.material_override = DuelArena._glow(Color(1.0, 0.82, 0.35), 3.0)
	add_child(_crystal)
	var colours := [DuelArena.X_COLOUR, DuelArena.Y_COLOUR, DuelArena.Z_COLOUR]
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.62
		torus.outer_radius = 0.7
		torus.rings = 24
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = DuelArena._glow(colours[i], 2.4)
		add_child(ring)
		_rings.append(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.45)
	light.light_energy = 2.5
	light.omni_range = 7.0
	add_child(light)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_crystal.rotation = Vector3(0.0, _t * 2.2, 0.0)
	_crystal.position.y = sin(_t * 2.5) * 0.12
	_rings[0].basis = Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.RIGHT, _t * 1.3)
	_rings[1].basis = Basis(Vector3.UP, _t * 1.7)
	_rings[2].basis = Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.FORWARD, _t * 1.1)
