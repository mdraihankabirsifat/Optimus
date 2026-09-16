class_name PlayerController
extends CharacterBody3D
## Gravity-relative movement and camera. Reads the gravity frame from GravityController
## and never assumes Vector3.UP is up.
##
## This file must not own gravity direction or health. See docs/ARCHITECTURE.md.

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gravity: GravityController = $GravityController
@onready var health: PlayerHealth = $PlayerHealth

var mouse_sensitivity: float = AppConfig.MOUSE_SENSITIVITY
var is_local_player: bool = true

## True while the G chord is held, which suppresses ordinary WASD movement so the
## keypress can be read as a gravity command instead.
var _gravity_armed: bool = false


func _ready() -> void:
	if is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		$Visual.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return

	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Look is locked during a shift so the slerp is not fought by mouse input.
		if gravity.is_transitioning:
			return
		var motion := event as InputEventMouseMotion
		# Yaw about the body's own local Y, which is local_up by construction.
		rotate_object_local(Vector3.UP, -motion.relative.x * mouse_sensitivity)
		basis = basis.orthonormalized()
		head.rotate_object_local(Vector3.RIGHT, -motion.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -AppConfig.PITCH_LIMIT, AppConfig.PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if is_local_player:
		_read_gravity_chord()

	var up := gravity.local_up()
	up_direction = up

	var vertical := up * velocity.dot(up)
	var planar := velocity - vertical

	if gravity.is_transitioning:
		# Movement is locked mid-rotation, but the racer still falls.
		planar = Vector3.ZERO
	else:
		planar = _apply_planar_movement(planar, up, delta)
		if Input.is_action_just_pressed("jump") and is_on_floor() and not _gravity_armed:
			vertical = up * AppConfig.JUMP_VELOCITY

	if is_on_floor() and vertical.dot(up) <= 0.0:
		# Small downward bias keeps floor snapping stable on slopes and corners.
		vertical = gravity.gravity_dir * 0.1
	else:
		vertical += gravity.gravity_dir * AppConfig.GRAVITY_STRENGTH * delta
		if vertical.length() > AppConfig.TERMINAL_VELOCITY:
			vertical = vertical.normalized() * AppConfig.TERMINAL_VELOCITY

	velocity = planar + vertical
	move_and_slide()
	_check_world_bounds()


func _apply_planar_movement(planar: Vector3, up: Vector3, delta: float) -> Vector3:
	var input := Vector2.ZERO
	if not _gravity_armed:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# global_basis.y is local_up, so this vector already lies in the walk plane.
	var wish := global_basis * Vector3(input.x, 0.0, input.y)
	wish = wish - up * wish.dot(up)

	var speed: float = AppConfig.SPRINT_SPEED if Input.is_action_pressed("sprint") \
		else AppConfig.WALK_SPEED

	if wish.length_squared() > 0.001:
		return planar.lerp(wish.normalized() * speed, AppConfig.ACCELERATION * delta)
	return planar.lerp(Vector3.ZERO, AppConfig.FRICTION * delta)


func _read_gravity_chord() -> void:
	_gravity_armed = Input.is_action_pressed("gravity_mod")
	if not _gravity_armed:
		return

	if Input.is_action_just_pressed("move_forward"):
		gravity.request_shift(_camera_relative(Vector3.FORWARD))
	elif Input.is_action_just_pressed("move_back"):
		gravity.request_shift(_camera_relative(Vector3.BACK))
	elif Input.is_action_just_pressed("move_left"):
		gravity.request_shift(_camera_relative(Vector3.LEFT))
	elif Input.is_action_just_pressed("move_right"):
		gravity.request_shift(_camera_relative(Vector3.RIGHT))
	elif Input.is_action_just_pressed("jump"):
		gravity.request_inversion()


## Convert a camera-space direction into a world vector lying in the current walk plane.
## Gravity commands are camera-relative, never world-axis-relative.
func _camera_relative(local_dir: Vector3) -> Vector3:
	var up := gravity.local_up()
	var fwd := -head.global_basis.z
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.01:
		# Looking straight up or down; fall back to the body's forward.
		fwd = -global_basis.z
	fwd = fwd.normalized()
	var right := fwd.cross(up).normalized()
	return (fwd * -local_dir.z + right * local_dir.x).normalized()


## GravityController decides whether this is recoverable. The protected vacuum-180 case
## always returns damage; only a genuinely unrecoverable violation returns -1.
## Damage is applied here exactly once — vacuum_recovered is a notification signal for
## HUD and audio, not a second damage path.
func _check_world_bounds() -> void:
	if global_position.length() < AppConfig.WORLD_BOUNDS:
		return
	var damage := gravity.handle_out_of_bounds()
	if damage < 0.0:
		health.eliminate()
	else:
		health.apply_damage(damage, "out_of_bounds")


## Gravity direction this racer is currently under. Read by the HUD and by remote
## representations of this player.
func current_gravity() -> Vector3:
	return gravity.gravity_dir
