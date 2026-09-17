class_name FreedomDuel
extends Node
## The Freedom Duel: the first two racers out of the cave fight for Champion.
##
## Owns qualification, the duel's own movement freedom (DOF), health reset, the two weapons,
## the Freedom Core, arena DOF shifts, sudden death and the result. It does not own
## movement or health -- it sets PlayerController.duel_dof and calls PlayerHealth, the same
## way a hazard would. MatchController asks it before ending the race once anyone qualifies.
##
## Offline and on a server this is the authority. On an online client it is a mirror: it
## never decides anything, it applies what the server sends (see net_apply_state()).
##
## Freedom, in control terms:
##   3 DOF  walk the floor plane and jump      (X, Z and Y)
##   2 DOF  walk the floor plane, no jump      (X and Z)
##   1 DOF  walk one axis only, briefly        (X or Z)
## Qualified 1st starts at 3, Qualified 2nd at 2 with a one-hit shield.

signal qualified(body: PlayerController, order: int)
signal phase_changed(phase: Phase)
signal countdown(value: int)
signal shot(shooter: PlayerController, kind: String, from: Vector3, to: Vector3, hit: PlayerController)
signal axis_locked(target: PlayerController, removed: String)
signal axis_restored(target: PlayerController)
signal lock_resisted(target: PlayerController)
signal core_spawned(position: Vector3)
signal core_captured(body: PlayerController, effect: String)
signal dof_shift(shift_name: String)
signal dof_shift_ended()
signal sudden_death_started()
signal duel_ended(champion: PlayerController, runner_up: PlayerController, reason: String)

enum Phase { OFF, WAITING, INTRO, FIGHT, ENDED }

const SHIFTS: Array[String] = ["FULL FREEDOM", "Y AXIS LOCKED", "FREEDOM SURGE"]
const SURGE_SPEED := 1.35
const BOT_EYE := 1.5

var phase: Phase = Phase.OFF
var net_client: bool = false
var mc: MatchController
var world: Node3D
var arena: DuelArena
var finalist_a: PlayerController
var finalist_b: PlayerController
## Body -> fighter state. See _new_state().
var fighters: Dictionary = {}
var duel_time: float = 0.0
var wait_time: float = 0.0
var intro_left: float = 0.0
var sudden_death: bool = false
var shift_name: String = ""
var shift_left: float = 0.0
var core_active: bool = false
var core_index: int = -1
var core_position: Vector3 = Vector3.ZERO
var champion: PlayerController
var runner_up: PlayerController
var end_reason: String = ""

var _shift_timer: float = 0.0
var _shift_count: int = 0
var _core_timer: float = 0.0
var _last_tick: int = -1
var _core_node: Node3D


func setup(p_world: Node3D, p_mc: MatchController) -> void:
	world = p_world
	mc = p_mc
	add_to_group("freedom_duel")
	arena = DuelArena.create(world)


func is_finalist(body: Node3D) -> bool:
	return body != null and (body == finalist_a or body == finalist_b)


func opponent_of(body: Node3D) -> PlayerController:
	if body == finalist_a:
		return finalist_b
	if body == finalist_b:
		return finalist_a
	return null


## True once anyone has qualified. From then on the race ends only through the duel.
func claims_end() -> bool:
	return phase != Phase.OFF


func is_fighting() -> bool:
	return phase == Phase.FIGHT


# --- Qualification --------------------------------------------------------------------

## MatchController: a racer reached the exit.
func on_racer_finished(body: PlayerController) -> void:
	if net_client:
		return
	if phase == Phase.OFF:
		finalist_a = body
		_mark_qualified(body, 1)
		phase = Phase.WAITING
		wait_time = 0.0
		_send_to_waiting(body)
		qualified.emit(body, 1)
		phase_changed.emit(phase)
		on_resolution_changed()
	elif phase == Phase.WAITING and body != finalist_a:
		finalist_b = body
		_mark_qualified(body, 2)
		qualified.emit(body, 2)
		_start_intro()


## MatchController: someone finished, was eliminated or disconnected.
func on_resolution_changed() -> void:
	if net_client:
		return
	match phase:
		Phase.WAITING:
			if not _anyone_can_still_qualify():
				resolve_by_default("no challenger left")
		Phase.INTRO, Phase.FIGHT:
			for body: PlayerController in [finalist_a, finalist_b]:
				var r := _racer(body)
				if r.get("disconnected", false) or not is_instance_valid(body):
					_finish(opponent_of(body), body, "opponent left")
					return
		_:
			pass


