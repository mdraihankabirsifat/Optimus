class_name NetMatch
extends Node
## One online race's link to the network. GameWorld adds it in the "server" and "client"
## roles; offline races never create one.
##
## SERVER: the authority. Humans are puppets posed by their own clients; everything that
## decides the race happens here and only here:
##   - Move charges: a client asks to shift, this validates and deducts exactly once
##   - hearts: server-side hazards hit server-side bodies; falls are reported and applied here
##   - mystery boxes: first valid request wins, the server rolls and applies the reward
##   - clues go only to the racer who earned them
##   - countdown, clock, finish detection, placements, elimination, results
##   - bots are simulated here, with the same discovered-graph planner as offline
##   - a client's pose is accepted only if it is physically plausible
##
## CLIENT: sends its own pose, shift requests, box requests and falls; mirrors everything
## else. It predicts its own Gravity Moves so the core mechanic never waits on the network,
## and snaps back if the server disagrees.
##
## Racers are addressed by racer id (rid): their index in the roster and in
## MatchController.racers, identical on every machine.

const SEND_RATE := 20.0
## The server starts the countdown when every client has loaded, or after this long.
const LOAD_TIMEOUT := 15.0
## Fastest legitimate travel in world units per second: sprint with a boost, pushed by
## wind, falling at terminal velocity -- rounded up generously.
const MAX_PLAUSIBLE_SPEED := 75.0
const POSE_SLACK := 2.5
const CORRECTION_COOLDOWN := 0.5
## Extra reach over the local interact ray, allowing for a pose a few frames old.
const INTERACT_SLACK := 2.5
const SPIDER_SMOOTHING := 12.0

var world: Node3D
var mc: MatchController
var role: String = ""
var room_code: String = ""
var racers: Array[PlayerController] = []
var local_rid: int = -1

var _boxes: Dictionary = {}          # box_index -> MysteryBox
var _tiles: Array[CrumbleTile] = []
var _gifts: Array[SprintGift] = []
var _spiders: Array[SpiderEnemy] = []
var _pistons: Array[PistonHazard] = []
var _send_timer: float = 0.0
var _server_time: float = 0.0

# Server
var _rid_of_peer: Dictionary = {}
var _peer_of_rid: Dictionary = {}
var _loaded: Dictionary = {}
var _load_timer: float = 0.0
var _countdown_started: bool = false
var _dirty: Dictionary = {}
var _last_pose_time: Dictionary = {}
var _grace_until: Dictionary = {}
var _last_correction: Dictionary = {}
var _humans_resolved_at: float = -1.0
var _results_sent: bool = false
var _last_exchange: Dictionary = {}
## Freedom Duel: the whole duel state goes out on every change and a few times a second.
var _duel: FreedomDuel
var _duel_dirty: bool = false
var _duel_timer: float = 0.0
const DUEL_SEND_RATE := 10.0
## How far a client's claimed muzzle may be from where the server has that finalist.
const DUEL_AIM_SLACK := 3.0

# Client
var _spider_targets: Array = []
var _server_lost: bool = false


func setup(p_world: Node3D) -> void:
	world = p_world
	role = String(world.get("net_role"))
	mc = world.get("match_controller")
	var config: Dictionary = world.get("net_config")
	room_code = String(config.get("room", ""))
	for r: Dictionary in mc.racers:
		racers.append(r["body"] as PlayerController)

	for box: Node in WorldScope.nodes(world, "mystery_boxes"):
		_boxes[(box as MysteryBox).box_index] = box
	for tile: Node in WorldScope.nodes(world, "crumble_tiles"):
		_tiles.append(tile as CrumbleTile)
	for gift: Node in WorldScope.nodes(world, "sprint_gifts"):
		_gifts.append(gift as SprintGift)
	for s: Node in WorldScope.nodes(world, "spiders"):
		_spiders.append(s as SpiderEnemy)
	_spiders.sort_custom(func(a: SpiderEnemy, b: SpiderEnemy) -> bool: return a.spider_id < b.spider_id)
	for h: Node in WorldScope.nodes(world, "hazards"):
		if h is PistonHazard:
			_pistons.append(h)

	if role == "server":
		_setup_server(config)
	else:
		_setup_client(config)


