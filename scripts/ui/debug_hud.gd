extends CanvasLayer
## Phase 2 prototype HUD: gravity frame, match timer, countdown and results.
## Developer C replaces this with the real HUD under UI-003.

@onready var readout: Label = $Readout
@onready var centre: Label = $CentreMessage
@onready var flash: ColorRect = $Flash

var _player: PlayerController
var _match: MatchController
var _cave: Node
var _flash_timer: float = 0.0
var _shift_count: int = 0
var _centre_timer: float = 0.0


func _ready() -> void:
	flash.color = Color(1.0, 0.25, 0.25, 0.0)
	centre.text = ""
	await get_tree().process_frame

	_player = get_tree().get_first_node_in_group("local_player") as PlayerController
	if _player == null:
		readout.text = "No local player found."
		return
	_player.gravity.shift_completed.connect(_on_shift_completed)
	_player.gravity.shift_denied.connect(_on_shift_denied)

	_cave = get_tree().get_first_node_in_group("cave_root")
	if _cave != null and "match_controller" in _cave:
		_match = _cave.match_controller
		_match.countdown_tick.connect(_on_countdown_tick)
		_match.match_started.connect(_on_match_started)
		_match.racer_finished.connect(_on_racer_finished)
		_match.match_ended.connect(_on_match_ended)


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		flash.color.a = maxf(0.0, _flash_timer) * 0.5

	if _centre_timer > 0.0:
		_centre_timer -= delta
		if _centre_timer <= 0.0:
			centre.text = ""

	if _player == null:
		return

	var g := _player.gravity
	var lines: Array = []

	if _match != null:
		lines.append("TIME     %s" % MatchController.format_time(_match.elapsed))
		lines.append("PHASE    %s" % MatchController.Phase.keys()[_match.phase])

	lines.append_array([
		"HEARTS   %s" % _hearts_bar(_player.health.hearts),
		"MOVES    %s" % _charge_bar(g.charges),
		"GRAVITY  %s" % _axis_name(g.gravity_dir),
		"LOCAL UP %s" % _axis_name(g.local_up()),
		"STATE    %s" % ("ROTATING" if g.is_transitioning else "STABLE"),
		"SHIFTS   %d" % _shift_count,
	])

	if _cave != null and _cave.graph != null:
		lines.append("DOF      %d  (axes you can travel here)" % _cave.player_degrees_of_freedom())
		lines.append("SEED     %d   CELL %s" % [_cave.seed_value, _cave.player_cell()])

	lines.append_array([
		"",
		"%s %s %s %s move   %s sprint (with gift)   %s jump" % [UiKit.binding_text("move_forward"), UiKit.binding_text("move_left"),
			UiKit.binding_text("move_back"), UiKit.binding_text("move_right"), UiKit.binding_text("sprint"), UiKit.binding_text("jump")],
		"%s + move = 90 degree gravity shift" % UiKit.binding_text("gravity_mod"),
		"%s = 180 degree inversion" % UiKit.chord_text("gravity_mod", "jump"),
		"%s releases the mouse" % UiKit.binding_text("pause"),
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


func _show_centre(text: String, seconds: float) -> void:
	centre.text = text
	_centre_timer = seconds


func _on_countdown_tick(value: int) -> void:
	_show_centre("GO!" if value <= 0 else str(value), 1.1)


func _on_match_started() -> void:
	_show_centre("GO!", 0.8)


func _on_racer_finished(racer_name: String, place: int, time: float) -> void:
	_show_centre("%s  -  PLACE %d\n%s"
		% [racer_name, place, MatchController.format_time(time)], 5.0)


func _on_match_ended(results: Array) -> void:
	var lines: Array = ["RACE COMPLETE", ""]
	for entry: Dictionary in results:
		if entry["finished"]:
			lines.append("#%d   %s   %s"
				% [entry["place"], entry["name"], MatchController.format_time(entry["finish_time"])])
		elif entry["eliminated"]:
			lines.append("--   %s   ELIMINATED" % entry["name"])
		else:
			lines.append("--   %s   DNF" % entry["name"])
	lines.append("")
	lines.append("seed %d" % (_cave.seed_value if _cave != null else 0))
	_show_centre("\n".join(lines), 9999.0)


func _on_shift_completed(_dir: Vector3) -> void:
	_shift_count += 1


func _on_shift_denied(reason: String) -> void:
	# Denial must never be silent, or players assume the game is broken.
	_flash_timer = 0.4
	print("Gravity shift denied: ", reason)
