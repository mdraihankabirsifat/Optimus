class_name FireHazard
extends Area3D
## A patch of fire on a cell floor. Readable from a distance, animated, never lethal in one
## touch: 0.5 heart per tick with a per-source cooldown so standing in it drains fairly.
##
## The patch covers most of the cell but always leaves one edge clear, so a racer can
## squeeze past on foot -- or shift gravity onto a wall and walk straight over it, which
## is the play the whole game is about.

const PATCH_SIZE := 5.2
const FLAME_HEIGHT := 2.4
const FLAME_COUNT := 7

var hazard_id: int = 0

var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _time: float = 0.0
var _bodies: Array[Node3D] = []


## `side` (0-3) is the cell edge left clear.
static func create(id: int, side: int) -> FireHazard:
	var fire := FireHazard.new()
	fire.hazard_id = id
	fire.name = "Fire%d" % id
	var offset := CaveBuilder.CELL_SIZE * 0.5 - PATCH_SIZE * 0.5
	var shift: Vector3 = [Vector3(offset, 0, 0), Vector3(-offset, 0, 0),
		Vector3(0, 0, offset), Vector3(0, 0, -offset)][side]
	# Sits on the world floor of the cell. Fire is part of the world; it has no gravity
	# frame of its own, which is exactly why walking the ceiling over it is safe.
	fire.position = Vector3(0.0, -CaveBuilder.CELL_SIZE * 0.5 + CaveBuilder.WALL_THICKNESS * 0.5, 0.0) + shift
	return fire


func _ready() -> void:
	collision_layer = 0
	collision_mask = CaveBuilder.LAYER_RACERS
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("hazards")

	var shape := BoxShape3D.new()
	shape.size = Vector3(PATCH_SIZE, FLAME_HEIGHT, PATCH_SIZE)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, FLAME_HEIGHT * 0.5, 0.0)
	add_child(collision)

	_build_visuals()


func _build_visuals() -> void:
	# Ember bed: a dark, glowing slab so the patch reads even when the flames are between
	# frames of their flicker.
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(PATCH_SIZE, 0.25, PATCH_SIZE)
	bed.mesh = bed_mesh
	bed.position = Vector3(0.0, 0.12, 0.0)
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.25, 0.08, 0.02)
	bed_mat.emission_enabled = true
	bed_mat.emission = Color(1.0, 0.35, 0.05)
	bed_mat.emission_energy_multiplier = 1.6
	bed.material_override = bed_mat
	add_child(bed)

	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.85)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.45, 0.08)
	flame_mat.emission_energy_multiplier = 2.2
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rng := RandomNumberGenerator.new()
	rng.seed = hazard_id * 131 + 7
	for i in FLAME_COUNT:
		var flame := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(0.45, 0.8)
		cone.height = rng.randf_range(1.4, FLAME_HEIGHT)
		cone.radial_segments = 6
		flame.mesh = cone
		flame.material_override = flame_mat
		flame.position = Vector3(
			rng.randf_range(-PATCH_SIZE * 0.38, PATCH_SIZE * 0.38),
			cone.height * 0.5 + 0.2,
			rng.randf_range(-PATCH_SIZE * 0.38, PATCH_SIZE * 0.38))
		flame.set_meta("phase", rng.randf() * TAU)
		flame.set_meta("base_h", cone.height)
		add_child(flame)
		_flames.append(flame)

	var particles := CPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 1.4
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(PATCH_SIZE * 0.4, 0.2, PATCH_SIZE * 0.4)
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 12.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 2.6
	particles.gravity = Vector3(0, 0.6, 0)
	particles.scale_amount_min = 0.06
	particles.scale_amount_max = 0.14
	particles.color = Color(1.0, 0.6, 0.2)
	var spark := BoxMesh.new()
	spark.size = Vector3.ONE
	particles.mesh = spark
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.7, 0.3)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.5, 0.1)
	spark_mat.emission_energy_multiplier = 3.0
	spark.material = spark_mat
	particles.position = Vector3(0.0, 0.4, 0.0)
	add_child(particles)

	var crackle := AudioStreamPlayer3D.new()
	crackle.bus = "SFX"
	crackle.stream = AudioManager.get_stream("fire_loop")
	crackle.unit_size = 4.0
	crackle.max_distance = 22.0
	crackle.volume_db = -4.0
	crackle.autoplay = crackle.stream != null
	crackle.position.y = 1.0
	add_child(crackle)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.15)
	_light.light_energy = 2.6
	_light.omni_range = CaveBuilder.CELL_SIZE * 1.3
	_light.position = Vector3(0.0, 1.6, 0.0)
	add_child(_light)


func _process(delta: float) -> void:
	_time += delta
	for flame: MeshInstance3D in _flames:
		var phase: float = flame.get_meta("phase")
		var base_h: float = flame.get_meta("base_h")
		var s := 0.8 + 0.25 * sin(_time * 11.0 + phase) + 0.12 * sin(_time * 23.0 + phase * 2.0)
		flame.scale = Vector3(1.0 + 0.1 * sin(_time * 7.0 + phase), s, 1.0 + 0.1 * cos(_time * 6.0 + phase))
		flame.position.y = base_h * 0.5 * s + 0.2
	if _light != null:
		_light.light_energy = 2.4 + 0.5 * sin(_time * 13.0) + 0.3 * sin(_time * 29.0)


func _physics_process(_delta: float) -> void:
	for body: Node3D in _bodies:
		if not is_instance_valid(body):
			continue
		var health: PlayerHealth = body.get("health")
		if health == null:
			continue
		health.apply_damage(AppConfig.DAMAGE_FIRE, "fire_%d" % hazard_id, AppConfig.FIRE_TICK_COOLDOWN)


func _on_body_entered(body: Node3D) -> void:
	if not _bodies.has(body):
		_bodies.append(body)


func _on_body_exited(body: Node3D) -> void:
	_bodies.erase(body)
