class_name MysteryBox
extends Area3D
## A one-time mystery box. Interact with E (humans) or by walking up to it (bots).
##
## The outcome is decided by a RandomNumberGenerator seeded from (match seed, box index),
## so it is fixed the moment the cave is generated and identical on every machine. Once a
## server exists, the server rolls and clients only display. Nothing here trusts the racer.

signal opened(racer: PlayerController, reward: String, description: String)
signal clue_granted(racer: PlayerController, direction: Vector3, vertical: int)

const SIZE := 1.15

var box_index: int = 0
var match_seed: int = 0
var is_open: bool = false
## World position of the finish. Used ONLY to derive a coarse clue direction. The box
## never reveals it directly, and only ~5% of boxes ever use it.
var finish_position: Vector3 = Vector3.ZERO

var _body: MeshInstance3D
var _lid: MeshInstance3D
var _glyph: Label3D
var _mat: StandardMaterial3D
var _time: float = 0.0


static func create(index: int, p_seed: int, corner: int, finish_pos: Vector3) -> MysteryBox:
	var box := MysteryBox.new()
	box.box_index = index
	box.match_seed = p_seed
	box.finish_position = finish_pos
	box.name = "MysteryBox%d" % index
	var off := CaveBuilder.CELL_SIZE * 0.5 - 2.0
	var corners := [Vector3(off, 0, off), Vector3(-off, 0, off), Vector3(off, 0, -off), Vector3(-off, 0, -off)]
	# Rests on the cell's world floor.
	box.position = Vector3(0.0, -CaveBuilder.CELL_SIZE * 0.5 + CaveBuilder.WALL_THICKNESS * 0.5 + SIZE * 0.5, 0.0) \
		+ corners[corner]
	return box


func _ready() -> void:
	collision_layer = PlayerInteraction.LAYER_INTERACTABLE
	collision_mask = 0
	add_to_group("mystery_boxes")

	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE * 1.6, SIZE * 1.6, SIZE * 1.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 0.22, 0.12)
	_mat.emission_enabled = true
	_mat.emission = Color(0.9, 0.7, 0.25)
	_mat.emission_energy_multiplier = 0.8
	_mat.roughness = 0.6

	_body = MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(SIZE, SIZE * 0.7, SIZE)
	_body.mesh = body_mesh
	_body.position = Vector3(0.0, -SIZE * 0.15, 0.0)
	_body.material_override = _mat
	add_child(_body)

	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(SIZE * 1.08, SIZE * 0.3, SIZE * 1.08)
	_lid.mesh = lid_mesh
	_lid.position = Vector3(0.0, SIZE * 0.35, 0.0)
	_lid.material_override = _mat
	add_child(_lid)

	# Bright bands so the box reads as "special" from down a corridor.
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(1.0, 0.85, 0.4)
	band_mat.emission_enabled = true
	band_mat.emission = Color(1.0, 0.8, 0.3)
	band_mat.emission_energy_multiplier = 2.0
	for axis in 2:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(SIZE * 1.12, SIZE * 1.02, 0.18) if axis == 0 \
			else Vector3(0.18, SIZE * 1.02, SIZE * 1.12)
		band.mesh = band_mesh
		band.material_override = band_mat
		add_child(band)

	_glyph = Label3D.new()
	_glyph.text = "?"
	_glyph.font_size = 96
	_glyph.pixel_size = 0.012
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.modulate = Color(1.0, 0.9, 0.5)
	_glyph.outline_size = 12
	_glyph.outline_modulate = Color(0.2, 0.1, 0.0)
	_glyph.position = Vector3(0.0, SIZE * 1.3, 0.0)
	add_child(_glyph)


func _process(delta: float) -> void:
	_time += delta
	if is_open:
		return
	_glyph.position.y = SIZE * 1.3 + sin(_time * 2.4) * 0.12
	_mat.emission_energy_multiplier = 0.7 + 0.35 * (0.5 + 0.5 * sin(_time * 3.0))


func prompt_text() -> String:
	return "" if is_open else "[E]  Open Mystery Box"


## Bots call this too, after walking within reach. Same rules, same rewards.
func interact(racer: PlayerController) -> void:
	if is_open or racer == null:
		return
	is_open = true
	collision_layer = 0
	_animate_open()

	var reward := _roll_reward()
	var description := _apply_reward(reward, racer)
	opened.emit(racer, reward, description)


func _roll_reward() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed * 104729 + box_index * 7919 + 17
	var total := 0
	for weight: int in AppConfig.LOOT_TABLE.values():
		total += weight
	var pick := rng.randi_range(0, total - 1)
	for key: String in AppConfig.LOOT_TABLE:
		pick -= int(AppConfig.LOOT_TABLE[key])
		if pick < 0:
			return key
	return "heart"


## Returns the player-facing description of what happened.
func _apply_reward(reward: String, racer: PlayerController) -> String:
	match reward:
		"heart":
			racer.health.refill(AppConfig.HEART_REFILL_AMOUNT)
			return "Heart Refill  +1 heart"
		"move":
			racer.gravity.add_charges(AppConfig.MOVE_REFILL_AMOUNT)
			return "Move Refill  +1 Gravity Move"
		"speed":
			racer.apply_speed_effect(AppConfig.SPEED_BOOST_MULTIPLIER, AppConfig.SPEED_BOOST_TIME)
			return "Speed Boost  %ds" % int(AppConfig.SPEED_BOOST_TIME)
		"shield":
			racer.health.grant_shield()
			return "Shield  absorbs the next hit"
		"slow":
			racer.apply_speed_effect(AppConfig.SLOW_MULTIPLIER, AppConfig.SLOW_TIME)
			return "Heavy Legs  slowed for %ds" % int(AppConfig.SLOW_TIME)
		"lose_move":
			var taken := racer.gravity.remove_charges(1)
			return "Drained  -1 Gravity Move" if taken > 0 else "Drained  ...but you had no Moves to lose"
		"second_chance":
			racer.health.grant_second_chance()
			return "Second Chance  survive one fatal hit"
		"clue":
			var info := _coarse_clue(racer.global_position)
			clue_granted.emit(racer, info["direction"], info["vertical"])
			return "CLUE  the exit lies %s%s" % [info["compass"], info["level_text"]]
	return "Nothing"


## A coarse hint only: one of eight compass directions plus above/below/same level.
## It never gives distance or the exact cell.
func _coarse_clue(from: Vector3) -> Dictionary:
	var delta := finish_position - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var direction := flat.normalized() if flat.length() > 0.5 else Vector3(0, 0, -1)
	# Snap to 45 degree compass points.
	var angle := atan2(direction.x, -direction.z)
	var snapped_angle := roundf(angle / (PI * 0.25)) * (PI * 0.25)
	direction = Vector3(sin(snapped_angle), 0.0, -cos(snapped_angle))
	var compass_names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var idx := int(roundf(snapped_angle / (PI * 0.25))) % 8
	if idx < 0:
		idx += 8
	var vertical := 0
	var level_text := ""
	if delta.y > CaveBuilder.CELL_SIZE * 0.6:
		vertical = 1
		level_text = ", above you"
	elif delta.y < -CaveBuilder.CELL_SIZE * 0.6:
		vertical = -1
		level_text = ", below you"
	return {
		"direction": direction, "vertical": vertical,
		"compass": compass_names[idx], "level_text": level_text,
	}


func _animate_open() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_lid, "position", Vector3(0.0, SIZE * 0.55, -SIZE * 0.55), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_glyph, "modulate:a", 0.0, 0.3)
	tween.tween_property(_mat, "emission_energy_multiplier", 0.08, 0.6)
