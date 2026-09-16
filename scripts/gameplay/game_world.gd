extends Node3D
## The race. Generates a seeded cave, builds it, places the racers, runs the match, and
## wires the HUD, pause menu, audio and spectator camera to it.
##
## Launched from the lobby it reads GameState. Instanced directly by a test harness it
## uses its exports instead and never changes scene on its own.

## Leave true for a different cave every launch. Set false and pick a seed to reproduce a
## specific cave when chasing a bug.
@export var randomise_seed := true
@export var fixed_seed := 12345
## 1-4 bots, giving 2-5 total racers. Every match needs at least two.
@export_range(1, 4) var bot_count: int = 2
@export_range(0, 2) var bot_skill: int = 2

const BOT_COLOURS: Array[Color] = [
	Color(0.95, 0.45, 0.30),
	Color(0.50, 0.85, 0.45),
	Color(0.85, 0.60, 0.95),
	Color(0.95, 0.85, 0.35),
]
const BOT_NAMES: Array[String] = ["Rook", "Vex", "Nim", "Kilo"]
const PLAYER_COLOUR := Color(0.36, 0.78, 1.0)
const RESULTS_DELAY := 2.5

var graph: CaveGraph
var seed_value: int
var bots: Array[Node3D] = []
var hud: RaceHUD
var pause_menu: PauseMenu

var _from_menu := false
var _local_resolved_at: float = -1.0
var _spectate_camera: Camera3D
var _spectate_index: int = 0
var _spectate_forward := Vector3.FORWARD

@onready var _player: PlayerController = $Player
@onready var match_controller: MatchController = $MatchController


func _ready() -> void:
	add_to_group("cave_root")
	_from_menu = GameState.launched_from_menu
	GameState.launched_from_menu = false

	seed_value = fixed_seed
	if _from_menu:
		seed_value = GameState.seed_value
		bot_count = GameState.bot_count
		bot_skill = GameState.bot_skill
	elif randomise_seed:
		seed_value = randi() % 1000000
	GameState.last_match_seed = seed_value

	var generator := CaveGenerator.new()
	graph = generator.generate(seed_value)
	if graph == null:
		push_error("Cave generation failed after %d attempts: %s"
			% [generator.attempts_used, generator.last_failure])
		return

	CaveBuilder.new().build(graph, self, seed_value)
	_player.global_position = CaveBuilder.floor_position(graph.spawn_cell)
	_player.display_name = "You"
	_player.set_racer_colour(PLAYER_COLOUR)

	print("seed %d | %d cells | %d hops to exit | %d Moves required | %d loops" % [
		seed_value,
		graph.cell_count(),
		int(graph.distances_from(graph.spawn_cell).get(graph.finish_cell, -1)),
		graph.spine_climb_cost(),
		graph.cycle_count(),
	])

	GameState.stats.clear()
	_register(_player, "You", PLAYER_COLOUR, false)
	_spawn_bots()

	hud = RaceHUD.new()
	add_child(hud)
	hud.setup(self, _player, match_controller)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.restart_requested.connect(_restart)
	_player.pause_requested.connect(pause_menu.open)

	for box: MysteryBox in get_tree().get_nodes_in_group("mystery_boxes"):
		box.opened.connect(_on_box_opened)
		box.clue_granted.connect(hud.on_clue)

	_spectate_camera = Camera3D.new()
	_spectate_camera.fov = 75.0
	add_child(_spectate_camera)

	match_controller.countdown_tick.connect(func(v: int) -> void:
		if v > 0:
			AudioManager.play_sfx("countdown"))
	match_controller.match_started.connect(func() -> void: AudioManager.play_sfx("go"))
	match_controller.racer_finished.connect(_on_racer_finished)
	match_controller.racer_eliminated.connect(_on_racer_eliminated)
	match_controller.match_ended.connect(_on_match_ended)

	AudioManager.stop_music()
	AudioManager.play_ambience()
	match_controller.begin_countdown()