## Qualified 1st becomes Champion without a duel. Only when a second finalist cannot come.
func resolve_by_default(reason: String) -> void:
	if phase != Phase.WAITING or net_client:
		return
	_finish(finalist_a, null, reason)


func _anyone_can_still_qualify() -> bool:
	for r: Dictionary in mc.racers:
		if r["body"] == finalist_a:
			continue
		if not r["finished"] and not r["eliminated"]:
			return true
	return false


func _mark_qualified(body: PlayerController, order: int) -> void:
	var r := _racer(body)
	if not r.is_empty():
		r["qualified"] = order


## Qualified 1st waits in the arena: safe from the cave, unable to touch anyone still in it.
func _send_to_waiting(body: PlayerController) -> void:
	_place(body, arena.spawn_a)
	body.input_enabled = true
	body.duel_dof = 3
	body.health.set_damage_enabled(false)


func _place(body: PlayerController, spot: Vector3) -> void:
	body.velocity = Vector3.ZERO
	body.push_velocity = Vector3.ZERO
	if body.gravity.gravity_dir != Vector3.DOWN or body.gravity.is_transitioning:
		body.gravity.net_force_state(Vector3.DOWN, body.gravity.charges)
	body.global_position = spot
	body.global_basis = arena.facing_basis(spot)
	body.head.rotation = Vector3.ZERO
	body.net_target_position = spot
	body.net_target_rotation = body.global_basis.get_rotation_quaternion()


# --- Intro ----------------------------------------------------------------------------

func _start_intro() -> void:
	phase = Phase.INTRO
	intro_left = float(AppConfig.DUEL_COUNTDOWN) + 1.5
	_last_tick = -1
	fighters.clear()
	for body: PlayerController in [finalist_a, finalist_b]:
		fighters[body] = _new_state(3 if body == finalist_a else 2)
		_place(body, arena.spawn_a if body == finalist_a else arena.spawn_b)
		body.input_enabled = false
		body.health.begin_duel(AppConfig.DUEL_HEARTS)
		body.health.set_damage_enabled(false)
		body.duel_dof = fighters[body]["base"]
		if not body.health.duel_down.is_connected(on_duel_down):
			body.health.duel_down.connect(on_duel_down.bind(body))
	# Qualified 2nd's one modest compensation: a single one-hit shield, once.
	finalist_b.health.grant_shield()
	fighters[finalist_b]["shield_granted"] = true
	_freeze_cave()
	phase_changed.emit(phase)


func _new_state(base: int) -> Dictionary:
	return {
		"base": base,
		"lock_left": 0.0,
		"immune_left": 0.0,
		"removed": "",
		"axis": Vector3.ZERO,
		"core_left": 0.0,
		"surge_left": 0.0,
		"pulse_cd": 0.0,
		"lock_cd": 0.0,
		"damage_dealt": 0.0,
		"locks_landed": 0,
		"cores": 0,
		"shots": 0,
		"hits": 0,
		"shield_granted": false,
	}


## Racers still in the cave stop where they are. Their progress (hops left to the exit)
## orders them in the results after anyone who actually finished.
func _freeze_cave() -> void:
	var graph: CaveGraph = world.get("graph")
	var dist := {}
	if graph != null:
		dist = graph.distances_from(graph.finish_cell)
	for r: Dictionary in mc.racers:
		var body := r["body"] as PlayerController
		if is_finalist(body) or r["finished"] or r["eliminated"] or not is_instance_valid(body):
			continue
		body.input_enabled = false
		body.health.set_damage_enabled(false)
		r["stopped_by_duel"] = true
		r["progress"] = int(dist.get(CaveBuilder.world_to_cell(body.global_position), 999))


# --- Tick -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if net_client:
		_client_tick(delta)
		return
	match phase:
		Phase.WAITING:
			wait_time += delta
			if wait_time >= AppConfig.DUEL_QUALIFY_TIMEOUT:
				resolve_by_default("qualification timed out")
		Phase.INTRO:
			_tick_intro(delta)
		Phase.FIGHT:
			_tick_fight(delta)
		_:
			pass


