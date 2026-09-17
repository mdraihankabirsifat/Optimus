class_name PlayerController
extends CharacterBody3D
## Gravity-relative movement and camera. Reads the gravity frame from GravityController
## and never assumes Vector3.UP is up.
##
## This file must not own gravity direction or health. See docs/ARCHITECTURE.md.

signal landed(impact_speed: float)
signal jumped()
signal footstep()
signal pause_requested()
signal speed_effect_changed(multiplier: float, remaining: float)
## Online client only: the racer left the world. The server decides the damage.
signal fell_out_of_world(unrecoverable: bool)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var gravity: GravityController = $GravityController
@onready var health: PlayerHealth = $PlayerHealth

var mouse_sensitivity: float = AppConfig.MOUSE_SENSITIVITY
var is_local_player: bool = true
var display_name: String = "You"
var rig: RacerRig
var acceleration: float = AppConfig.ACCELERATION
## Set when Space is released while still rising: the jump is cut short for a smaller hop.
var _jump_cut: bool = false
var racer_colour: Color = Color(0.29, 0.72, 0.98)
## Cleared by MatchController during countdown, after finishing, and on elimination.
## Looking around stays allowed while this is false -- only movement is frozen, so a racer
## can orient themselves before GO.
var input_enabled: bool = true

## Movement intent for this frame. A local player fills these from Input; a bot fills them
## from BotController. Both then run through identical movement code below, which is what
## guarantees a bot cannot out-accelerate, out-run, or clip past a human.
var move_input: Vector2 = Vector2.ZERO
var sprint_input: bool = false
var jump_requested: bool = false

## World-space velocity pushed onto the racer this frame by wind. Cleared after each move,
## so a zone must keep pushing every physics frame the racer stays inside it.
var push_velocity: Vector3 = Vector3.ZERO

## Temporary speed modifier from a mystery box (boost above 1, slow below 1).
var speed_multiplier: float = 1.0
var _speed_effect_timer: float = 0.0

## True while the G chord is held, which suppresses ordinary WASD movement so the
## keypress can be read as a gravity command instead. Read by the HUD for the preview.
var gravity_armed: bool = false

## --- Freedom Duel. 0 means cave rules; the duel sets 1, 2 or 3. ---
## 3: walk the floor plane and jump. 2: walk the floor plane, no jump. 1: walk one axis only.
## No Gravity Moves at any level: the cave's charges play no part in the duel.
var duel_dof: int = 0
## At 1 DOF, the one direction left to walk along.
var duel_axis: Vector3 = Vector3.ZERO
## Freedom Surge and similar arena effects.
var duel_speed: float = 1.0

## --- Networking. All false offline; offline play never touches any of this. ---
## A remote racer's body on this machine: no simulation, it follows transforms the
## network sends. Used for other players and bots on a client, and for humans on the server.
var net_puppet: bool = false
## The local racer in an online race: moves itself, but health and falls are the server's.
var net_client: bool = false
## Pause menu open during an online race: the race keeps running, so input is swallowed.
var menu_blocked: bool = false
var net_target_position: Vector3 = Vector3.ZERO
var net_target_rotation: Quaternion = Quaternion.IDENTITY
var net_on_floor: bool = true
## Exponential smoothing rate for a puppet. The server sets INF: it renders nothing and
## wants exact positions for hazards and the finish trigger.
var net_smoothing: float = 14.0

var _was_on_floor: bool = false
var _coyote_timer: float = 0.0
var _step_accumulator: float = 0.0
var _last_vertical_speed: float = 0.0


