class_name GravityController
extends Node
## Owns this racer's personal gravity frame: direction, body orientation, Move charges,
## and the safe-transform history used for protected vacuum recovery.
##
## Every other system treats this as READ-ONLY. Nothing outside this file may assign
## gravity_dir or charges directly.
##
## See docs/CORE_MECHANICS.md for the full specification.

signal shift_started(new_dir: Vector3)
signal shift_completed(new_dir: Vector3)
signal charges_changed(remaining: int)
signal shift_denied(reason: String)
signal vacuum_recovered(damage: float)

const CARDINALS := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
	Vector3.DOWN, Vector3.BACK, Vector3.FORWARD,
]

## Degenerate-projection threshold when rebuilding the basis.
const DEGENERATE_EPSILON := 0.01

@export var transition_time: float = 0.35

var gravity_dir: Vector3 = Vector3.DOWN
var charges: int = 5
var is_transitioning: bool = false

var _body: CharacterBody3D
var _head: Node3D
var _elapsed: float = 0.0
var _from_basis: Basis
var _to_basis: Basis
var _pending_dir: Vector3 = Vector3.DOWN
var _safe_transforms: Array[Transform3D] = []
var _safe_timer: float = 0.0
## Set when a 180 inversion is spent, cleared on the next safe landing.
## Gates the protected "vacuum 180 damages instead of eliminating" rule.
var _inversion_pending: bool = false
## A remote racer's frame. Charges and direction still follow the same rules, but the body
## pose comes from the network, so nothing here rotates it. See PlayerController.net_puppet.
var net_puppet: bool = false


func _ready() -> void:
	transition_time = AppConfig.GRAVITY_TRANSITION_TIME
	charges = AppConfig.MOVE_CHARGES_START
	_body = get_parent() as CharacterBody3D
	assert(_body != null, "GravityController must be a child of a CharacterBody3D")
	_head = _body.get_node("Head") as Node3D
	_align_body_to_gravity(gravity_dir)
	charges_changed.emit(charges)


# --- Public read-only accessors -----------------------------------------------

func local_up() -> Vector3:
	return -gravity_dir


func can_shift() -> bool:
	return charges > 0 and not is_transitioning


# --- Public commands ----------------------------------------------------------

## 90 degree shift. direction_hint is a world-space vector; it gets snapped to the
## nearest of the six cardinals, which is what keeps gravity grid-aligned even though
## the camera can point anywhere.
func request_shift(direction_hint: Vector3) -> void:
	_try_shift(snap_to_cardinal(direction_hint), false)


## 180 degree inversion. Your ceiling becomes your floor.
func request_inversion() -> void:
	_try_shift(-gravity_dir, true)


## Server side of an online shift: the same validation and the same single deduction,
## for a racer whose client asked to fall toward `dir`. Returns whether it was accepted.
func request_direction(dir: Vector3) -> bool:
	var cardinal := snap_to_cardinal(dir)
	return _try_shift(cardinal, cardinal.is_equal_approx(-gravity_dir))


## Online client: the server's word on charges. Signals fire only on a real change.
func net_set_charges(amount: int) -> void:
	if amount == charges:
		return
	charges = clampi(amount, 0, AppConfig.MOVE_CHARGES_MAX)
	charges_changed.emit(charges)


## Online: a remote racer's gravity changed. The pose follows the network; this only
## records the direction and plays the tuck for the length of a transition.
func net_set_gravity(dir: Vector3) -> void:
	var cardinal := snap_to_cardinal(dir)
	if cardinal.is_equal_approx(gravity_dir):
		return
	gravity_dir = cardinal
	_pending_dir = cardinal
	is_transitioning = true
	_elapsed = 0.0


## Online client: the server rejected a shift this machine already started. Snap back to
## the server's frame and charge count.
func net_force_state(dir: Vector3, amount: int) -> void:
	is_transitioning = false
	_inversion_pending = false
	_align_body_to_gravity(snap_to_cardinal(dir))
	net_set_charges(amount)


## Add charges, clamped. Used by Move Refill rewards.
func add_charges(amount: int) -> void:
	charges = mini(charges + amount, AppConfig.MOVE_CHARGES_MAX)
	charges_changed.emit(charges)


## Remove charges, never below zero. Used by the mystery-box penalty. Returns how many
## were actually taken so the caller can describe it honestly.
func remove_charges(amount: int) -> int:
	var taken: int = mini(amount, charges)
	charges -= taken
	charges_changed.emit(charges)
	return taken