static func dir_index(v: Vector3) -> int:
	var snapped := GravityController.snap_to_cardinal(v)
	for i in 6:
		if Vector3(CaveGraph.DIRS[i]).is_equal_approx(snapped):
			return i
	return CaveGraph.DIR_DOWN


static func dir_vector(i: int) -> Vector3:
	return Vector3(CaveGraph.DIRS[clampi(i, 0, 5)])


func _process(delta: float) -> void:
	_server_time += delta
	if role == "server":
		_server_process(delta)
	else:
		_client_process(delta)


# ======================================================================================
# Server
# ======================================================================================

func _setup_server(config: Dictionary) -> void:
	for entry: Dictionary in config.get("roster", []):
		if not entry["is_bot"]:
			_rid_of_peer[int(entry["peer"])] = int(entry["rid"])
			_peer_of_rid[int(entry["rid"])] = int(entry["peer"])

	for rid in racers.size():
		var b := racers[rid]
		var mark := func(_x: Variant = null) -> void: _dirty[rid] = true
		b.health.hearts_changed.connect(mark)
		b.health.shield_changed.connect(mark)
		b.health.second_chance_changed.connect(mark)
		b.health.last_heart_started.connect(mark)
		b.gravity.charges_changed.connect(mark)
		b.gravity.shift_started.connect(func(d: Vector3) -> void:
			_broadcast("s_shift", [rid, dir_index(d)]))

	for box: MysteryBox in _boxes.values():
		box.opened.connect(func(racer: PlayerController, reward: String, description: String) -> void:
			_broadcast("s_box", [box.box_index, racers.find(racer), reward, description]))
		box.clue_granted.connect(func(racer: PlayerController, direction: Vector3, vertical: int) -> void:
			var peer := int(_peer_of_rid.get(racers.find(racer), 0))
			if peer != 0:
				NetManager.server_send(peer, "s_clue", [direction, vertical]))
	for i in _tiles.size():
		_tiles[i].crumbling_started.connect(func() -> void: _broadcast("s_crumble", [i]))
	for gift: SprintGift in _gifts:
		gift.taken.connect(func(g: SprintGift, racer: PlayerController) -> void:
			_broadcast("s_gift", [g.gift_index, racers.find(racer), false]))
		gift.restored.connect(func(g: SprintGift) -> void:
			_broadcast("s_gift", [g.gift_index, -1, true]))

	mc.countdown_tick.connect(func(v: int) -> void: _broadcast("s_countdown", [v]))
	mc.match_started.connect(func() -> void: _broadcast("s_go", [mc.elapsed]))
	mc.racer_finished.connect(func(racer_name: String, place: int, time: float) -> void:
		_broadcast("s_finished", [_rid_named(racer_name), place, time]))
	mc.racer_eliminated.connect(func(racer_name: String, time: float) -> void:
		var rid := _rid_named(racer_name)
		var gone := rid >= 0 and bool(mc.racers[rid]["disconnected"])
		_broadcast("s_eliminated", [rid, time, gone]))
	mc.match_ended.connect(_server_send_results)
	_setup_server_duel()
	_setup_server_battle()


## The server owns the duel. Every decision -- qualification, freedom, hits, locks, cores,
## shifts, sudden death, the Champion -- is made by the FreedomDuel here and sent out; each
## event is sent once, from the one place it happened, so nothing can be applied twice.
func _setup_server_duel() -> void:
	_duel = world.get("duel")
	if _duel == null:
		return
	var mark := func(_a: Variant = null, _b: Variant = null) -> void: _duel_dirty = true
	_duel.qualified.connect(func(_b: PlayerController, _o: int) -> void: _send_duel_state())
	_duel.phase_changed.connect(func(p: FreedomDuel.Phase) -> void:
		if p == FreedomDuel.Phase.INTRO:
			# Humans are puppets here; hold them at their arena spawn until their clients
			# arrive, correcting any cave pose still in flight.
			for body: PlayerController in [_duel.finalist_a, _duel.finalist_b]:
				_last_correction.erase(racers.find(body))
		_send_duel_state())
	_duel.shot.connect(func(shooter: PlayerController, kind: String, from: Vector3, to: Vector3, hit: PlayerController) -> void:
		_broadcast("s_duel_event", ["shot", [racers.find(shooter), kind, from, to, racers.find(hit) if hit != null else -1]])
		_duel_dirty = true)
	_duel.axis_locked.connect(func(t: PlayerController, removed: String) -> void:
		_send_duel_state()
		_broadcast("s_duel_event", ["locked", [racers.find(t), removed]]))
	_duel.lock_resisted.connect(func(t: PlayerController) -> void:
		_broadcast("s_duel_event", ["resisted", [racers.find(t)]]))
	_duel.core_captured.connect(func(b: PlayerController, effect: String) -> void:
		_send_duel_state()
		_broadcast("s_duel_event", ["core", [racers.find(b), effect]]))
	_duel.axis_restored.connect(mark)
	_duel.core_spawned.connect(mark)
	_duel.dof_shift.connect(mark)
	_duel.dof_shift_ended.connect(mark)
	_duel.sudden_death_started.connect(mark)
	_duel.duel_ended.connect(func(c: PlayerController, r: PlayerController, reason: String) -> void:
		_send_duel_state()
		_broadcast("s_duel_event", ["end", [racers.find(c), racers.find(r) if r != null else -1, reason]]))


