extends Node3D
## The race. Generates a seeded cave, builds it, places the racers, runs the match, and
## wires the HUD, pause menu, audio and spectator camera to it.
##
## Launched from the lobby it reads GameState. Instanced directly by a test harness it
## uses its exports instead and never changes scene on its own.
##
## Three roles, one scene:
##   offline  ("")        the judging fallback. Never touches NetManager.
##   "client"             an online race on a player's machine: the local racer moves
##                        itself, everyone else is a puppet, the server owns every outcome.
##   "server"             a room's race on the dedicated server: no local player, no HUD;
##                        humans are puppets of their clients, bots are simulated here.

## Leave true for a different cave every launch. Set false and pick a seed to reproduce a
## specific cave when chasing a bug.
@export var randomise_seed := true
@export var fixed_seed := 12345
## 1-4 bots, giving 2-5 total racers. Every match needs at least two.
@export_range(1, 4) var bot_count: int = 2
@export_range(0, 2) var bot_skill: int = 2
@export_range(0, 2) var cave_size: int = 1
## Prompt 2: the first two out of the cave fight the Freedom Duel for Champion. Harnesses
## that measure pure cave traversal switch it off.
@export var duel_enabled: bool = true
## Prompt 3: "normal" or "rush", and the Rush length. Harnesses set these directly.
@export var ruleset: String = AppConfig.RULESET_NORMAL
@export var rush_seconds: int = AppConfig.RUSH_DEFAULT

const BOT_COLOURS: Array[Color] = [
	Color(0.95, 0.45, 0.30),
	Color(0.50, 0.85, 0.45),
	Color(0.85, 0.60, 0.95),
	Color(0.95, 0.85, 0.35),
]
const BOT_NAMES: Array[String] = ["Rook", "Vex", "Nim", "Kilo"]
const PLAYER_COLOUR := Color(0.36, 0.78, 1.0)
const RESULTS_DELAY := 2.5
const SPAWN_RING_RADIUS := 1.8

## Online role, see the header. The dedicated server sets both before adding the world to
## the tree; a client picks them up from GameState.
var net_role: String = ""
var net_config: Dictionary = {}
var net_match: NetMatch
## ART-012: the environment this race is dressed in. Never affects generation.
var theme: CaveTheme
@export var theme_id: String = "stone_age"

var graph: CaveGraph
## CaveGenerator.profile for this race: "normal", "rush180", "rush300" or "rush480".
var generation_profile: String = "normal"
var seed_value: int
var bots: Array[Node3D] = []
## Online only: racers this machine does not simulate.
var remotes: Array[Node3D] = []
var hud: RaceHUD
var duel: FreedomDuel
var duel_hud: DuelHUD
var pause_menu: PauseMenu
## Racer name -> {boxes, moves_used, damage_taken, colour, is_bot}. Offline and on a client
## GameState.stats is this same dictionary; each server room keeps its own.
var stats: Dictionary = {}

var _from_menu := false
var _local_resolved_at: float = -1.0
var _spectate_camera: Camera3D
var _spectate_index: int = 0
var _spectate_forward := Vector3.FORWARD
var _move_regen := false
var _regen_timer := 0.0
var _heartbeat_timer := 0.0
## Cells the local racer has stood in. The map (UI-015) draws only these.
var visited_cells: Dictionary = {}
var _last_cell := Vector3i(-999, -999, -999)
var _ghost: GhostRacer
var _ghost_frames: Array = []
var _ghost_timer := 0.0
var _crumb_mat: StandardMaterial3D

@onready var _player: PlayerController = $Player
@onready var match_controller: MatchController = $MatchController


func _enter_tree() -> void:
	# Before any child is ready, so everything built inside can scope its lookups here.
	add_to_group("cave_root")