func _ready() -> void:
	# Without this every bot's camera fights the local player's for the viewport.
	camera.current = is_local_player
	# The capsule mesh stays in the scene as a placeholder; the rig replaces it at runtime.
	($Visual as MeshInstance3D).mesh = null
	rig = RacerRig.new()
	$Visual.add_child(rig)
	rig.set_colour(racer_colour)
	# FEEL-005/006 playtest values apply to every racer alike, bots included. Online, every
	# machine must move identically, so personal slider values give way to the defaults.
	if GameState.net_role == "":
		gravity.transition_time = SettingsManager.turn_time
		acceleration = SettingsManager.acceleration
	else:
		gravity.transition_time = AppConfig.GRAVITY_TRANSITION_TIME
		acceleration = AppConfig.ACCELERATION
	if is_local_player:
		# Claimed here rather than in the scene file, so bots instancing the same scene
		# do not all announce themselves as the local player.
		add_to_group("local_player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		$Visual.visible = false
		mouse_sensitivity = AppConfig.MOUSE_SENSITIVITY * SettingsManager.sensitivity
		SettingsManager.changed.connect(func() -> void:
			mouse_sensitivity = AppConfig.MOUSE_SENSITIVITY * SettingsManager.sensitivity)
	add_to_group("racers")


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return

	if event.is_action_pressed("pause"):
		pause_requested.emit()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Look is locked during a shift so the slerp is not fought by mouse input.
		if gravity.is_transitioning:
			return
		var motion := event as InputEventMouseMotion
		# Yaw about the body's own local Y, which is local_up by construction.
		rotate_object_local(Vector3.UP, -motion.relative.x * mouse_sensitivity)
		basis = basis.orthonormalized()
		var pitch_sign := 1.0 if SettingsManager.invert_y else -1.0
		head.rotate_object_local(Vector3.RIGHT, pitch_sign * motion.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -AppConfig.PITCH_LIMIT, AppConfig.PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	if net_puppet:
		_puppet_step(delta)
		return
	if is_local_player:
		_gather_local_input()
	if not input_enabled:
		move_input = Vector2.ZERO
		sprint_input = false
		jump_requested = false
		gravity_armed = false

	_tick_speed_effect(delta)

	var up := gravity.local_up()
	up_direction = up

	var vertical := up * velocity.dot(up)
	var planar := velocity - vertical
	var on_floor := is_on_floor()

	if on_floor:
		_coyote_timer = AppConfig.COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	if gravity.is_transitioning or not input_enabled:
		# Movement is locked mid-rotation and outside the racing phase, but the racer
		# still falls -- gravity never stops applying.
		planar = Vector3.ZERO
	else:
		planar = _apply_planar_movement(planar, up, delta)
		if jump_requested and _coyote_timer > 0.0 and not gravity_armed and can_jump():
			vertical = up * (AppConfig.DUEL_JUMP_VELOCITY if duel_dof > 0 else AppConfig.JUMP_VELOCITY)
			_coyote_timer = 0.0
			on_floor = false
			jumped.emit()
	jump_requested = false

	# FEEL-004: tap for a hop, hold for the full jump.
	if _jump_cut:
		_jump_cut = false
		if vertical.dot(up) > AppConfig.JUMP_VELOCITY * 0.35:
			vertical *= 0.5

	if on_floor and vertical.dot(up) <= 0.0:
		# Small downward bias keeps floor snapping stable on slopes and corners.
		vertical = gravity.gravity_dir * 0.1
	else:
		vertical += gravity.gravity_dir * AppConfig.GRAVITY_STRENGTH * delta
		if vertical.length() > AppConfig.TERMINAL_VELOCITY:
			vertical = vertical.normalized() * AppConfig.TERMINAL_VELOCITY

	_last_vertical_speed = vertical.dot(up)
	velocity = planar + vertical + push_velocity
	move_and_slide()
	# Take the push back out so it never accumulates into the racer's own momentum.
	velocity -= push_velocity
	push_velocity = Vector3.ZERO
	_check_world_bounds()
	_emit_feel_events(planar, delta)


func _apply_planar_movement(planar: Vector3, up: Vector3, delta: float) -> Vector3:
	# W means "forward from where I am NOW": the axes come from the camera and the gravity
	# this racer has at this instant, never from the spawn frame. See movement_axes().
	var axes := movement_axes()
	var wish: Vector3 = axes["right"] * move_input.x - axes["forward"] * move_input.y
	wish = wish - up * wish.dot(up)
	if duel_dof == 1 and duel_axis != Vector3.ZERO:
		wish = duel_axis * wish.dot(duel_axis)

	var speed: float = AppConfig.SPRINT_SPEED if sprint_input else AppConfig.WALK_SPEED
	speed *= speed_multiplier * duel_speed

	if wish.length_squared() > 0.001:
		return planar.lerp(wish.normalized() * speed, minf(1.0, acceleration * delta))
	return planar.lerp(Vector3.ZERO, AppConfig.FRICTION * delta)


## Landing thuds and footsteps. Purely notifications; nothing here changes movement.
func _emit_feel_events(planar: Vector3, delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit(absf(_last_vertical_speed))
		_step_accumulator = 0.0
	_was_on_floor = on_floor

	if on_floor and planar.length() > 1.0:
		_step_accumulator += planar.length() * delta
		if _step_accumulator >= AppConfig.FOOTSTEP_DISTANCE:
			_step_accumulator = 0.0
			footstep.emit()


## A remote racer: glide toward the latest networked pose. Velocity is kept so the rig's
## run cycle and the trail still read correctly.
func _puppet_step(delta: float) -> void:
	up_direction = gravity.local_up()
	var t := 1.0 if is_inf(net_smoothing) else 1.0 - exp(-net_smoothing * delta)
	if global_position.distance_to(net_target_position) > 12.0:
		t = 1.0  # a recovery teleport, not motion worth smoothing
	global_position = global_position.lerp(net_target_position, t)
	var current := global_basis.get_rotation_quaternion()
	global_basis = Basis(current.slerp(net_target_rotation, t)).orthonormalized()


## Jumping is the third degree of freedom in the duel. The cave always allows it.
func can_jump() -> bool:
	return duel_dof == 0 or duel_dof >= 3


## The rig asks this rather than is_on_floor(): a puppet never calls move_and_slide.
func grounded() -> bool:
	return net_on_floor if net_puppet else is_on_floor()


## Local player only. Bots never touch Input.
func _gather_local_input() -> void:
	if not input_enabled:
		return
	if menu_blocked:
		move_input = Vector2.ZERO
		sprint_input = false
		gravity_armed = false
		return
	if duel_dof == 0:
		_read_gravity_chord()
	else:
		gravity_armed = false
	if gravity_armed:
		move_input = Vector2.ZERO
		return
	move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprint_input = Input.is_action_pressed("sprint")
	if Input.is_action_just_released("jump"):
		_jump_cut = true
	if Input.is_action_just_pressed("jump"):
		jump_requested = true


func _read_gravity_chord() -> void:
	gravity_armed = Input.is_action_pressed("gravity_mod")
	if not gravity_armed:
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
## Public so the HUD preview can show exactly what each key would do.
func _camera_relative(local_dir: Vector3) -> Vector3:
	var axes := movement_axes()
	return (axes["forward"] * -local_dir.z + axes["right"] * local_dir.x).normalized()


## The racer's current movement frame: {forward, right, up}, all unit length and mutually
## perpendicular. Built fresh every call from the CURRENT gravity and the CURRENT camera:
##   up      = -gravity
##   forward = camera forward projected onto the plane perpendicular to up
##   right   = forward x up
## If the camera looks almost straight along up or down, its projection vanishes; the body's
## forward is used instead, then the camera's own up vector (which points "ahead" when you
## look straight down). Nothing here ever reads the spawn orientation or world up.
func movement_axes() -> Dictionary:
	var up := gravity.local_up()
	var fwd := _project(-head.global_basis.z, up)
	if fwd.length_squared() < 1e-4:
		fwd = _project(-global_basis.z, up)
	if fwd.length_squared() < 1e-4:
		fwd = _project(head.global_basis.y, up)
	if fwd.length_squared() < 1e-4:
		# Last resort: any direction in the plane. Only reachable with a degenerate basis.
		fwd = _project(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.BACK, up)
	fwd = fwd.normalized()
	return {"forward": fwd, "right": fwd.cross(up).normalized(), "up": up}


static func _project(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


func preview_shift_direction(local_dir: Vector3) -> Vector3:
	return GravityController.snap_to_cardinal(_camera_relative(local_dir))


## Mystery box effects. Positive multipliers are boosts, below 1 is a slow.
func apply_speed_effect(multiplier: float, seconds: float) -> void:
	speed_multiplier = multiplier
	_speed_effect_timer = seconds
	speed_effect_changed.emit(speed_multiplier, _speed_effect_timer)


func _tick_speed_effect(delta: float) -> void:
	if _speed_effect_timer <= 0.0:
		return
	_speed_effect_timer -= delta
	if _speed_effect_timer <= 0.0:
		speed_multiplier = 1.0
		speed_effect_changed.emit(1.0, 0.0)


func speed_effect_remaining() -> float:
	return maxf(0.0, _speed_effect_timer)


## GravityController decides whether this is recoverable. The protected vacuum-180 case
## always returns damage; only a genuinely unrecoverable violation returns -1.
## Damage is applied here exactly once -- vacuum_recovered is a notification signal for
## HUD and audio, not a second damage path.
func _check_world_bounds() -> void:
	if global_position.length() < AppConfig.WORLD_BOUNDS:
		return
	var damage := gravity.handle_out_of_bounds()
	if net_client:
		# Recover locally so play continues at once, but a heart is the server's to take.
		fell_out_of_world.emit(damage < 0.0)
		return
	if damage < 0.0:
		health.eliminate()
	else:
		health.apply_damage(damage, "out_of_bounds")


## Gravity direction this racer is currently under. Read by the HUD and by remote
## representations of this player.
func current_gravity() -> Vector3:
	return gravity.gravity_dir


## Applies a racer colour to the visible body. Bots and remote players are told apart by it.
func set_racer_colour(colour: Color) -> void:
	racer_colour = colour
	if rig != null:
		rig.set_colour(colour)
	var visor := find_child("Visor", true, false) as MeshInstance3D
	if visor != null:
		var vm := StandardMaterial3D.new()
		vm.albedo_color = Color(0.08, 0.08, 0.1)
		vm.emission_enabled = true
		vm.emission = colour.lightened(0.5)
		vm.emission_energy_multiplier = 1.5
		visor.set_surface_override_material(0, vm)
	var label := get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.modulate = colour.lightened(0.3)
