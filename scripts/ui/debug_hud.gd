extends CanvasLayer
## Phase 1 prototype HUD. Displays the gravity frame so the mechanic can be verified.
## Developer C replaces this with the real HUD under UI-003.

@onready var readout: Label = $Readout
@onready var flash: ColorRect = $Flash

var _player: PlayerController
var _flash_timer: float = 0.0
var _shift_count: int = 0


func _ready() -> void:
	flash.color = Color(1.0, 0.25, 0.25, 0.0)
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("local_player") as PlayerController
	if _player == null:
		readout.text = "No local player found."
		return
	_player.gravity.shift_completed.connect(_on_shift_completed)
	_player.gravity.shift_denied.connect(_on_shift_denied)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		flash.color.a = maxf(0.0, _flash_timer) * 0.5

	if _player == null:
		return

	var g := _player.gravity
	var lines := [
		"HEARTS   %s" % _hearts_bar(_player.health.hearts),
		"MOVES    %s" % _charge_bar(g.charges),
		"GRAVITY  %s" % _axis_name(g.gravity_dir),
		"LOCAL UP %s" % _axis_name(g.local_up()),
		"STATE    %s" % ("ROTATING" if g.is_transitioning else "STABLE"),
		"SHIFTS   %d" % _shift_count,
	]

	var cave := get_tree().get_first_node_in_group("cave_root")
	if cave != null and cave.graph != null:
		lines.append("DOF      %d  (axes you can travel here)" % cave.player_degrees_of_freedom())
		lines.append("SEED     %d   CELL %s" % [cave.seed_value, cave.player_cell()])

	lines.append_array([
		"",
		"WASD move   SHIFT sprint   SPACE jump",
		"G + WASD  = 90 degree gravity shift",
		"G + SPACE = 180 degree inversion",
		"ESC releases the mouse",
	])
	readout.text = "\n".join(lines)


func _hearts_bar(hearts: float) -> String:
	var full := int(hearts)
	var half := 1 if hearts - float(full) >= 0.5 else 0
	var empty := int(AppConfig.HEARTS_MAX) - full - half
	return "@".repeat(full) + "-".repeat(half) + ".".repeat(empty) + "  %.1f" % hearts


func _charge_bar(charges: int) -> String:
	var used: int = AppConfig.MOVE_CHARGES_START - charges
	return "#".repeat(charges) + ".".repeat(maxi(0, used)) + "  %d" % charges


func _axis_name(v: Vector3) -> String:
	if v.is_equal_approx(Vector3.DOWN): return "-Y  (down)"
	if v.is_equal_approx(Vector3.UP): return "+Y  (up)"
	if v.is_equal_approx(Vector3.LEFT): return "-X"
	if v.is_equal_approx(Vector3.RIGHT): return "+X"
	if v.is_equal_approx(Vector3.FORWARD): return "-Z"
	if v.is_equal_approx(Vector3.BACK): return "+Z"
	return str(v.snappedf(0.01))


func _on_shift_completed(_dir: Vector3) -> void:
	_shift_count += 1


func _on_shift_denied(reason: String) -> void:
	# Denial must never be silent, or players assume the game is broken.
	_flash_timer = 0.4
	print("Gravity shift denied: ", reason)