func _ready() -> void:
	_from_menu = GameState.launched_from_menu
	GameState.launched_from_menu = false
	if net_role == "" and _from_menu and GameState.net_role == "client":
		net_role = "client"
		net_config = GameState.net_config

	seed_value = fixed_seed
	if net_role != "":
		seed_value = int(net_config.get("seed", fixed_seed))
		cave_size = int(net_config.get("cave_size", 1))
		bot_skill = int(net_config.get("bot_skill", 1))
		_move_regen = bool(net_config.get("move_regen", false))
		theme_id = String(net_config.get("theme", "stone_age"))
		ruleset = String(net_config.get("ruleset", AppConfig.RULESET_NORMAL))
		rush_seconds = int(net_config.get("rush_seconds", AppConfig.RUSH_DEFAULT))
	elif _from_menu:
		theme_id = GameState.theme_id
		seed_value = GameState.seed_value
		bot_count = GameState.bot_count
		bot_skill = GameState.bot_skill
		_move_regen = GameState.move_regen
		cave_size = GameState.cave_size
		ruleset = GameState.ruleset
		rush_seconds = GameState.rush_seconds
	elif randomise_seed:
		seed_value = randi() % 1000000
	if not _is_server():
		GameState.last_match_seed = seed_value
		GameState.last_cave_size = cave_size
		GameState.new_record = false

	if ruleset not in AppConfig.RULESETS:
		ruleset = AppConfig.RULESET_NORMAL
	if rush_seconds not in AppConfig.RUSH_DURATIONS:
		rush_seconds = AppConfig.RUSH_DEFAULT
	var generator := CaveGenerator.new()
	generator.configure(cave_size, ruleset, rush_seconds)
	generation_profile = generator.profile
	graph = generator.generate(seed_value)
	if not _is_server():
		GameState.last_ruleset = ruleset
		GameState.last_rush_seconds = rush_seconds
		GameState.last_move_regen = _move_regen
		GameState.last_time_up = false
	if graph == null:
		push_error("Cave generation failed after %d attempts: %s"
			% [generator.attempts_used, generator.last_failure])
		return

	theme = CaveTheme.by_id(theme_id)
	var builder := CaveBuilder.new()
	builder.theme = theme
	builder.build(graph, self, seed_value)
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		# Duplicate: rooms on a server share the scene's resource otherwise.
		world_env.environment = world_env.environment.duplicate()
		theme.apply_environment(world_env.environment)
	print("seed %d | %d cells | %d hops to exit | %d Moves required | %d loops" % [
		seed_value,
		graph.cell_count(),
		int(graph.distances_from(graph.spawn_cell).get(graph.finish_cell, -1)),
		graph.spine_climb_cost(),
		graph.cycle_count(),
	])

	stats = {}
	if not _is_server():
		GameState.stats = stats

	if _is_server():
		# A server has no one sitting at it.
		remove_child(_player)
		_player.queue_free()
		_player = null
		match_controller.end_when_one_left = true
		_spawn_net_racers()
	elif net_role == "client":
		match_controller.net_client = true
		_spawn_net_racers()
	else:
		_player.global_position = CaveBuilder.floor_position(graph.spawn_cell)
		var my_name := local_display_name()
		_player.display_name = my_name
		_player.set_racer_colour(PLAYER_COLOUR)
		var label := _player.get_node_or_null("NameLabel") as Label3D
		if label != null:
			label.text = my_name
		_register(_player, my_name, PLAYER_COLOUR, false)
		_spawn_bots()

	for box: MysteryBox in WorldScope.nodes(self, "mystery_boxes"):
		box.opened.connect(_on_box_opened)
		box.net_client = net_role == "client"
	for tile: CrumbleTile in WorldScope.nodes(self, "crumble_tiles"):
		tile.net_client = net_role == "client"

	if duel_enabled and AppConfig.DUEL_ENABLED and match_controller.racers.size() >= 2:
		duel = FreedomDuel.new()
		duel.name = "FreedomDuel"
		duel.net_client = net_role == "client"
		add_child(duel)
		duel.setup(self, match_controller)
		match_controller.duel = duel

	if ruleset == AppConfig.RULESET_RUSH:
		match_controller.cave_time_limit = float(rush_seconds)
	match_controller.cave_time_up.connect(_on_cave_time_up)

	match_controller.racer_finished.connect(_on_racer_finished)
	match_controller.racer_eliminated.connect(_on_racer_eliminated)
	match_controller.match_ended.connect(_on_match_ended)

	if net_role != "":
		net_match = NetMatch.new()
		net_match.name = "NetMatch"
		add_child(net_match)
		net_match.setup(self)

	if _is_server():
		# The server's NetMatch starts the countdown once every client has loaded the cave.
		return

	hud = RaceHUD.new()
	add_child(hud)
	hud.setup(self, _player, match_controller)
	for box: MysteryBox in WorldScope.nodes(self, "mystery_boxes"):
		box.clue_granted.connect(hud.on_clue)
	if duel != null:
		duel_hud = DuelHUD.new()
		add_child(duel_hud)
		duel_hud.setup(self, duel, _player, hud)
		duel.phase_changed.connect(_on_duel_phase)
	pause_menu = PauseMenu.new()
	pause_menu.online = net_role == "client"
	add_child(pause_menu)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.leave_requested.connect(_leave_online)
	pause_menu.open_changed.connect(func(open: bool) -> void:
		_player.menu_blocked = open and net_role == "client")
	_player.pause_requested.connect(pause_menu.open)

	if net_role == "":
		_ghost = GhostRacer.load_for(seed_value, cave_size, record_tag())
		if _ghost != null:
			add_child(_ghost)
			_ghost.visible = false

	_spectate_camera = Camera3D.new()
	_spectate_camera.fov = 75.0
	add_child(_spectate_camera)

	match_controller.countdown_tick.connect(func(v: int) -> void:
		if v > 0:
			AudioManager.play_sfx("countdown"))
	match_controller.match_started.connect(func() -> void:
		AudioManager.play_sfx("go")
		AudioManager.play_music("music_race", -16.0)
		var gates := WorldScope.nodes(self, "spawn_gates")
		if not gates.is_empty():
			AudioManager.play_sfx("gate", -4.0)
		for gate in gates:
			(gate as SpawnGate).open())

	if theme.personal_light_energy > 0.0:
		# Dark Cave: a lamp that rides with the racer onto walls and ceilings.
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp"
		lamp.light_color = theme.personal_light_colour
		lamp.light_energy = theme.personal_light_energy
		lamp.omni_range = CaveBuilder.CELL_SIZE * 1.6
		lamp.position = Vector3(0.0, 0.6, 0.0)
		_player.add_child(lamp)

	if CaveDebugView.available() and net_role == "":
		var debug_view := CaveDebugView.new()
		add_child(debug_view)
		debug_view.setup(self, graph)

	AudioManager.stop_music()
	AudioManager.play_ambience(theme.ambience_pitch, theme.ambience_volume_db)
	match_controller.begin_countdown()
	_prewarm_effects()