func _tick_intro(delta: float) -> void:
	intro_left -= delta
	var tick := ceili(intro_left)
	if tick != _last_tick and tick <= AppConfig.DUEL_COUNTDOWN:
		_last_tick = tick
		countdown.emit(maxi(tick, 0))
	if intro_left > 0.0:
		return
	phase = Phase.FIGHT
	duel_time = 0.0
	_shift_timer = AppConfig.DOF_SHIFT_FIRST
	_core_timer = AppConfig.CORE_FIRST_SPAWN
	for body: PlayerController in fighters:
		body.input_enabled = true
		body.health.set_damage_enabled(true)
	phase_changed.emit(phase)


func _tick_fight(delta: float) -> void:
	duel_time += delta
	for body: PlayerController in fighters:
		_tick_fighter(body, fighters[body], delta)

	if not sudden_death:
		_shift_timer -= delta
		if shift_name != "":
			shift_left -= delta
			if shift_left <= 0.0:
				shift_name = ""
				_shift_timer = AppConfig.DOF_SHIFT_INTERVAL
				dof_shift_ended.emit()
		elif _shift_timer <= 0.0:
			shift_name = SHIFTS[_shift_count % SHIFTS.size()]
			_shift_count += 1
			shift_left = AppConfig.DOF_SHIFT_DURATION
			dof_shift.emit(shift_name)
		if duel_time >= AppConfig.SUDDEN_DEATH_AT:
			_start_sudden_death()

	_tick_core(delta)
	_apply_dof()

	if duel_time >= AppConfig.DUEL_HARD_LIMIT:
		_finish_on_points()


func _tick_fighter(body: PlayerController, st: Dictionary, delta: float) -> void:
	st["pulse_cd"] = maxf(0.0, st["pulse_cd"] - delta)
	st["lock_cd"] = maxf(0.0, st["lock_cd"] - delta)
	st["core_left"] = maxf(0.0, st["core_left"] - delta)
	st["surge_left"] = maxf(0.0, st["surge_left"] - delta)
	if st["lock_left"] > 0.0:
		st["lock_left"] -= delta
		if st["lock_left"] <= 0.0:
			st["lock_left"] = 0.0
			st["removed"] = ""
			st["immune_left"] = AppConfig.AXIS_LOCK_IMMUNITY
			axis_restored.emit(body)
	else:
		st["immune_left"] = maxf(0.0, st["immune_left"] - delta)


func _start_sudden_death() -> void:
	sudden_death = true
	if shift_name != "":
		shift_name = ""
		dof_shift_ended.emit()
	for body: PlayerController in fighters:
		fighters[body]["base"] = 3
		# Defensive effects end: no shield carries into sudden death.
		body.health.drop_shield()
	sudden_death_started.emit()


# --- Freedom -----------------------------------------------------------------------

## The DOF a fighter has right now, after cores, locks, shifts and sudden death.
func effective_dof(body: PlayerController) -> int:
	if not fighters.has(body):
		return body.duel_dof
	var st: Dictionary = fighters[body]
	var d: int = int(st["base"])
	if st["core_left"] > 0.0:
		d += 1
	if shift_name == "FULL FREEDOM":
		d = maxi(d, 3)
	if st["lock_left"] > 0.0:
		d -= 1
	if shift_name == "Y AXIS LOCKED":
		d = mini(d, 2)
	return clampi(d, 1, 3)


## [X, Y, Z] -- which arena axes this fighter can move along right now.
func axes_of(body: PlayerController) -> Array[bool]:
	var d := shown_dof(body) if fighters.has(body) else body.duel_dof
	if d <= 0:
		return [true, true, true]
	if d >= 3:
		return [true, true, true]
	if d == 2:
		return [true, false, true]
	var axis: Vector3 = fighters[body]["axis"] if fighters.has(body) else body.duel_axis
	return [absf(axis.x) > 0.5, false, absf(axis.z) > 0.5]


func _apply_dof() -> void:
	for body: PlayerController in fighters:
		var st: Dictionary = fighters[body]
		var d := effective_dof(body)
		if d == 1 and st["axis"] == Vector3.ZERO:
			# Keep the arena axis closest to where the fighter is looking: the one that matters.
			var fwd := -body.global_basis.z
			st["axis"] = Vector3.RIGHT if absf(fwd.x) > absf(fwd.z) else Vector3.BACK
		elif d != 1:
			st["axis"] = Vector3.ZERO
		body.duel_dof = d
		body.duel_axis = st["axis"]
		body.duel_speed = SURGE_SPEED if shift_name == "FREEDOM SURGE" or st["surge_left"] > 0.0 else 1.0