## Master Prompt 4: the server's BattleMode decides every hit, kill, respawn and score; this
## relays each once, from the one place it happened.
var _battle: BattleMode
var _battle_timer := 0.0
var _battle_dirty := false
var _last_battle_fire: Dictionary = {}


func _setup_server_battle() -> void:
	_battle = world.get("battle")
	if _battle == null:
		return
	_battle.shot.connect(func(sh: PlayerController, from: Vector3, to: Vector3, hit: PlayerController) -> void:
		_broadcast("s_battle_event", ["shot", [racers.find(sh), from, to, racers.find(hit) if hit != null else -1]]))
	_battle.killed.connect(func(k: PlayerController, v: PlayerController) -> void:
		_broadcast("s_battle_event", ["kill", [racers.find(k) if k != null else -1, racers.find(v)]])
		_battle_dirty = true)
	_battle.respawned.connect(func(b: PlayerController, pos: Vector3) -> void:
		# Hold a human's server copy at the spawn so its client's old pose is corrected there.
		_last_correction.erase(racers.find(b))
		_broadcast("s_battle_event", ["respawn", [racers.find(b), pos]])
		_battle_dirty = true)
	_battle.scores_changed.connect(func() -> void: _battle_dirty = true)


func server_on_battle_fire(peer: int, origin: Vector3, dir: Vector3) -> void:
	var b := _human_body(peer)
	if b == null or _battle == null:
		return
	if not origin.is_finite() or not dir.is_finite() or dir.length_squared() < 0.25:
		return
	var rid := _rid_for(peer)
	# Retried or duplicated requests inside one cooldown are dropped here as well as by the
	# blaster's own cooldown, so one trigger pull can never score twice.
	if _server_time - float(_last_battle_fire.get(rid, -INF)) < AppConfig.PULSE_COOLDOWN * 0.8:
		return
	_last_battle_fire[rid] = _server_time
	if origin.distance_to(b.net_target_position) > DUEL_AIM_SLACK:
		origin = b.net_target_position + Vector3(0, 0.6, 0)
	_battle.fire(b, origin, dir.normalized())


func send_battle_fire(origin: Vector3, dir: Vector3) -> void:
	if role == "client":
		NetManager.send_to_server("c_battle_fire", [origin, dir])


func client_on_battle_state(rows: Array) -> void:
	var b: BattleMode = world.get("battle")
	if b != null:
		b.net_apply_state(rows)


func client_on_battle_event(kind: String, args: Array) -> void:
	var b: BattleMode = world.get("battle")
	if b != null:
		b.net_event(kind, args)


func _send_duel_state() -> void:
	_duel_dirty = false
	_duel_timer = 1.0 / DUEL_SEND_RATE
	_broadcast("s_duel_state", [_duel.net_state()])


func server_on_duel_fire(peer: int, kind: String, origin: Vector3, dir: Vector3) -> void:
	var b := _human_body(peer)
	if b == null or _duel == null or not _duel.is_fighting() or not _duel.fighters.has(b):
		return
	if kind != "pulse" and kind != "lock":
		return
	if not origin.is_finite() or not dir.is_finite() or dir.length_squared() < 0.25:
		return
	# The shot must start at the shooter, give or take a snapshot of lag.
	if origin.distance_to(b.net_target_position) > DUEL_AIM_SLACK:
		origin = b.net_target_position + Vector3(0, 0.6, 0)
	_duel.fire(b, kind, origin, dir.normalized())