## Prompt 3: the saved player name offline, "You" if none was ever entered. Bots keep their
## names; a player who picks a bot's name gets " (you)" so stats and results never merge.
func local_display_name() -> String:
	var n := LobbyState.clean_name(SettingsManager.player_name)
	if n == "" or not _from_menu:
		n = "You"
	for bot_name: String in BOT_NAMES:
		if n.to_lower() == bot_name.to_lower():
			n = "%s (you)" % n.left(LobbyState.NAME_MAX - 6)
	return n


func _is_server() -> bool:
	return net_role == "server"


## SHIP-008: GL Compatibility compiles a shader the first time something is drawn with it.
## The first dust puff after GO used to cost a 120 ms hitch. Draw each effect once in view
## during the countdown, when a stutter is invisible, instead.
func _prewarm_effects() -> void:
	await get_tree().process_frame
	var up := _player.gravity.local_up()
	var ahead := _player.global_position - _player.camera.global_basis.z * 2.0
	Vfx.dust_puff(self, ahead, up, 0.3)
	visited_cells[graph.spawn_cell] = true
	_last_cell = graph.spawn_cell
	_drop_breadcrumb()


## Bots spawn in a ring around the shared starting chamber so nobody begins inside
## anyone else, and every racer starts the same distance from the exit.
func _spawn_bots() -> void:
	var scene: PackedScene = load("res://scenes/bots/bot_player.tscn")
	var origin := CaveBuilder.floor_position(graph.spawn_cell)
	var count: int = clampi(bot_count, 0, 4)

	for i in count:
		var bot: Node3D = scene.instantiate()
		add_child(bot)
		var angle := TAU * float(i) / float(count)
		bot.global_position = origin + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING_RADIUS

		var controller: BotController = bot.get_node("BotController")
		controller.setup(graph, BOT_NAMES[i], BOT_COLOURS[i], i + 1, bot_skill)
		_register(bot, BOT_NAMES[i], BOT_COLOURS[i], true)
		bots.append(bot)