# --- Weapons -----------------------------------------------------------------------

## Fire from where the shooter is looking. Returns false if the shot is not allowed now.
## Online, the server calls this with the aim the client sent.
func fire(shooter: PlayerController, kind: String, aim_from: Vector3 = Vector3.INF, aim_dir: Vector3 = Vector3.ZERO) -> bool:
	if net_client or phase != Phase.FIGHT or not fighters.has(shooter):
		return false
	var st: Dictionary = fighters[shooter]
	var key := "pulse_cd" if kind == "pulse" else "lock_cd"
	if kind != "pulse" and kind != "lock":
		return false
	if st[key] > 0.0:
		return false
	st[key] = AppConfig.PULSE_COOLDOWN if kind == "pulse" else AppConfig.AXIS_LOCK_COOLDOWN
	st["shots"] += 1

	var from := aim_from if aim_from != Vector3.INF else shooter.head.global_position
	var dir := aim_dir if aim_dir != Vector3.ZERO else -shooter.head.global_basis.z
	dir = dir.normalized()
	var to := from + dir * AppConfig.PULSE_RANGE
	var hit: PlayerController = null
	var space := shooter.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [shooter.get_rid()])
	var result := space.intersect_ray(query)
	if not result.is_empty():
		to = result["position"]
		if result["collider"] == opponent_of(shooter):
			hit = result["collider"]

	shot.emit(shooter, kind, from, to, hit)
	if hit != null:
		st["hits"] += 1
		_resolve_hit(shooter, hit, kind)
	return true


func _resolve_hit(shooter: PlayerController, target: PlayerController, kind: String) -> void:
	var st: Dictionary = fighters[shooter]
	var tst: Dictionary = fighters[target]
	var damage := AppConfig.PULSE_DAMAGE if kind == "pulse" else AppConfig.AXIS_LOCK_DAMAGE
	if sudden_death:
		damage *= AppConfig.SUDDEN_DEATH_DAMAGE_SCALE
	var before := target.health.hearts
	if target.health.apply_damage(damage, "duel_%s" % kind):
		st["damage_dealt"] += before - target.health.hearts
	if kind != "lock" or phase != Phase.FIGHT:
		return
	if tst["lock_left"] > 0.0 or tst["immune_left"] > 0.0:
		lock_resisted.emit(target)
		return
	var before_dof := effective_dof(target)
	tst["lock_left"] = AppConfig.AXIS_LOCK_DURATION
	st["locks_landed"] += 1
	_apply_dof()
	var removed := "Y"
	if before_dof <= 2:
		removed = "Z" if absf((tst["axis"] as Vector3).x) > 0.5 else "X"
	tst["removed"] = removed
	axis_locked.emit(target, removed)


# --- Freedom Core --------------------------------------------------------------------

func _tick_core(delta: float) -> void:
	if not core_active:
		_core_timer -= delta
		if _core_timer <= 0.0:
			core_index = (core_index + 1) % arena.core_points.size()
			core_position = arena.core_points[core_index]
			core_active = true
			_show_core(true)
			core_spawned.emit(core_position)
		return
	for body: PlayerController in fighters:
		if body.global_position.distance_to(core_position) <= AppConfig.CORE_PICKUP_RADIUS:
			capture_core(body)
			return


func capture_core(body: PlayerController) -> void:
	if not core_active or not fighters.has(body):
		return
	var st: Dictionary = fighters[body]
	core_active = false
	_show_core(false)
	_core_timer = AppConfig.CORE_RESPAWN
	st["cores"] += 1
	var effect := "dof"
	if sudden_death:
		effect = "surge"
		st["surge_left"] = AppConfig.CORE_BOOST_TIME * 0.5
	elif effective_dof(body) >= 3 and st["lock_left"] <= 0.0:
		# Already fully free: no literal "4DOF". A shield instead, or a burst if already shielded.
		if body.health.has_shield:
			effect = "surge"
			st["surge_left"] = AppConfig.CORE_BOOST_TIME * 0.5
		else:
			effect = "shield"
			body.health.grant_shield()
	else:
		st["core_left"] = AppConfig.CORE_BOOST_TIME
	_apply_dof()
	core_captured.emit(body, effect)


func _show_core(active: bool) -> void:
	if _core_node == null:
		_core_node = FreedomCoreVisual.new()
		world.add_child(_core_node)
	_core_node.visible = active
	_core_node.global_position = core_position


