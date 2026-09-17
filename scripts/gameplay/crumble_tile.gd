class_name CrumbleTile
extends StaticBody3D
## HAZ-002: a cracked slab covering a shaft. Anything touching it -- from above or pressed
## against it from below -- starts it crumbling. It never comes back.
##
## The generator never puts one on the guaranteed route, and the shaft beneath is already a
## real connection in the cave graph, so a collapse can only open the map, never close it.

signal collapsed()
## The server relays this so every client's copy of the tile crumbles too.
signal crumbling_started()

var _trigger: Area3D
var _mesh: MeshInstance3D
var _state := 0  # 0 intact, 1 cracking, 2 gone
## Online client copy: only the server's tile decides when a touch starts the collapse.
var net_client: bool = false
var _timer := 0.0
var _rest_y := 0.0


## `cell` is the upper cell; the tile is its floor.
static func create(cell: Vector3i) -> CrumbleTile:
	var tile := CrumbleTile.new()
	tile.position = CaveBuilder.cell_to_world(cell) + Vector3(0.0, -CaveBuilder.CELL_SIZE * 0.5, 0.0)
	return tile


func _ready() -> void:
	collision_layer = CaveBuilder.LAYER_WORLD
	collision_mask = 0
	add_to_group("crumble_tiles")
	# Exactly plugs the tunnel-sized opening between the two cells.
	var hole := CaveBuilder.TUNNEL_HALF * 2.0
	var size := Vector3(hole + 0.1, CaveBuilder.WALL_THICKNESS, hole + 0.1)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size - Vector3(0.05, 0.0, 0.05)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.4, 0.32)
	mat.roughness = 1.0
	_mesh.material_override = mat
	add_child(_mesh)
	# Glowing cracks so the tile reads as fragile before anyone steps on it.
	var crack_mat := StandardMaterial3D.new()
	crack_mat.albedo_color = Color(1.0, 0.55, 0.2)
	crack_mat.emission_enabled = true
	crack_mat.emission = Color(1.0, 0.45, 0.1)
	crack_mat.emission_energy_multiplier = 0.6
	for i in 5:
		var crack := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(2.2 - 0.25 * i, 0.03, 0.05)
		crack.mesh = line
		crack.material_override = crack_mat
		crack.rotation.y = float(i) * 1.13
		crack.position = Vector3(cos(i * 2.1) * 0.8, 0.0, sin(i * 2.1) * 0.8)
		for face in [1.0, -1.0]:
			var side := crack.duplicate() as MeshInstance3D
			side.position.y = face * (CaveBuilder.WALL_THICKNESS * 0.5 + 0.01)
			_mesh.add_child(side)
		crack.free()

	_trigger = Area3D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = CaveBuilder.LAYER_RACERS
	var tshape := BoxShape3D.new()
	tshape.size = Vector3(hole - 0.4, CaveBuilder.WALL_THICKNESS + 1.4, hole - 0.4)
	var tcol := CollisionShape3D.new()
	tcol.shape = tshape
	_trigger.add_child(tcol)
	add_child(_trigger)
	_trigger.body_entered.connect(func(_b: Node3D) -> void:
		if not net_client:
			start_crumbling())


func start_crumbling() -> void:
	if _state != 0:
		return
	crumbling_started.emit()
	_state = 1
	_timer = AppConfig.CRUMBLE_DELAY
	AudioManager.play_sfx_3d("crumble", global_position, 0.0)


func _physics_process(delta: float) -> void:
	if _state != 1:
		return
	_timer -= delta
	_mesh.position = Vector3(randf_range(-0.06, 0.06), randf_range(-0.03, 0.03), randf_range(-0.06, 0.06))
	if _timer > 0.0:
		return
	_state = 2
	collision_layer = 0
	_trigger.monitoring = false
	collapsed.emit()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_mesh, "position:y", -7.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_mesh, "rotation", Vector3(0.4, 0.2, -0.3), 0.9)
	tween.chain().tween_callback(queue_free)