## Online: every racer in the roster, in racer-id order, around the same starting ring on
## every machine. The server simulates its bots and puppets the humans; a client drives its
## own racer and puppets everyone else.
func _spawn_net_racers() -> void:
	var roster: Array = net_config.get("roster", [])
	var local_rid := int(net_config.get("local_rid", -1))
	var origin := CaveBuilder.floor_position(graph.spawn_cell)
	var count := maxi(1, roster.size())
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var bot_scene: PackedScene = load("res://scenes/bots/bot_player.tscn")

	for entry: Dictionary in roster:
		var rid := int(entry["rid"])
		var racer_name := String(entry["name"])
		var colour := Color.html(String(entry["colour"]))
		var is_bot := bool(entry["is_bot"])
		var angle := TAU * float(rid) / float(count)
		var spot := origin + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING_RADIUS
		var body: PlayerController

		if net_role == "client" and rid == local_rid:
			body = _player
			body.net_client = true
			body.health.net_client = true
			body.display_name = racer_name
			body.set_racer_colour(colour)
			GameState.net_local_name = racer_name
		elif _is_server() and is_bot:
			body = bot_scene.instantiate()
			add_child(body)
			(body.get_node("BotController") as BotController).setup(graph, racer_name, colour, rid + 1, bot_skill)
			bots.append(body)
		else:
			body = player_scene.instantiate()
			body.is_local_player = false
			body.net_puppet = true
			if _is_server():
				body.net_smoothing = INF
			add_child(body)
			body.gravity.net_puppet = true
			# On a client, local copies of hazards overlap puppets too; only the server's
			# copies may take their hearts.
			body.health.net_client = net_role == "client"
			body.display_name = racer_name
			body.set_racer_colour(colour)
			var label := body.get_node_or_null("NameLabel") as Label3D
			if label != null:
				label.text = racer_name
			remotes.append(body)

		body.global_position = spot
		body.net_target_position = spot
		body.net_target_rotation = body.global_basis.get_rotation_quaternion()
		_register(body, racer_name, colour, is_bot)


## Match registration, stats and audio for one racer. The local racer hears its own
## events flat; everyone else is positional, so a rival flipping gravity across a cavern
## is something you can hear.
func _register(racer: PlayerController, racer_name: String, colour: Color, is_bot: bool) -> void:
	match_controller.register_racer(racer, racer_name, is_bot)
	_register_stats(racer_name, colour, is_bot)
	var g := racer.gravity
	g.shift_started.connect(func(_d: Vector3) -> void: bump_stat(racer.display_name, "moves_used"))
	racer.health.damaged.connect(func(amount: float, _s: String) -> void:
		# Cave damage only; the duel keeps its own numbers.
		if not racer.health.duel_mode:
			bump_stat(racer.display_name, "damage_taken", amount))
	if _is_server():
		return

	var is_local := racer == _player
	racer.health.eliminated.connect(func() -> void:
		if not is_local:
			racer.rig.emote("argh"))
	# VFX-004 / VFX-005: dust off whatever surface this racer calls the floor.
	racer.footstep.connect(func() -> void:
		var up := g.local_up()
		Vfx.dust_puff(self, racer.global_position - up * 0.9, up, 0.25))
	racer.landed.connect(func(speed: float) -> void:
		if speed > 6.0:
			var up := g.local_up()
			Vfx.dust_puff(self, racer.global_position - up * 0.9, up, clampf(speed / 18.0, 0.4, 1.6)))
	if not is_local:
		var trail := RacerTrail.new()
		add_child(trail)
		trail.setup(racer)
	g.shift_started.connect(func(_d: Vector3) -> void:
		if is_local:
			AudioManager.play_sfx("shift")
		else:
			AudioManager.play_sfx_3d("racer_shift", racer.global_position, 2.0))
	racer.health.damaged.connect(func(_amount: float, _s: String) -> void:
		if is_local:
			AudioManager.play_sfx("damage")
		else:
			AudioManager.play_sfx_3d("damage", racer.global_position, -4.0))
	if not is_local:
		return
	g.shift_completed.connect(func(_d: Vector3) -> void: AudioManager.play_sfx("shift_done", -3.0))
	g.shift_denied.connect(func(reason: String) -> void:
		if reason != "transitioning":
			AudioManager.play_sfx("denied"))
	racer.health.shield_absorbed.connect(func() -> void: AudioManager.play_sfx("shield"))
	racer.health.second_chance_used.connect(func() -> void: AudioManager.play_sfx("second_chance"))
	racer.add_child(Vfx.dust_motes())
	racer.footstep.connect(func() -> void: AudioManager.play_sfx("footstep", -10.0, 0.15))
	racer.jumped.connect(func() -> void: AudioManager.play_sfx("jump", -6.0))
	racer.landed.connect(func(speed: float) -> void:
		if speed > 4.0:
			AudioManager.play_sfx("land", linear_to_db(clampf(speed / 20.0, 0.3, 1.0))))