# --- Ending --------------------------------------------------------------------------

## A finalist's hearts ran out.
func on_duel_down(body: PlayerController) -> void:
	if net_client or phase != Phase.FIGHT:
		return
	_finish(opponent_of(body), body, "knockout")


func _finish_on_points() -> void:
	var a := finalist_a
	var b := finalist_b
	var winner := a
	if b.health.hearts > a.health.hearts:
		winner = b
	elif is_equal_approx(b.health.hearts, a.health.hearts) \
			and float(fighters[b]["damage_dealt"]) > float(fighters[a]["damage_dealt"]):
		winner = b
	_finish(winner, opponent_of(winner), "time")


func _finish(p_champion: PlayerController, p_runner: PlayerController, reason: String) -> void:
	if phase == Phase.ENDED:
		return
	phase = Phase.ENDED
	champion = p_champion
	runner_up = p_runner
	end_reason = reason
	if _core_node != null:
		_core_node.visible = false
	for body: PlayerController in fighters:
		body.input_enabled = false
		body.health.set_damage_enabled(false)
	var cr := _racer(champion)
	if not cr.is_empty():
		cr["duel_place"] = 1
	var rr := _racer(runner_up)
	if not rr.is_empty():
		rr["duel_place"] = 2
	for body: PlayerController in fighters:
		var r := _racer(body)
		if r.is_empty():
			continue
		var st: Dictionary = fighters[body]
		r["duel_stats"] = {
			"duration": duel_time,
			"damage_dealt": float(st["damage_dealt"]),
			"locks_landed": int(st["locks_landed"]),
			"cores": int(st["cores"]),
			"hearts_left": body.health.hearts,
		}
	phase_changed.emit(phase)
	duel_ended.emit(champion, runner_up, reason)
	mc.end_after_duel()


func _racer(body: Node3D) -> Dictionary:
	if body == null or mc == null:
		return {}
	for r: Dictionary in mc.racers:
		if r["body"] == body:
			return r
	return {}


# --- Online mirror -------------------------------------------------------------------

## Server -> everyone: the whole duel in one small dictionary, sent a few times a second
## and on every change that matters. Positions are not in here; poses already sync.
func net_state() -> Dictionary:
	var fs := []
	for body: PlayerController in [finalist_a, finalist_b]:
		if body == null or not fighters.has(body):
			continue
		var st: Dictionary = fighters[body]
		fs.append([_rid(body), effective_dof(body), st["axis"], st["lock_left"], st["immune_left"],
			st["core_left"], st["pulse_cd"], st["lock_cd"], body.health.hearts, body.health.has_shield,
			st["removed"], st["damage_dealt"], st["locks_landed"], st["cores"]])
	return {
		"phase": phase, "a": _rid(finalist_a), "b": _rid(finalist_b), "t": duel_time,
		"wait": wait_time, "intro": intro_left, "sd": sudden_death, "shift": shift_name,
		"shift_left": shift_left, "core": core_active, "core_i": core_index, "f": fs,
	}


func _rid(body: Node3D) -> int:
	var r := _racer(body)
	return int(r.get("rid", -1))


func _body_of(rid: int) -> PlayerController:
	if mc == null or rid < 0 or rid >= mc.racers.size():
		return null
	return mc.racers[rid]["body"] as PlayerController