func _rid_named(racer_name: String) -> int:
	for r: Dictionary in mc.racers:
		if r["name"] == racer_name:
			return int(r["rid"])
	return -1


func _broadcast(method: String, args: Array) -> void:
	for peer: int in _peer_of_rid.values():
		NetManager.server_send(peer, method, args)


func _server_process(delta: float) -> void:
	if not _countdown_started:
		_load_timer += delta
		if _all_loaded() or _load_timer >= LOAD_TIMEOUT:
			_countdown_started = true
			mc.begin_countdown()

	for rid: int in _dirty.keys():
		var b := racers[rid]
		if is_instance_valid(b):
			var flags := (1 if b.health.has_shield else 0) | (2 if b.health.has_second_chance else 0) \
				| (4 if b.health.is_eliminated else 0)
			_broadcast("s_racer_state", [rid, b.health.hearts, b.gravity.charges, flags, b.health.grace_left])
	_dirty.clear()

	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = 1.0 / SEND_RATE
		_broadcast("s_snapshot", [mc.elapsed, _server_time, _pose_list(), _spider_list()])

	if _battle != null:
		_battle_timer -= delta
		if _battle_dirty or _battle_timer <= 0.0:
			_battle_dirty = false
			_battle_timer = 0.2
			_broadcast("s_battle_state", [_battle.net_state()])

	if _duel != null and _duel.phase != FreedomDuel.Phase.OFF:
		_duel_timer -= delta
		if _duel_dirty or _duel_timer <= 0.0:
			_send_duel_state()

	_check_humans_resolved()


func _all_loaded() -> bool:
	for peer: int in _peer_of_rid.values():
		if not _loaded.has(peer):
			return false
	return true


func _pose_list() -> Array:
	var out: Array = []
	for rid in racers.size():
		var b := racers[rid]
		if not is_instance_valid(b):
			continue
		var flags := (1 if b.grounded() else 0) | (2 if b.gravity.is_transitioning else 0)
		out.append([rid, b.global_position, b.global_basis.get_rotation_quaternion(), b.velocity,
			dir_index(b.gravity.gravity_dir), flags])
	return out


func _spider_list() -> Array:
	var out: Array = []
	for s in _spiders:
		out.append([s.global_position, s.global_basis.get_rotation_quaternion()])
	return out


## Nobody should wait on bots once every human is done. Same grace as offline.
func _check_humans_resolved() -> void:
	if mc.phase != MatchController.Phase.RACING:
		return
	if _duel != null and _duel.claims_end():
		# From the first qualifier on, the duel's own time limits guarantee the ending; the
		# human grace would otherwise hand Qualified 1st the title before anyone could follow.
		_humans_resolved_at = -1.0
		if _peer_of_rid.is_empty():
			mc.force_end()
		return
	var connected_humans := 0
	var unresolved_humans := 0
	for rid: int in _peer_of_rid.keys():
		connected_humans += 1
		var r: Dictionary = mc.racers[rid]
		if not r["finished"] and not r["eliminated"]:
			unresolved_humans += 1
	if connected_humans == 0:
		mc.force_end()
		return
	if unresolved_humans > 0:
		_humans_resolved_at = -1.0
		return
	if _humans_resolved_at < 0.0:
		_humans_resolved_at = mc.elapsed
	elif mc.elapsed - _humans_resolved_at >= AppConfig.LOCAL_RESOLVED_GRACE:
		mc.force_end()


func _server_send_results(results: Array) -> void:
	if _results_sent:
		return
	_results_sent = true
	var clean: Array = []
	for entry: Dictionary in results:
		var d := entry.duplicate()
		d.erase("body")
		clean.append(d)
	var stats_out := {}
	var stats: Dictionary = world.get("stats")
	for racer_name: String in stats:
		var s: Dictionary = stats[racer_name].duplicate()
		s["colour"] = (s["colour"] as Color).to_html(false)
		stats_out[racer_name] = s
	_broadcast("s_results", [clean, stats_out, mc.elapsed])
	NetManager.server_match_finished(room_code)


