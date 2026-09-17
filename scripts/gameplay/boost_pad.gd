class_name BoostPad
extends Area3D
## FUN-001: a floor pad on a straight corridor that gives a short speed boost. Rewards
## racers who remember where the long runs are.

const LENGTH := 6.0
const WIDTH := 2.6

var _mat: StandardMaterial3D
var _time: float = 0.0
var _cooldowns: Dictionary = {}


static func create(cell: Vector3i, axis: int, half: float = CaveBuilder.CHAMBER_HALF) -> BoostPad:
	var pad := BoostPad.new()
	pad.position = CaveBuilder.cell_to_world(cell) + Vector3(0.0, CaveBuilder.FLOOR_Y, 0.0)
	if axis == CaveGraph.DIR_PLUS_Z:
		pad.rotation.y = PI * 0.5
	return pad


func _ready() -> void:
	collision_layer = 0
	collision_mask = CaveBuilder.LAYER_RACERS
	body_entered.connect(_on_body_entered)
	var shape := BoxShape3D.new()
	shape.size = Vector3(LENGTH, 1.6, WIDTH)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.8
	add_child(col)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.1, 0.35, 0.45)
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 0.9, 1.0)
	_mat.emission_energy_multiplier = 1.4
	var base := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(LENGTH, 0.08, WIDTH)
	base.mesh = slab
	base.material_override = StandardMaterial3D.new()
	(base.material_override as StandardMaterial3D).albedo_color = Color(0.12, 0.12, 0.14)
	base.position.y = 0.04
	add_child(base)
	# Chevrons point both ways: a pad works in either direction of travel.
	for i in 4:
		var chevron := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(1.6, 0.9, 0.06)
		chevron.mesh = prism
		chevron.material_override = _mat
		chevron.rotation = Vector3(-PI * 0.5, 0.0, -PI * 0.5 if i < 2 else PI * 0.5)
		chevron.position = Vector3(-2.2 + 1.3 * i + (0.3 if i >= 2 else 0.0), 0.1, 0.0)
		add_child(chevron)


func _process(delta: float) -> void:
	_time += delta
	_mat.emission_energy_multiplier = 1.0 + 0.8 * (0.5 + 0.5 * sin(_time * 6.0))
	for body: Node in _cooldowns.keys():
		_cooldowns[body] = float(_cooldowns[body]) - delta
		if _cooldowns[body] <= 0.0:
			_cooldowns.erase(body)


func _on_body_entered(body: Node3D) -> void:
	var racer := body as PlayerController
	if racer == null or not racer.input_enabled or _cooldowns.has(racer):
		return
	# A pad refreshes a boost but never cancels a mystery-box slow.
	if racer.speed_multiplier < 1.0:
		return
	_cooldowns[racer] = 1.5
	racer.apply_speed_effect(maxf(AppConfig.BOOST_PAD_MULTIPLIER, racer.speed_multiplier),
		maxf(AppConfig.BOOST_PAD_TIME, racer.speed_effect_remaining()))
	if racer.is_local_player:
		AudioManager.play_sfx("speed", -4.0)
	else:
		AudioManager.play_sfx_3d("speed", global_position, -6.0)