## Online client: adopt the server's duel. Signals fire on changes so HUD and audio work
## exactly as offline.
func net_apply_state(s: Dictionary) -> void:
	var new_phase: Phase = int(s.get("phase", 0)) as Phase
	var a := _body_of(int(s.get("a", -1)))
	var b := _body_of(int(s.get("b", -1)))
	if a != null and finalist_a != a:
		finalist_a = a
		_mark_qualified(a, 1)
		if new_phase == Phase.WAITING or phase == Phase.OFF:
			_send_to_waiting_client(a)
		qualified.emit(a, 1)
	if b != null and finalist_b != b:
		finalist_b = b
		_mark_qualified(b, 2)
		qualified.emit(b, 2)
	if new_phase >= Phase.INTRO and phase < Phase.INTRO and finalist_a != null and finalist_b != null:
		fighters.clear()
		for body: PlayerController in [finalist_a, finalist_b]:
			fighters[body] = _new_state(3 if body == finalist_a else 2)
			_place_client(body, arena.spawn_a if body == finalist_a else arena.spawn_b)
			body.health.duel_mode = true
			body.input_enabled = false
		intro_left = float(s.get("intro", 0.0))
		_last_tick = -1
	duel_time = float(s.get("t", 0.0))
	wait_time = float(s.get("wait", 0.0))
	if new_phase == Phase.INTRO:
		intro_left = float(s.get("intro", intro_left))
	var sd := bool(s.get("sd", false))
	if sd and not sudden_death:
		sudden_death = true
		sudden_death_started.emit()
	var sh := String(s.get("shift", ""))
	if sh != shift_name:
		shift_name = sh
		if sh == "":
			dof_shift_ended.emit()
		else:
			dof_shift.emit(sh)
	shift_left = float(s.get("shift_left", 0.0))
	var core := bool(s.get("core", false))
	core_index = int(s.get("core_i", -1))
	if core_index >= 0 and core_index < arena.core_points.size():
		core_position = arena.core_points[core_index]
	if core != core_active:
		core_active = core
		_show_core(core)
		if core:
			core_spawned.emit(core_position)
	for f: Array in s.get("f", []):
		var body := _body_of(int(f[0]))
		if body == null:
			continue
		if not fighters.has(body):
			fighters[body] = _new_state(2)
		var st: Dictionary = fighters[body]
		var was_locked: bool = st["lock_left"] > 0.0
		st["axis"] = f[2]
		st["lock_left"] = float(f[3])
		st["immune_left"] = float(f[4])
		st["core_left"] = float(f[5])
		st["pulse_cd"] = float(f[6])
		st["lock_cd"] = float(f[7])
		st["removed"] = String(f[10])
		st["damage_dealt"] = float(f[11])
		st["locks_landed"] = int(f[12])
		st["cores"] = int(f[13])
		st["net_dof"] = int(f[1])
		body.duel_dof = int(f[1])
		body.duel_axis = f[2]
		body.health.net_apply(float(f[8]), bool(f[9]), false, false)
		if was_locked and st["lock_left"] <= 0.0:
			axis_restored.emit(body)
	if new_phase != phase:
		phase = new_phase
		if phase == Phase.FIGHT:
			for body: PlayerController in fighters:
				body.input_enabled = true
		elif phase == Phase.ENDED:
			for body: PlayerController in fighters:
				body.input_enabled = false
			if _core_node != null:
				_core_node.visible = false
		phase_changed.emit(phase)


## Online client: an event the state packet cannot express as a change (who shot what).
func net_event(kind: String, args: Array) -> void:
	match kind:
		"shot":
			var hit := _body_of(int(args[4]))
			shot.emit(_body_of(int(args[0])), String(args[1]), args[2], args[3], hit)
		"locked":
			axis_locked.emit(_body_of(int(args[0])), String(args[1]))
		"resisted":
			lock_resisted.emit(_body_of(int(args[0])))
		"core":
			core_captured.emit(_body_of(int(args[0])), String(args[1]))
		"end":
			champion = _body_of(int(args[0]))
			runner_up = _body_of(int(args[1]))
			end_reason = String(args[2])
			duel_ended.emit(champion, runner_up, end_reason)


func _send_to_waiting_client(body: PlayerController) -> void:
	# Only the machine that simulates this racer moves it; everyone else sees its pose arrive.
	if body.net_puppet:
		return
	_place(body, arena.spawn_a)
	body.input_enabled = true
	body.duel_dof = 3


func _place_client(body: PlayerController, spot: Vector3) -> void:
	if body.net_puppet:
		return
	_place(body, spot)


func _client_tick(delta: float) -> void:
	if phase == Phase.INTRO:
		intro_left -= delta
		var tick := ceili(intro_left)
		if tick != _last_tick and tick <= AppConfig.DUEL_COUNTDOWN:
			_last_tick = tick
			countdown.emit(maxi(tick, 0))
	elif phase == Phase.FIGHT:
		duel_time += delta
		for body: PlayerController in fighters:
			var st: Dictionary = fighters[body]
			for key: String in ["pulse_cd", "lock_cd", "core_left", "lock_left", "immune_left"]:
				st[key] = maxf(0.0, float(st[key]) - delta)
		if shift_name != "":
			shift_left = maxf(0.0, shift_left - delta)


## On a client, effective_dof() would recompute from partial state; the server's number wins.
func shown_dof(body: PlayerController) -> int:
	if net_client and fighters.has(body):
		return int(fighters[body].get("net_dof", body.duel_dof))
	return effective_dof(body)