func _rid_for(peer: int) -> int:
	return int(_rid_of_peer.get(peer, -1))


## Human puppets only: a racer a bot has taken over no longer listens to its old client.
func _human_body(peer: int) -> PlayerController:
	var rid := _rid_for(peer)
	if rid < 0 or rid >= racers.size():
		return null
	var b := racers[rid]
	return b if is_instance_valid(b) and b.net_puppet else null


func server_on_loaded(peer: int, graph_hash: int) -> void:
	var rid := _rid_for(peer)
	if rid < 0:
		return
	var graph: CaveGraph = world.get("graph")
	if graph_hash != graph.graph_hash():
		NetManager.server_send(peer, "s_notice", ["Your cave does not match the server's. Update your game.", true])
		server_on_disconnect(peer)
		return
	_loaded[peer] = true


## The client's gravity (`_grav`) is only ever a prediction; the server's frame stands.
func server_on_state(peer: int, pos: Vector3, rot: Quaternion, vel: Vector3, _grav: int, flags: int) -> void:
	var b := _human_body(peer)
	if b == null:
		return
	var rid := _rid_for(peer)
	if not pos.is_finite() or not vel.is_finite() or not rot.is_finite() or rot.length_squared() < 0.5:
		return
	var racing := mc.phase == MatchController.Phase.RACING
	var dt := maxf(_server_time - float(_last_pose_time.get(rid, _server_time - 1.0 / SEND_RATE)), 1.0 / 60.0)
	var allowed := (MAX_PLAUSIBLE_SPEED * dt + POSE_SLACK) if racing else POSE_SLACK
	var in_grace := _server_time < float(_grace_until.get(rid, -1.0))
	var jump := b.net_target_position.distance_to(pos)
	if pos.length() > AppConfig.WORLD_BOUNDS + 30.0 or (jump > allowed and not in_grace):
		_correct(peer, rid, b)
		return
	b.net_target_position = pos
	b.net_target_rotation = rot.normalized()
	b.velocity = vel
	b.net_on_floor = (flags & 1) != 0
	_last_pose_time[rid] = _server_time


func _correct(peer: int, rid: int, b: PlayerController) -> void:
	if _server_time - float(_last_correction.get(rid, -INF)) < CORRECTION_COOLDOWN:
		return
	_last_correction[rid] = _server_time
	NetManager.server_send(peer, "s_correct",
		[b.net_target_position, b.net_target_rotation, dir_index(b.gravity.gravity_dir)])


func server_on_shift(peer: int, idx: int) -> void:
	var b := _human_body(peer)
	if b == null or idx < 0 or idx > 5:
		return
	var reason := ""
	if mc.phase != MatchController.Phase.RACING or not b.input_enabled or b.health.is_eliminated:
		reason = "not_racing"
	elif b.gravity.charges <= 0:
		reason = "no_charges"
	elif dir_vector(idx).is_equal_approx(b.gravity.gravity_dir):
		reason = "same_direction"
	elif not b.gravity.request_direction(dir_vector(idx)):
		reason = "transitioning"
	if reason != "":
		NetManager.server_send(peer, "s_shift_denied",
			[reason, b.gravity.charges, dir_index(b.gravity.gravity_dir)])


func server_on_interact(peer: int, box_index: int) -> void:
	var b := _human_body(peer)
	var box: MysteryBox = _boxes.get(box_index, null)
	if b == null or box == null:
		return
	if box.is_open:
		NetManager.server_send(peer, "s_notice", ["Someone got to that box first.", false])
		return
	if not b.input_enabled or b.health.is_eliminated:
		return
	if b.global_position.distance_to(box.global_position) > AppConfig.INTERACT_RANGE + INTERACT_SLACK:
		return
	box.interact(b)


## A client fell out of the world and has already recovered itself. It can only ever hurt
## its own racer by reporting this, so there is nothing to exploit.
func server_on_fell(peer: int, unrecoverable: bool) -> void:
	var b := _human_body(peer)
	if b == null:
		return
	var rid := _rid_for(peer)
	_grace_until[rid] = _server_time + 1.5
	if unrecoverable:
		b.health.eliminate()
	else:
		b.health.apply_damage(AppConfig.DAMAGE_VACUUM_FALL, "out_of_bounds")


