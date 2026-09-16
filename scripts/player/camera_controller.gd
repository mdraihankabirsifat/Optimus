class_name CameraController
extends Camera3D
## Game feel for the first-person camera: FOV response to sprinting and falling, a brief
## FOV punch on a gravity shift, a landing dip and a subtle walk bob.
##
## This script only ever changes `fov` and the camera's LOCAL offset inside Head. It never
## rotates anything -- orientation belongs to GravityController and mouse look. That is
## what keeps it impossible for this file to introduce roll. See docs/ARCHITECTURE.md.

@export var base_fov: float = 80.0
@export var sprint_fov_add: float = 6.0
@export var fall_fov_add: float = 5.0
@export var shift_fov_punch: float = -9.0
@export var bob_amplitude: float = 0.035
@export var bob_frequency: float = 9.5
@export var land_dip: float = 0.09

var _player: PlayerController
var _target_fov: float
var _punch: float = 0.0
var _dip: float = 0.0
var _bob_phase: float = 0.0
var _rest_offset: Vector3


func _ready() -> void:
	_player = get_parent().get_parent() as PlayerController
	_target_fov = base_fov
	fov = base_fov
	_rest_offset = position
	if _player == null:
		return
	# Children are ready before their parent, and a BotController clears is_local_player
	# in its own _ready. Wait until the whole racer is assembled before asking.
	if not _player.is_node_ready():
		await _player.ready
	if not _player.is_local_player:
		set_process(false)
		return
	_player.gravity.shift_started.connect(func(_d: Vector3) -> void: _punch = shift_fov_punch)
	_player.landed.connect(func(speed: float) -> void:
		_dip = land_dip * clampf(speed / 14.0, 0.25, 1.4))


func _process(delta: float) -> void:
	if _player == null:
		return
	var up := _player.gravity.local_up()
	var vertical_speed := _player.velocity.dot(up)
	var planar := _player.velocity - up * vertical_speed
	var planar_speed := planar.length()

	var want := base_fov
	if _player.sprint_input and planar_speed > AppConfig.WALK_SPEED + 0.5:
		want += sprint_fov_add
	if _player.speed_multiplier > 1.05:
		want += 3.0
	# Falling fast widens the view a touch so a long drop after a shift feels like one.
	want += fall_fov_add * clampf(-vertical_speed / AppConfig.TERMINAL_VELOCITY, 0.0, 1.0)

	_punch = lerpf(_punch, 0.0, 1.0 - exp(-7.0 * delta))
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-9.0 * delta))
	fov = lerpf(fov, want + _punch, 1.0 - exp(-8.0 * delta))

	var bob := Vector3.ZERO
	if _player.is_on_floor() and planar_speed > 1.0 and not _player.gravity.is_transitioning:
		_bob_phase += delta * bob_frequency * clampf(planar_speed / AppConfig.WALK_SPEED, 0.6, 1.6)
		var strength := bob_amplitude * clampf(planar_speed / AppConfig.SPRINT_SPEED, 0.4, 1.0)
		bob = Vector3(sin(_bob_phase) * strength * 0.6, absf(cos(_bob_phase)) * strength, 0.0)
	else:
		_bob_phase = 0.0

	# Camera-local offset only. Head's Y is the racer's local up, so a dip along local -Y
	# is always "down" in this racer's own frame.
	position = _rest_offset + bob - Vector3(0.0, _dip, 0.0)
