class_name RacerRig
extends Node3D
## ART-006 / ART-007: a blocky caveman-explorer built from boxes, animated in code.
##
## Everything here is LOCAL to the racer's body, and the body is already aligned to that
## racer's own gravity, so a racer walking a wall animates correctly with no extra maths.
## This script only reads the racer; it never moves, rotates or damages anything outside
## its own limbs.

var _racer: PlayerController
var _hips: Node3D
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _cloth: StandardMaterial3D
var _skin: StandardMaterial3D
var _outline: StandardMaterial3D
var _phase := 0.0
var _hurt := 0.0
var _cheer := 0.0
var _emote := ""
var _emote_label: Label3D
var _emote_timer := 0.0


func _ready() -> void:
	_racer = get_parent().get_parent() as PlayerController
	_cloth = StandardMaterial3D.new()
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = Color(0.86, 0.66, 0.5)
	_outline = StandardMaterial3D.new()
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	_outline.grow_amount = 0.035
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color(0.2, 0.12, 0.07)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.35, 0.22, 0.12)

	# Capsule was 1.8 tall centred on the body origin, so feet sit at -0.9.
	_hips = Node3D.new()
	_hips.position.y = -0.1
	add_child(_hips)
	_torso = _part(Vector3(0.62, 0.72, 0.36), Vector3(0, 0.36, 0), _cloth, _hips)
	var belt := _part(Vector3(0.66, 0.1, 0.4), Vector3(0, 0.04, 0), leather, _hips)
	belt.name = "Belt"
	_head = _part(Vector3(0.44, 0.44, 0.42), Vector3(0, 0.98, 0), _skin, _hips)
	_part(Vector3(0.48, 0.14, 0.46), Vector3(0, 0.22, 0.02), hair, _head)
	_arm_l = _limb(Vector3(-0.42, 0.66, 0), Vector3(0.18, 0.62, 0.2), _cloth, _skin)
	_arm_r = _limb(Vector3(0.42, 0.66, 0), Vector3(0.18, 0.62, 0.2), _cloth, _skin)
	_leg_l = _limb(Vector3(-0.16, 0.0, 0), Vector3(0.22, 0.78, 0.24), leather, leather)
	_leg_r = _limb(Vector3(0.16, 0.0, 0), Vector3(0.22, 0.78, 0.24), leather, leather)
	for leg in [_leg_l, _leg_r]:
		leg.position.y = -0.02

	var visor := get_parent().get_node_or_null("Visor") as MeshInstance3D
	if visor != null:
		visor.reparent(_head, false)
		visor.position = Vector3(0, 0.02, -0.22)
		visor.scale = Vector3(0.8, 0.8, 0.5)

	_emote_label = Label3D.new()
	_emote_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote_label.font_size = 64
	_emote_label.pixel_size = 0.008
	_emote_label.outline_size = 12
	_emote_label.position.y = 1.75
	_emote_label.visible = false
	add_child(_emote_label)

	if _racer != null:
		_racer.health.damaged.connect(func(_a: float, _s: String) -> void: _hurt = 1.0)


## VFX-012: an outline in the racer's colour keeps them readable against stone at range.
func set_colour(colour: Color) -> void:
	_cloth.albedo_color = colour
	_cloth.emission_enabled = true
	_cloth.emission = colour
	_cloth.emission_energy_multiplier = 0.15
	_outline.albedo_color = colour.lightened(0.35)
	_cloth.next_pass = _outline
	_skin.next_pass = _outline


func cheer(seconds: float = 3.0) -> void:
	_cheer = seconds


## FUN-007: a short line of text over the racer's head.
func emote(text: String, seconds: float = 2.2) -> void:
	_emote_label.text = text
	_emote_label.modulate = _cloth.albedo_color.lightened(0.4)
	_emote_label.visible = true
	_emote_timer = seconds


func _part(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A pivot at the shoulder or hip with the limb hanging below it.
func _limb(pivot: Vector3, size: Vector3, upper: Material, lower: Material) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	_hips.add_child(p)
	_part(Vector3(size.x, size.y * 0.55, size.z), Vector3(0, -size.y * 0.27, 0), upper, p)
	_part(Vector3(size.x * 0.95, size.y * 0.5, size.z * 0.95), Vector3(0, -size.y * 0.75, 0), lower, p)
	return p


func _process(delta: float) -> void:
	if _racer == null:
		return
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	_cheer = maxf(0.0, _cheer - delta)
	if _emote_timer > 0.0:
		_emote_timer -= delta
		_emote_label.position.y = 1.75 + (2.2 - _emote_timer) * 0.1
		if _emote_timer <= 0.0:
			_emote_label.visible = false

	var up := _racer.gravity.local_up()
	var vel := _racer.velocity
	var vertical := vel.dot(up)
	var planar := (vel - up * vertical).length()
	var grounded := _racer.is_on_floor()
	var t := 1.0 - exp(-14.0 * delta)

	var arm_swing := 0.0
	var leg_swing := 0.0
	var arms_out := 0.0
	var arms_up := 0.0
	var lean := 0.0
	var tuck := 0.0
	var bob := 0.0

	if _racer.health.is_eliminated:
		_hips.rotation.x = lerpf(_hips.rotation.x, -1.45, t)
		_hips.position.y = lerpf(_hips.position.y, -0.62, t)
		return

	if _racer.gravity.is_transitioning:
		tuck = 1.0
	elif _cheer > 0.0:
		arms_up = 1.0
		bob = absf(sin(_cheer * 9.0)) * 0.25
	elif not grounded:
		arms_out = 0.7
		leg_swing = 0.35
	elif planar > 0.5:
		_phase += delta * planar * 1.5
		arm_swing = clampf(planar / AppConfig.WALK_SPEED, 0.3, 1.3) * 0.75
		leg_swing = arm_swing * 1.1
		lean = clampf(planar / AppConfig.SPRINT_SPEED, 0.0, 1.0) * 0.18
		bob = absf(sin(_phase)) * 0.06
	else:
		_phase = 0.0
		bob = sin(Time.get_ticks_msec() * 0.002) * 0.015

	var s := sin(_phase)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, s * arm_swing - arms_up * 2.8 - tuck * 1.2, t)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -s * arm_swing - arms_up * 2.8 - tuck * 1.2, t)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, arms_out * 1.1 + arms_up * 0.3, t)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, -arms_out * 1.1 - arms_up * 0.3, t)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -s * leg_swing - tuck * 1.3, t)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, s * leg_swing * (0.4 if not grounded else 1.0) - tuck * 1.3, t)
	_hips.rotation.x = lerpf(_hips.rotation.x, -lean - tuck * 0.5 + _hurt * 0.4, t)
	_hips.position.y = lerpf(_hips.position.y, -0.1 + bob - tuck * 0.15, t)
	_cloth.emission_energy_multiplier = 0.15 + _hurt * 2.0