func _register_stats(racer_name: String, colour: Color, is_bot: bool) -> void:
	stats[racer_name] = {
		"hearts_traded": 0,
		"boxes": 0,
		"moves_used": 0,
		"damage_taken": 0.0,
		"colour": colour,
		"is_bot": is_bot,
	}


func bump_stat(racer_name: String, key: String, amount: float = 1.0) -> void:
	if not stats.has(racer_name):
		return
	var entry: Dictionary = stats[racer_name]
	if entry[key] is int:
		entry[key] = int(entry[key]) + int(amount)
	else:
		entry[key] = float(entry[key]) + amount


## Online: a bot took over a dropped racer, so its stats follow the new name.
func rename_stats(old_name: String, new_name: String, is_bot: bool) -> void:
	if stats.has(old_name) and old_name != new_name:
		stats[new_name] = stats[old_name]
		stats.erase(old_name)
	if stats.has(new_name):
		stats[new_name]["is_bot"] = is_bot


func _process(delta: float) -> void:
	if _is_server():
		_tick_regen(delta)
		return
	if net_role == "":
		_tick_regen(delta)
	_tick_heartbeat(delta)
	_track_local(delta)
	if net_role == "" and bots.is_empty() and _local_resolved_at >= 0.0 \
			and match_controller.phase == MatchController.Phase.RACING \
			and match_controller.elapsed - _local_resolved_at > 2.0:
		match_controller.force_end()
	_tick_duel_input()
	if match_controller.phase == MatchController.Phase.RACING and _local_resolved_at >= 0.0:
		if duel != null and duel.claims_end():
			hud.set_banner(_duel_spectate_banner())
		elif net_role == "client":
			hud.set_banner("Spectating %s    [" + UiKit.binding_text("spectate_next") + "] next racer    the race ends when the others resolve"
				% _spectate_target_name())
		else:
			var left := AppConfig.LOCAL_RESOLVED_GRACE - (match_controller.elapsed - _local_resolved_at)
			hud.set_banner("Spectating %s    [" + UiKit.binding_text("spectate_next") + "] next racer    [" + UiKit.binding_text("skip_wait") + "] end race now  (%ds)"
				% [_spectate_target_name(), ceili(maxf(left, 0.0))])
			if left <= 0.0:
				match_controller.force_end()
	_update_spectate_camera(delta)


## Everyone racing against the local player on this machine.
func _others() -> Array[Node3D]:
	var out: Array[Node3D] = []
	out.append_array(bots)
	out.append_array(remotes)
	return out


## Breadcrumbs, the map's visited set, and the ghost recording.
func _track_local(delta: float) -> void:
	if match_controller.phase != MatchController.Phase.RACING:
		return
	var elapsed := match_controller.elapsed
	if _ghost != null:
		_ghost.show_at(elapsed)
	if _local_resolved_at >= 0.0:
		return
	_ghost_timer += delta
	while _ghost_timer >= GhostRacer.SAMPLE and _ghost_frames.size() * GhostRacer.SAMPLE <= elapsed:
		_ghost_timer -= GhostRacer.SAMPLE
		_ghost_frames.append([_player.global_position, _player.global_basis.get_rotation_quaternion()])

	var cell := CaveBuilder.world_to_cell(_player.global_position)
	if cell == _last_cell or not graph.has_cell(cell):
		return
	_last_cell = cell
	if visited_cells.has(cell):
		return
	visited_cells[cell] = true
	_drop_breadcrumb()


## LEVEL-013: a faint mark on whatever surface you are standing on as you enter a new cell,
## so a corridor you have already searched looks searched.
func _drop_breadcrumb() -> void:
	if _crumb_mat == null:
		_crumb_mat = StandardMaterial3D.new()
		_crumb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_crumb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_crumb_mat.albedo_color = Color(_player.racer_colour, 0.35)
	var up := _player.gravity.local_up()
	var mark := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.35
	disc.bottom_radius = 0.35
	disc.height = 0.02
	disc.radial_segments = 6
	mark.mesh = disc
	mark.material_override = _crumb_mat
	add_child(mark)
	var right := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mark.global_basis = Basis(right, up, right.cross(up))
	mark.global_position = _player.global_position - up * 0.88