## Called by the player controller when an out-of-bounds condition is detected.
## Returns the damage to apply, or -1.0 if the racer should be eliminated instead.
func handle_out_of_bounds() -> float:
	if _inversion_pending:
		# Protected case: a 180 into vacuum must never instantly eliminate.
		_recover_to_safe_transform()
		vacuum_recovered.emit(AppConfig.DAMAGE_VACUUM_FALL)
		return AppConfig.DAMAGE_VACUUM_FALL
	if not _safe_transforms.is_empty():
		# Ordinary fall out of the world: still recoverable, still costs a heart.
		_recover_to_safe_transform()
		return AppConfig.DAMAGE_VACUUM_FALL
	return -1.0


# --- Internals ----------------------------------------------------------------

func _try_shift(new_dir: Vector3, is_inversion: bool) -> bool:
	# A puppet's transition is only a visual timer, and network jitter can make a second,
	# perfectly legal shift arrive a moment before it ends. Only the owner's own frame
	# enforces the lockout strictly.
	var locked := is_transitioning and (not net_puppet or _elapsed < transition_time * 0.5)
	if locked:
		shift_denied.emit("transitioning")
		return false
	if charges <= 0:
		shift_denied.emit("no_charges")
		return false
	if new_dir.is_equal_approx(gravity_dir):
		# Already falling that way. Refuse without spending a charge.
		shift_denied.emit("same_direction")
		return false

	# Validation deliberately does NOT check for a nearby surface.
	# Shifting into empty space is a legal, intentional risk.
	charges -= 1
	charges_changed.emit(charges)

	if is_inversion:
		_inversion_pending = true

	if net_puppet:
		_pending_dir = new_dir
		gravity_dir = new_dir
		_elapsed = 0.0
		is_transitioning = true
		shift_started.emit(new_dir)
		return true

	_pending_dir = new_dir
	_from_basis = _body.global_basis.orthonormalized()
	_to_basis = _build_basis(new_dir)
	_elapsed = 0.0
	is_transitioning = true
	shift_started.emit(new_dir)
	return true


## Build the target orientation without introducing camera roll.
## Walked through case by case in docs/CORE_MECHANICS.md section 5.
func _build_basis(new_dir: Vector3) -> Basis:
	var new_up := -new_dir
	var current := _body.global_basis.orthonormalized()
	var old_fwd := -current.z
	var old_up := current.y

	# Keep looking roughly where we were looking.
	var fwd := old_fwd - new_up * old_fwd.dot(new_up)
	if fwd.length() < DEGENERATE_EPSILON:
		# old_fwd is parallel to the new up (the G+W / G+S cases).
		fwd = old_up - new_up * old_up.dot(new_up)
	fwd = fwd.normalized()

	var right := fwd.cross(new_up).normalized()
	return Basis(right, new_up, -fwd).orthonormalized()


func _align_body_to_gravity(dir: Vector3) -> void:
	gravity_dir = dir
	_body.global_basis = _build_basis(dir)
	_body.up_direction = -dir


func _physics_process(delta: float) -> void:
	if net_puppet:
		if is_transitioning:
			_elapsed += delta
			if _elapsed >= transition_time:
				is_transitioning = false
				shift_completed.emit(gravity_dir)
		return
	if is_transitioning:
		_advance_transition(delta)
	else:
		_sample_safe_transform(delta)


func _advance_transition(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / transition_time, 0.0, 1.0)
	# Ease in-out so the rotation starts and ends gently. This is most of what
	# separates "readable" from "nauseating".
	var eased: float = t * t * (3.0 - 2.0 * t)
	_body.global_basis = _from_basis.slerp(_to_basis, eased).orthonormalized()

	if t >= 1.0:
		is_transitioning = false
		gravity_dir = _pending_dir
		_body.up_direction = -gravity_dir
		_body.global_basis = _to_basis
		shift_completed.emit(gravity_dir)


func _sample_safe_transform(delta: float) -> void:
	_safe_timer += delta
	if _safe_timer < AppConfig.SAFE_TRANSFORM_INTERVAL:
		return
	_safe_timer = 0.0
	if not _body.is_on_floor():
		return

	# A successful landing resolves any pending inversion risk.
	_inversion_pending = false
	_safe_transforms.push_back(_body.global_transform)
	if _safe_transforms.size() > AppConfig.SAFE_TRANSFORM_HISTORY:
		_safe_transforms.pop_front()


func _recover_to_safe_transform() -> void:
	if _safe_transforms.is_empty():
		return
	var recovered: Transform3D = _safe_transforms[-1]
	_body.global_transform = recovered
	_body.velocity = Vector3.ZERO
	# The stored transform's up axis tells us which gravity that pose belonged to.
	_align_body_to_gravity(-recovered.basis.y.normalized())
	is_transitioning = false
	_inversion_pending = false


static func snap_to_cardinal(v: Vector3) -> Vector3:
	var best: Vector3 = CARDINALS[0]
	var best_dot := -INF
	for axis: Vector3 in CARDINALS:
		var d := v.dot(axis)
		if d > best_dot:
			best_dot = d
			best = axis
	return best