func server_on_emote(peer: int, k: int) -> void:
	var rid := _rid_for(peer)
	if rid < 0 or k < 0 or k > 2:
		return
	for other_peer: int in _peer_of_rid.values():
		if other_peer != peer:
			NetManager.server_send(other_peer, "s_emote", [rid, k])


func server_on_test_teleport(peer: int, pos: Vector3) -> void:
	var b := _human_body(peer)
	if b == null:
		return
	var rid := _rid_for(peer)
	_grace_until[rid] = _server_time + 1.0
	b.net_target_position = pos
	b.global_position = pos


## A human left mid-race. In Mixed Race a fresh bot takes their racer over -- it knows
## nothing of the cave, exactly as fair as any other bot. Otherwise they are marked
## disconnected and the race carries on.
func server_on_disconnect(peer: int) -> void:
	var rid := _rid_for(peer)
	if rid < 0:
		return
	_rid_of_peer.erase(peer)
	_peer_of_rid.erase(rid)
	_loaded.erase(peer)
	var b := racers[rid]
	if not is_instance_valid(b):
		return
	var entry: Dictionary = mc.racers[rid]
	var room := _room()
	var resolved := bool(entry["finished"]) or bool(entry["eliminated"])
	if room != null and room.replace_disconnected_with_bot and not resolved \
			and mc.phase != MatchController.Phase.ENDED:
		_replace_with_bot(rid, b)
	else:
		mc.mark_disconnected(b)


func _room() -> LobbyState:
	return NetManager._rooms.get(room_code, null)


func _replace_with_bot(rid: int, b: PlayerController) -> void:
	var old_name := b.display_name
	var new_name := "%s (bot)" % old_name.left(10)
	b.net_puppet = false
	b.gravity.net_puppet = false
	b.velocity = Vector3.ZERO
	b.gravity.net_force_state(b.gravity.gravity_dir, b.gravity.charges)
	var controller := BotController.new()
	controller.name = "BotController"
	b.add_child(controller)
	controller.setup(world.get("graph"), new_name, b.racer_colour, rid + 1, int(world.get("bot_skill")))
	mc.net_rename(rid, new_name, true)
	world.call("rename_stats", old_name, new_name, true)
	(world.get("bots") as Array).append(b)
	_broadcast("s_replaced", [rid, new_name])
	print("[server] room %s: %s dropped, a bot took over" % [room_code, old_name])


# ======================================================================================
# Client
# ======================================================================================

func _setup_client(config: Dictionary) -> void:
	local_rid = int(config.get("local_rid", -1))
	NetManager.client_match = self
	for s in _spiders:
		s.set_physics_process(false)
		_spider_targets.append([s.global_position, s.global_basis.get_rotation_quaternion()])

	var me := _local()
	if me != null:
		me.gravity.shift_started.connect(func(d: Vector3) -> void:
			NetManager.send_to_server("c_shift", [dir_index(d)]))
		me.fell_out_of_world.connect(func(unrecoverable: bool) -> void:
			NetManager.send_to_server("c_fell", [unrecoverable]))
	for box: MysteryBox in _boxes.values():
		box.open_requested.connect(func(b: MysteryBox, _racer: PlayerController) -> void:
			NetManager.send_to_server("c_interact", [b.box_index]))

	var graph: CaveGraph = world.get("graph")
	var expected := int(config.get("graph_hash", -1))
	if graph.graph_hash() != expected:
		push_error("Cave mismatch: local graph %d, server %d" % [graph.graph_hash(), expected])
		NetManager.notice.emit("Your cave does not match the server's. Update your game.", true)
	NetManager.send_to_server("c_loaded", [graph.graph_hash()])


func _local() -> PlayerController:
	if local_rid < 0 or local_rid >= racers.size():
		return null
	return racers[local_rid]


func _exit_tree() -> void:
	if NetManager.client_match == self:
		NetManager.client_match = null