## Bots spawn in a ring around the shared starting chamber so nobody begins inside
## anyone else, and every racer starts the same distance from the exit.
func _spawn_bots() -> void:
	var scene: PackedScene = load("res://scenes/bots/bot_player.tscn")
	var origin := CaveBuilder.floor_position(graph.spawn_cell)
	var count: int = clampi(bot_count, 1, 4)

	for i in count:
		var bot: Node3D = scene.instantiate()
		add_child(bot)
		var angle := TAU * float(i) / float(count)
		bot.global_position = origin + Vector3(cos(angle), 0.0, sin(angle)) * 1.8

		var controller: BotController = bot.get_node("BotController")
		controller.setup(graph, BOT_NAMES[i], BOT_COLOURS[i], i + 1, bot_skill)
		_register(bot, BOT_NAMES[i], BOT_COLOURS[i], true)
		bots.append(bot)


## Match registration, stats and audio for one racer. The local racer hears its own
## events flat; everyone else is positional, so a bot flipping gravity across a cavern
## is something you can hear.
func _register(racer: PlayerController, racer_name: String, colour: Color, is_bot: bool) -> void:
	match_controller.register_racer(racer, racer_name, is_bot)
	GameState.register_racer_stats(racer_name, colour, is_bot)
	var g := racer.gravity
	g.shift_started.connect(func(_d: Vector3) -> void:
		GameState.bump_stat(racer_name, "moves_used")
		if is_bot:
			AudioManager.play_sfx_3d("racer_shift", racer.global_position, 2.0)
		else:
			AudioManager.play_sfx("shift"))
	racer.health.damaged.connect(func(amount: float, _s: String) -> void:
		GameState.bump_stat(racer_name, "damage_taken", amount)
		if is_bot:
			AudioManager.play_sfx_3d("damage", racer.global_position, -4.0)
		else:
			AudioManager.play_sfx("damage"))
	if is_bot:
		return
	g.shift_completed.connect(func(_d: Vector3) -> void: AudioManager.play_sfx("shift_done", -3.0))
	g.shift_denied.connect(func(reason: String) -> void:
		if reason != "transitioning":
			AudioManager.play_sfx("denied"))
	racer.health.shield_absorbed.connect(func() -> void: AudioManager.play_sfx("shield"))
	racer.footstep.connect(func() -> void: AudioManager.play_sfx("footstep", -10.0, 0.15))
	racer.jumped.connect(func() -> void: AudioManager.play_sfx("jump", -6.0))
	racer.landed.connect(func(speed: float) -> void:
		if speed > 4.0:
			AudioManager.play_sfx("land", linear_to_db(clampf(speed / 20.0, 0.3, 1.0))))


func _process(delta: float) -> void:
	if match_controller.phase == MatchController.Phase.RACING and _local_resolved_at >= 0.0:
		var left := AppConfig.LOCAL_RESOLVED_GRACE - (match_controller.elapsed - _local_resolved_at)
		hud.set_banner("Spectating %s    [Tab] next racer    [Enter] end race now  (%ds)"
			% [_spectate_target_name(), ceili(maxf(left, 0.0))])
		if left <= 0.0:
			match_controller.force_end()
	_update_spectate_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu != null and pause_menu.is_open():
		return
	# Browsers drop pointer lock on focus loss; a click takes it back.
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _local_resolved_at < 0.0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _local_resolved_at < 0.0:
		return
	if event.is_action_pressed("spectate_next"):
		_spectate_index += 1
	elif event.is_action_pressed("skip_wait"):
		match_controller.force_end()


# --- Spectating -------------------------------------------------------------------

func _spectate_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r: Dictionary in match_controller.racers:
		if r["body"] != _player and not r["finished"] and not r["eliminated"]:
			out.append(r["body"])
	if out.is_empty():
		out.append_array(bots)
	return out


func _spectate_target_name() -> String:
	var targets := _spectate_targets()
	if targets.is_empty():
		return "-"
	return (targets[_spectate_index % targets.size()] as PlayerController).display_name