## AXIS-010: optional slow Move regeneration, identical for every racer. Offline and on the
## server only: a client's charges are whatever the server says.
func _tick_regen(delta: float) -> void:
	if not _move_regen or match_controller.phase != MatchController.Phase.RACING:
		return
	_regen_timer += delta
	if _regen_timer < AppConfig.MOVE_REGEN_INTERVAL:
		return
	_regen_timer = 0.0
	for r: Dictionary in match_controller.racers:
		var racer := r["body"] as PlayerController
		if r["finished"] or r["eliminated"] or racer.gravity.charges >= AppConfig.MOVE_CHARGES_START:
			continue
		racer.gravity.add_charges(1)
		if racer == _player and hud != null:
			hud.toast("+1 Gravity Move regenerated", UiKit.SKY, 2.0)
			AudioManager.play_sfx("move_refill", -6.0)


## HEALTH-006: a heartbeat you can hear when one more hit ends your race.
func _tick_heartbeat(delta: float) -> void:
	var h := _player.health
	if h.is_eliminated or h.hearts > AppConfig.LOW_HEALTH or match_controller.phase != MatchController.Phase.RACING:
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = 0.85 if h.hearts <= 0.5 else 1.1
		AudioManager.play_sfx("heartbeat", -2.0)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or (pause_menu != null and pause_menu.is_open()):
		return
	# Browsers drop pointer lock on focus loss; a click takes it back.
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _local_resolved_at < 0.0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("toggle_map"):
		hud.toggle_map()
	if event.is_action_pressed("exchange_heart", false) and not event.is_echo() and _local_resolved_at < 0.0:
		_local_exchange()
	for k in 3:
		if event.is_action_pressed("emote_%d" % (k + 1)) and match_controller.phase != MatchController.Phase.PENDING:
			var text: String = EMOTES[k]
			_player.rig.emote(text)
			hud.toast("You: %s" % text, _player.racer_colour, 1.5)
			AudioManager.play_sfx("emote", -4.0)
			if net_match != null:
				net_match.send_emote(k)
	if duel != null and duel.phase == FreedomDuel.Phase.WAITING and duel.finalist_a == _player 			and event.is_action_pressed("skip_wait") and net_role == "" 			and duel.wait_time >= AppConfig.DUEL_SKIP_AFTER:
		duel.resolve_by_default("Qualified 1st ended the wait")
		return
	if _local_resolved_at < 0.0:
		return
	if event.is_action_pressed("spectate_next"):
		_spectate_index += 1
	elif event.is_action_pressed("skip_wait") and net_role == "":
		match_controller.force_end()


const EMOTES: Array[String] = ["hey!", "GG", "catch me!"]


# --- Freedom Duel ----------------------------------------------------------------------

## Held fire repeats at the blaster's own rate; Axis Lock fires on press.
func _tick_duel_input() -> void:
	if duel == null or not duel.is_fighting() or not duel.fighters.has(_player):
		return
	if (pause_menu != null and pause_menu.is_open()) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var st: Dictionary = duel.fighters[_player]
	if Input.is_action_pressed("duel_fire") and float(st["pulse_cd"]) <= 0.0:
		_local_fire("pulse")
	if Input.is_action_just_pressed("duel_lock") and float(st["lock_cd"]) <= 0.0:
		_local_fire("lock")


func _local_fire(kind: String) -> void:
	var from := _player.head.global_position
	var dir := -_player.camera.global_basis.z
	if net_role == "client":
		# The server decides whether it hit; start the cooldown here so the key feels right.
		var st: Dictionary = duel.fighters[_player]
		st["pulse_cd" if kind == "pulse" else "lock_cd"] = AppConfig.PULSE_COOLDOWN if kind == "pulse" else AppConfig.AXIS_LOCK_COOLDOWN
		net_match.send_duel_fire(kind, from, dir)
	else:
		duel.fire(_player, kind, from, dir)


func _on_duel_phase(p: FreedomDuel.Phase) -> void:
	if p == FreedomDuel.Phase.INTRO:
		if not duel.is_finalist(_player) and _local_resolved_at < 0.0:
			# Still in the cave when the duel began: the race is over for you, watch the final.
			_begin_spectating()
		elif duel.is_finalist(_player):
			_spectate_camera.current = false
			_player.camera.make_current()
	if hud != null:
		# The duel HUD takes the screen once the local racer is in the arena or the final is on.
		hud.visible = p == FreedomDuel.Phase.OFF \
			or (p == FreedomDuel.Phase.WAITING and not duel.is_finalist(_player))