func _client_process(delta: float) -> void:
	var t := 1.0 - exp(-SPIDER_SMOOTHING * delta)
	for i in mini(_spiders.size(), _spider_targets.size()):
		var s := _spiders[i]
		s.global_position = s.global_position.lerp(_spider_targets[i][0], t)
		s.global_basis = Basis(s.global_basis.get_rotation_quaternion().slerp(_spider_targets[i][1], t))

	if _server_lost or mc.phase == MatchController.Phase.ENDED:
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = 1.0 / SEND_RATE
	var me := _local()
	if me == null:
		return
	var flags := (1 if me.is_on_floor() else 0) | (2 if me.gravity.is_transitioning else 0)
	NetManager.send_to_server("c_state", [me.global_position, me.global_basis.get_rotation_quaternion(),
		me.velocity, dir_index(me.gravity.gravity_dir), flags])


func send_emote(k: int) -> void:
	if role == "client":
		NetManager.send_to_server("c_emote", [k])


func leave() -> void:
	NetManager.leave_room()
	GameState.net_role = ""


func client_on_countdown(value: int) -> void:
	mc.net_countdown(value)


func client_on_go(elapsed: float) -> void:
	mc.net_go(elapsed)


func client_on_snapshot(elapsed: float, server_time: float, poses: Array, spiders: Array) -> void:
	mc.net_sync_clock(elapsed)
	for p in _pistons:
		p.net_sync_time(server_time)
	for pose: Array in poses:
		var rid := int(pose[0])
		if rid == local_rid or rid < 0 or rid >= racers.size():
			continue
		var b := racers[rid]
		if not is_instance_valid(b) or not b.net_puppet:
			continue
		b.net_target_position = pose[1]
		b.net_target_rotation = pose[2]
		b.velocity = pose[3]
		b.gravity.net_set_gravity(dir_vector(int(pose[4])))
		b.net_on_floor = (int(pose[5]) & 1) != 0
	for i in mini(spiders.size(), _spider_targets.size()):
		_spider_targets[i] = spiders[i]


func client_on_racer_state(rid: int, hearts: float, charges: int, flags: int, grace: float = -1.0) -> void:
	if rid < 0 or rid >= racers.size():
		return
	var b := racers[rid]
	b.gravity.net_set_charges(charges)
	b.health.net_set_grace(grace)
	b.health.net_apply(hearts, (flags & 1) != 0, (flags & 2) != 0, (flags & 4) != 0)


## Prompt 3: this client asked to trade a heart. The server validates and applies it, then the
## usual racer state carries the new hearts, Moves and deadline back.
func server_on_exchange(peer: int) -> void:
	var b := _human_body(peer)
	if b == null:
		return
	var rid := _rid_for(peer)
	if _server_time - float(_last_exchange.get(rid, -INF)) < AppConfig.HEART_EXCHANGE_DEBOUNCE:
		return
	_last_exchange[rid] = _server_time
	var reason: String = world.call("request_heart_exchange", b)
	NetManager.server_send(peer, "s_exchange", [reason])
	_dirty[rid] = true


func send_exchange() -> void:
	if role == "client":
		NetManager.send_to_server("c_exchange", [])


func client_on_exchange(reason: String) -> void:
	world.call("on_exchange_result", _local(), reason)


func client_on_shift(rid: int, idx: int) -> void:
	if rid == local_rid or rid < 0 or rid >= racers.size():
		return
	var b := racers[rid]
	var dir := dir_vector(idx)
	b.gravity.net_set_gravity(dir)
	# Remote shifts sound and count exactly like local ones.
	b.gravity.shift_started.emit(dir)


func client_on_shift_denied(reason: String, charges: int, grav: int) -> void:
	var me := _local()
	if me == null:
		return
	me.gravity.net_force_state(dir_vector(grav), charges)
	if reason in ["no_charges", "same_direction"]:
		me.gravity.shift_denied.emit(reason)


func client_on_box(box_index: int, rid: int, reward: String, description: String) -> void:
	var box: MysteryBox = _boxes.get(box_index, null)
	if box == null:
		return
	var racer: PlayerController = racers[rid] if rid >= 0 and rid < racers.size() else null
	box.net_apply_open(racer, reward, description)


func client_on_clue(direction: Vector3, vertical: int) -> void:
	var hud: RaceHUD = world.get("hud")
	if hud != null and _local() != null:
		hud.on_clue(_local(), direction, vertical)


