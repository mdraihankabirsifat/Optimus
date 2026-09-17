class_name SpikeHazard
extends StaticBody3D
## Prompt 3: a stalagmite or stalactite is a real object. It blocks like it looks (a solid
## cone approximated by a cylinder) and its point hurts: a thin damaging shell around the
## spike, half a heart per touch with a per-spike cooldown so leaning on one is not a drain.
##
## Only chambers get spikes (CaveBuilder skips them in the narrow tunnels) so they can never
## close a route or a wall/ceiling walking line the cave validator relies on.

const DAMAGE := 0.5
const COOLDOWN := 1.0
const SHELL := 0.25

var spike_id: int = 0
var _bodies: Array[Node3D] = []


## `height` is the cone's length, `radius` its base, `hanging` true for a stalactite. The
## node sits at the base; the spike points +Y (down for a hanging one).
static func create(id: int, height: float, radius: float, hanging: bool) -> SpikeHazard:
	var spike := SpikeHazard.new()
	spike.spike_id = id
	spike.name = "Spike%d" % id
	spike.collision_layer = CaveBuilder.LAYER_WORLD
	spike.collision_mask = 0
	var dir := -1.0 if hanging else 1.0
	# Solid core: most of the cone's volume, slimmer than the base so a racer brushing the
	# visible edge is pushed off rather than snagged.
	var core := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius * 0.6
	cyl.height = height * 0.85
	core.shape = cyl
	core.position = Vector3(0, dir * height * 0.425, 0)
	spike.add_child(core)
	# Damaging shell, a little larger than the core, over the upper part of the spike.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = CaveBuilder.LAYER_RACERS
	var shell := CollisionShape3D.new()
	var shell_shape := CylinderShape3D.new()
	shell_shape.radius = radius * 0.6 + SHELL
	shell_shape.height = height
	shell.shape = shell_shape
	shell.position = Vector3(0, dir * height * 0.5, 0)
	area.add_child(shell)
	spike.add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if not spike._bodies.has(b):
			spike._bodies.append(b))
	area.body_exited.connect(func(b: Node3D) -> void: spike._bodies.erase(b))
	spike.add_to_group("hazards")
	return spike


func _physics_process(_delta: float) -> void:
	for body: Node3D in _bodies.duplicate():
		if not is_instance_valid(body) or (body as CollisionObject3D).collision_layer & CaveBuilder.LAYER_RACERS == 0:
			_bodies.erase(body)
			continue
		var health: PlayerHealth = body.get("health")
		if health != null:
			health.apply_damage(DAMAGE, "spike_%d" % spike_id, COOLDOWN)
