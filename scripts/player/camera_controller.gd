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
var _shake: float = 0.0


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
	_player.gravity.shift_started.connect(func(_d: Vector3) -> void:
		if SettingsManager.camera_effects:
			_punch = shift_fov_punch
			_hitstop())
	_player.landed.connect(func(speed: float) -> void:
		_dip = land_dip * clampf(speed / 14.0, 0.25, 1.4)
		if speed > 16.0:
			add_shake(clampf((speed - 16.0) / 25.0, 0.1, 0.45)))
	_player.health.damaged.connect(func(amount: float, _s: String) -> void:
		add_shake(0.25 + 0.2 * amount))


## VFX-011: positional shake only. Never rotation -- a rolling camera is the one thing the
## gravity mechanic must never produce.
func add_shake(amount: float) -> void:
	if SettingsManager.camera_effects:
		_shake = minf(0.6, _shake + amount)


## VFX-002: a few frames of near-freeze as a Move fires. Timed on the real clock so the
## freeze itself can never be slowed down.
func _hitstop() -> void:
	Engine.time_scale = 0.1
	await get_tree().create_timer(0.055, true, false, true).timeout
	Engine.time_scale = 1.0


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
	if SettingsManager.head_bob and _player.is_on_floor() and planar_speed > 1.0 \
			and not _player.gravity.is_transitioning:
		_bob_phase += delta * bob_frequency * clampf(planar_speed / AppConfig.WALK_SPEED, 0.6, 1.6)
		var strength := bob_amplitude * clampf(planar_speed / AppConfig.SPRINT_SPEED, 0.4, 1.0)
		bob = Vector3(sin(_bob_phase) * strength * 0.6, absf(cos(_bob_phase)) * strength, 0.0)
	else:
		_bob_phase = 0.0

	# Camera-local offset only. Head's Y is the racer's local up, so a dip along local -Y
	# is always "down" in this racer's own frame.
	_shake = maxf(0.0, _shake - delta * 1.6)
	var jitter := Vector3.ZERO
	if _shake > 0.0:
		var ms := float(Time.get_ticks_msec())
		jitter = Vector3(sin(ms * 0.071), sin(ms * 0.053 + 1.3), 0.0) * _shake * _shake * 0.5
	position = _rest_offset + bob + jitter - Vector3(0.0, _dip, 0.0)