## A chase camera in the target's own gravity frame, so you see a bot walking a wall the
## way that bot experiences it.
func _update_spectate_camera(delta: float) -> void:
	if _local_resolved_at < 0.0:
		return
	var targets := _spectate_targets()
	if targets.is_empty():
		return
	var target := targets[_spectate_index % targets.size()] as PlayerController
	var up := target.gravity.local_up()
	var planar := target.velocity - up * target.velocity.dot(up)
	if planar.length() > 1.0:
		_spectate_forward = _spectate_forward.lerp(planar.normalized(), 1.0 - exp(-3.0 * delta))
	_spectate_forward = (_spectate_forward - up * _spectate_forward.dot(up))
	if _spectate_forward.length() < 0.1:
		_spectate_forward = -target.global_basis.z
	_spectate_forward = _spectate_forward.normalized()
	var want := target.global_position + up * 2.6 - _spectate_forward * 4.5
	_spectate_camera.global_position = _spectate_camera.global_position.lerp(want, 1.0 - exp(-6.0 * delta))
	_spectate_camera.look_at(target.global_position + up * 0.6, up)


func _begin_spectating() -> void:
	if _local_resolved_at >= 0.0:
		return
	_local_resolved_at = match_controller.elapsed
	await get_tree().create_timer(2.0).timeout
	if match_controller.phase != MatchController.Phase.RACING:
		return
	_spectate_camera.global_position = _player.global_position
	_spectate_camera.make_current()


# --- Events -----------------------------------------------------------------------

func _on_box_opened(racer: PlayerController, reward: String, description: String) -> void:
	GameState.bump_stat(racer.display_name, "boxes")
	hud.on_box_opened(racer, reward, description)
	if racer != _player:
		return
	AudioManager.play_sfx("box_open")
	var cue := {"heart": "heart", "move": "move_refill", "speed": "speed", "shield": "shield",
		"slow": "penalty", "lose_move": "penalty", "clue": "clue"}
	AudioManager.play_sfx(cue.get(reward, "notify"))


func _on_racer_finished(racer_name: String, place: int, time: float) -> void:
	print("%s finished #%d in %s" % [racer_name, place, MatchController.format_time(time)])
	if racer_name == _player.display_name:
		AudioManager.play_sfx("finish")
		_begin_spectating()
	else:
		AudioManager.play_sfx("notify", -4.0)


func _on_racer_eliminated(racer_name: String, _time: float) -> void:
	if racer_name == _player.display_name:
		AudioManager.play_sfx("eliminated")
		_begin_spectating()


func _on_match_ended(results: Array) -> void:
	print("--- results ---")
	for entry: Dictionary in results:
		if entry["finished"]:
			print("  #%d  %s  %s"
				% [entry["place"], entry["name"], MatchController.format_time(entry["finish_time"])])
		elif entry["eliminated"]:
			print("  --  %s  ELIMINATED at %s"
				% [entry["name"], MatchController.format_time(entry["elimination_time"])])
		else:
			print("  --  %s  DNF" % entry["name"])

	GameState.record_results(results, seed_value, match_controller.elapsed)
	if not _from_menu:
		return
	hud.set_banner("")
	hud.show_centre("RACE OVER", RESULTS_DELAY + 1.0, UiKit.EMBER)
	await get_tree().create_timer(RESULTS_DELAY).timeout
	AudioManager.stop_ambience()
	SceneRouter.go_to(SceneRouter.RESULTS)


func _restart() -> void:
	GameState.prepare_match(seed_value, bot_count)
	AudioManager.stop_ambience()
	SceneRouter.start_match()


## Degrees of Freedom at the racer's current cell: how many axes offer travel here.
## This is the theme stated as a number, and it is why the HUD shows it.
func player_degrees_of_freedom() -> int:
	if graph == null or _player == null:
		return 0
	return graph.degrees_of_freedom(CaveBuilder.world_to_cell(_player.global_position))


func player_cell() -> Vector3i:
	if _player == null:
		return Vector3i.ZERO
	return CaveBuilder.world_to_cell(_player.global_position)
