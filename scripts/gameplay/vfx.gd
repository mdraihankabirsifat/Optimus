class_name Vfx
extends RefCounted
## One-shot world effects. Every effect here is oriented by the racer's own local up, so dust
## kicked up by someone walking on a wall flies away from that wall, not toward world up.

static var _dust_mesh: BoxMesh


static func dust_puff(parent: Node, at: Vector3, up: Vector3, strength: float = 1.0) -> void:
	if _dust_mesh == null:
		_dust_mesh = BoxMesh.new()
		_dust_mesh.size = Vector3.ONE * 0.12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.72, 0.62, 0.5, 0.55)
		mat.vertex_color_use_as_albedo = true
		_dust_mesh.material = mat
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int(6 + 14 * strength)
	p.lifetime = 0.55
	p.explosiveness = 0.9
	p.local_coords = false
	p.mesh = _dust_mesh
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.6 * strength
	p.initial_velocity_max = 2.4 * strength
	p.gravity = Vector3.ZERO
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2 + strength
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	parent.add_child(p)
	# Point the emitter's +Y along the racer's up so the puff rises off their floor.
	var right := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	p.global_basis = Basis(right, up, right.cross(up)).orthonormalized()
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## VFX-008: slow motes drifting in the air around the local player.
static func dust_motes() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 5, 9)
	p.direction = Vector3(0.3, 0.2, 0.1)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.035
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.75, 0.45)
	m.material = mat
	p.mesh = m
	return p