func _duel_spectate_banner() -> String:
	match duel.phase:
		FreedomDuel.Phase.WAITING:
			var skip := ("    [%s] end now" % UiKit.binding_text("skip_wait")) if net_role == "" else ""
			return "Spectating %s    [" + UiKit.binding_text("spectate_next") + "] next racer    %s is Qualified 1st, waiting for a second finalist%s" \
				% [_spectate_target_name(), duel.finalist_a.display_name, skip]
		FreedomDuel.Phase.INTRO, FreedomDuel.Phase.FIGHT:
			return ""
		_:
			return ""


# --- Spectating -------------------------------------------------------------------

func _spectate_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if duel != null and duel.phase >= FreedomDuel.Phase.INTRO:
		for body: PlayerController in [duel.finalist_a, duel.finalist_b]:
			if body != null and body != _player and is_instance_valid(body):
				out.append(body)
		if not out.is_empty():
			return out
	for r: Dictionary in match_controller.racers:
		if r["body"] != _player and not r["finished"] and not r["eliminated"] and is_instance_valid(r["body"]):
			out.append(r["body"])
	if out.is_empty():
		out.append_array(_others())
	return out


func _spectate_target_name() -> String:
	var targets := _spectate_targets()
	if targets.is_empty():
		return "-"
	return (targets[_spectate_index % targets.size()] as PlayerController).display_name


## A chase camera in the target's own gravity frame, so you see a rival walking a wall the
## way that rival experiences it.
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
	if racer != null:
		bump_stat(racer.display_name, "boxes")
	if _is_server():
		return
	hud.on_box_opened(racer, reward, description)
	if racer != _player:
		return
	AudioManager.play_sfx("box_open")
	var cue := {"heart": "heart", "move": "move_refill", "speed": "speed", "shield": "shield",
		"slow": "penalty", "lose_move": "penalty", "clue": "clue"}
	AudioManager.play_sfx(cue.get(reward, "notify"))


func _on_racer_finished(racer_name: String, place: int, time: float) -> void:
	print("%s finished #%d in %s" % [racer_name, place, MatchController.format_time(time)])
	if _is_server():
		return
	if racer_name == _player.display_name:
		AudioManager.play_sfx("finish")
		_player.rig.cheer()
		if net_role == "":
			GameState.new_record = SettingsManager.submit_cave_time(time, seed_value, cave_size, record_tag())
			if GameState.new_record and _ghost_frames.size() > 2:
				GhostRacer.save(seed_value, cave_size, _ghost_frames, record_tag())
		# The first two out are finalists: they go to the arena, not the spectator camera.
		if duel == null or place > 2:
			_begin_spectating()
	else:
		AudioManager.play_sfx("notify", -4.0)
		for other: Node3D in _others():
			var b := other as PlayerController
			if b.display_name == racer_name:
				b.rig.cheer()
				b.rig.emote("GG!" if place == 1 else "made it!")


func _on_racer_eliminated(racer_name: String, _time: float) -> void:
	if _is_server():
		return
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
			print("  --  %s  %s at %s" % [entry["name"],
				"DISCONNECTED" if entry.get("disconnected", false) else "ELIMINATED",
				MatchController.format_time(entry["elimination_time"])])
		else:
			print("  --  %s  DNF" % entry["name"])
	if _is_server():
		return

	AudioManager.stop_music()
	GameState.record_results(results, seed_value, match_controller.elapsed)
	if duel != null and duel.phase == FreedomDuel.Phase.ENDED:
		GameState.last_duel = {
			"fought": duel.runner_up != null,
			"duration": duel.duel_time,
			"reason": duel.end_reason,
		}
	else:
		GameState.last_duel = {}
	GameState.last_results_online = net_role == "client"
	if not _from_menu:
		return
	hud.set_banner("")
	var delay := RESULTS_DELAY
	if duel != null and duel.champion != null:
		# The duel HUD is showing the Champion; give that moment room before results.
		delay += 2.0
	else:
		hud.show_centre("RACE OVER", RESULTS_DELAY + 1.0, UiKit.EMBER)
	await get_tree().create_timer(delay).timeout
	AudioManager.stop_ambience()
	SceneRouter.go_to(SceneRouter.RESULTS)