## Master Prompt 4: the server decided who took a Sprint Gift. Show it, and if it was this
## client's racer, open its sprint window here, where its movement runs.
func client_on_gift(gift_index: int, rid: int, available: bool) -> void:
	for gift: SprintGift in _gifts:
		if gift.gift_index == gift_index:
			gift.set_available(available)
	if not available and rid == local_rid and _local() != null:
		_local().grant_sprint_gift()


func client_on_crumble(tile_index: int) -> void:
	if tile_index >= 0 and tile_index < _tiles.size() and is_instance_valid(_tiles[tile_index]):
		_tiles[tile_index].start_crumbling()


func client_on_finished(rid: int, place: int, time: float) -> void:
	mc.net_finish(rid, place, time)


func client_on_eliminated(rid: int, time: float, disconnected: bool) -> void:
	if rid >= 0 and rid < racers.size() and not disconnected:
		racers[rid].health.eliminate()
	mc.net_eliminate(rid, time, disconnected)
	if disconnected and rid != local_rid:
		var hud: RaceHUD = world.get("hud")
		if hud != null:
			hud.toast("%s disconnected" % mc.racers[rid]["name"], UiKit.TEXT_DIM)


func client_on_replaced(rid: int, new_name: String) -> void:
	if rid < 0 or rid >= racers.size():
		return
	var b := racers[rid]
	var old_name := b.display_name
	mc.net_rename(rid, new_name, true)
	world.call("rename_stats", old_name, new_name, true)
	b.display_name = new_name
	var label := b.get_node_or_null("NameLabel") as Label3D
	if label != null:
		label.text = new_name
	var hud: RaceHUD = world.get("hud")
	if hud != null:
		hud.toast("%s disconnected -- a bot took over" % old_name, UiKit.TEXT_DIM)


func client_on_correct(pos: Vector3, rot: Quaternion, grav: int) -> void:
	var me := _local()
	if me == null:
		return
	me.global_position = pos
	me.global_basis = Basis(rot)
	me.velocity = Vector3.ZERO
	if not dir_vector(grav).is_equal_approx(me.gravity.gravity_dir):
		me.gravity.net_force_state(dir_vector(grav), me.gravity.charges)


func client_on_emote(rid: int, k: int) -> void:
	if rid < 0 or rid >= racers.size() or k < 0 or k > 2:
		return
	var text: String = ["hey!", "GG", "catch me!"][k]
	racers[rid].rig.emote(text)
	var hud: RaceHUD = world.get("hud")
	if hud != null:
		hud.toast("%s: %s" % [racers[rid].display_name, text], racers[rid].racer_colour, 1.5)


func client_on_results(results: Array, stats: Dictionary, elapsed: float) -> void:
	var local_stats: Dictionary = world.get("stats")
	local_stats.clear()
	for racer_name: String in stats:
		var s: Dictionary = stats[racer_name]
		s["colour"] = Color.html(String(s.get("colour", "ffffff")))
		local_stats[racer_name] = s
	mc.net_end(results, elapsed)


func client_on_duel_state(state: Dictionary) -> void:
	var duel: FreedomDuel = world.get("duel")
	if duel == null:
		return
	var was := duel.phase
	duel.net_apply_state(state)
	if was < FreedomDuel.Phase.INTRO and duel.phase >= FreedomDuel.Phase.INTRO:
		# The cave is over for everyone who is not fighting.
		var me := _local()
		if me != null and not duel.is_finalist(me):
			me.input_enabled = false


func client_on_duel_event(kind: String, args: Array) -> void:
	var duel: FreedomDuel = world.get("duel")
	if duel != null:
		duel.net_event(kind, args)


func send_duel_fire(kind: String, origin: Vector3, dir: Vector3) -> void:
	if role == "client":
		NetManager.send_to_server("c_duel_fire", [kind, origin, dir])


func client_on_server_lost() -> void:
	if _server_lost:
		return
	_server_lost = true
	GameState.net_role = ""
	var hud: RaceHUD = world.get("hud")
	if hud != null:
		hud.set_banner("")
		hud.show_centre("CONNECTION LOST", 4.0, UiKit.DANGER)
		hud.toast("The server went away. Offline Bot Race still works from the menu.", UiKit.TEXT, 4.0)
	await get_tree().create_timer(3.5).timeout
	if is_inside_tree():
		SceneRouter.go_to(SceneRouter.MAIN_MENU)
