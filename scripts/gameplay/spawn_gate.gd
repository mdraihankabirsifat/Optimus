class_name SpawnGate
extends StaticBody3D
## ART-010: a portcullis across one exit of the spawn chamber. Drops into the floor on GO.

var _bars: Node3D


## `dir_index` is the horizontal face of the spawn cell this gate blocks.
static func create(cell: Vector3i, dir_index: int) -> SpawnGate:
	var gate := SpawnGate.new()
	var n := Vector3(CaveGraph.DIRS[dir_index])
	gate.position = CaveBuilder.cell_to_world(cell) + n * (CaveBuilder.CELL_SIZE * 0.5)
	if dir_index == CaveGraph.DIR_PLUS_X or dir_index == CaveGraph.DIR_MINUS_X:
		gate.rotation.y = PI * 0.5
	return gate


func _ready() -> void:
	collision_layer = CaveBuilder.LAYER_WORLD
	collision_mask = 0
	add_to_group("spawn_gates")
	var size := Vector3(CaveBuilder.CELL_SIZE, CaveBuilder.CELL_SIZE, 0.4)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	_bars = Node3D.new()
	add_child(_bars)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.2, 0.11)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.62, 0.24)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.2)
	glow.emission_energy_multiplier = 1.6
	for i in 7:
		var bar := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.14
		m.bottom_radius = 0.14
		m.height = CaveBuilder.CELL_SIZE - 1.0
		m.radial_segments = 6
		bar.mesh = m
		bar.material_override = wood
		bar.position.x = -3.0 + i
		_bars.add_child(bar)
	for y in [-2.0, 1.5]:
		var beam := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(CaveBuilder.CELL_SIZE - 1.0, 0.3, 0.3)
		beam.mesh = b
		beam.material_override = glow if y > 0.0 else wood
		beam.position.y = y
		_bars.add_child(beam)


func open() -> void:
	collision_layer = 0
	var tween := create_tween()
	tween.tween_property(_bars, "position:y", -CaveBuilder.CELL_SIZE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _bars.visible = false)