## Records and ghosts are kept apart for every setting that changes the cave or the race:
## generator version, Normal or a Rush length, and Move regeneration. Older records under
## the previous plain "seed:size" key are left in the file untouched, never mixed in.
func record_tag() -> String:
	return GameState.make_record_tag(generation_profile, _move_regen)


## Prompt 3, Rush: the cave phase is over.
func _on_cave_time_up(qualifiers: int) -> void:
	if not _is_server():
		GameState.last_time_up = qualifiers < 2
	print("rush time up: %d qualifier(s)" % qualifiers)
	if _is_server() or hud == null:
		return
	AudioManager.play_sfx("sudden_death", -4.0)
	if qualifiers == 0:
		hud.show_centre("TIME UP  -  NO QUALIFIERS", 4.0, UiKit.DANGER)
	elif qualifiers == 1:
		hud.show_centre("TIME UP", 3.0, UiKit.DANGER)


# --- Prompt 3: trading a heart for a Move ------------------------------------------------

var _last_heart_armed_until: float = -1.0


## The one authoritative transaction, used by the local player offline, by the server for a
## client's request, and by bots. Validates everything, then takes exactly one heart and adds
## exactly one Move, and starts the last-heart deadline if that was the final heart.
## Returns "" on success or a player-readable reason.
func request_heart_exchange(body: PlayerController) -> String:
	if net_role == "client":
		return "the server decides"
	if match_controller.phase != MatchController.Phase.RACING or match_controller.cave_expired:
		return "only while racing in the cave"
	var r := {}
	for racer: Dictionary in match_controller.racers:
		if racer["body"] == body:
			r = racer
	if r.is_empty() or r["finished"] or r["eliminated"]:
		return "only while racing in the cave"
	if duel != null and duel.is_finalist(body):
		return "not after qualifying"
	if _move_regen:
		return "off while Move regeneration is on"
	if not body.input_enabled:
		return "only while racing in the cave"
	if body.gravity.charges >= AppConfig.MOVE_CHARGES_MAX:
		return "your Moves are full"
	var problem := body.health.exchange_problem()
	if problem != "":
		return problem
	if not body.health.exchange_heart():
		return "you need a full heart"
	body.gravity.add_charges(1)
	bump_stat(body.display_name, "hearts_traded")
	return ""


## Local key press. Spending the last heart needs a second press, with the deadline explained.
func _local_exchange() -> void:
	var h := _player.health
	var now := match_controller.elapsed
	if h.hearts >= AppConfig.HEART_EXCHANGE_COST and h.hearts < AppConfig.HEART_EXCHANGE_COST * 2.0 \
			and not h.in_grace() and now > _last_heart_armed_until:
		_last_heart_armed_until = now + AppConfig.LAST_HEART_CONFIRM
		hud.toast("Last heart: press %s again. You get a Move and %ds to live -- this cannot be cancelled."
			% [UiKit.binding_text("exchange_heart"), int(AppConfig.LAST_HEART_GRACE)], UiKit.DANGER, AppConfig.LAST_HEART_CONFIRM)
		AudioManager.play_sfx("denied", -6.0)
		return
	_last_heart_armed_until = -1.0
	if net_role == "client":
		net_match.send_exchange()
		return
	on_exchange_result(_player, request_heart_exchange(_player))


func on_exchange_result(body: PlayerController, reason: String) -> void:
	if body != _player or hud == null:
		return
	if reason == "":
		AudioManager.play_sfx("move_refill")
		hud.toast("Traded a heart for a Move", UiKit.SKY, 2.0)
	else:
		AudioManager.play_sfx("denied", -4.0)
		hud.toast("Cannot trade a heart: %s" % reason, UiKit.TEXT_DIM, 2.0)


func _restart() -> void:
	if net_role != "":
		return
	GameState.cave_size = cave_size
	GameState.theme_id = theme_id
	GameState.ruleset = ruleset
	GameState.rush_seconds = rush_seconds
	GameState.prepare_match(seed_value, bot_count)
	AudioManager.stop_ambience()
	SceneRouter.start_match()


## Pause menu "Leave race" online. The race carries on without you on the server.
func _leave_online() -> void:
	AudioManager.stop_ambience()
	AudioManager.stop_music()
	if net_match != null:
		net_match.leave()
	SceneRouter.go_to(SceneRouter.MAIN_MENU)


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


func local_player() -> PlayerController:
	return _player
