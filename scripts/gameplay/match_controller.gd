class_name MatchController
extends Node
## Owns match flow: countdown, timer, finish order, elimination order, results.
##
## It observes racers; it does not own their state. Health lives in PlayerHealth and the
## gravity frame lives in GravityController. This file only records what happened and when.
##
## Built for 2-5 racers from the start so bots and remote players slot in without a rewrite,
## even though only one local racer exists today. See docs/ARCHITECTURE.md.

signal countdown_tick(value: int)
signal match_started()
signal racer_finished(racer_name: String, place: int, time: float)
signal racer_eliminated(racer_name: String, time: float)
signal match_ended(results: Array)

enum Phase { PENDING, COUNTDOWN, RACING, ENDED }

var phase: Phase = Phase.PENDING
var elapsed: float = 0.0
var racers: Array[Dictionary] = []

## Online client: the server runs the countdown, detects the finish and records every
## placement. This copy only mirrors what the server reports, and keeps a local clock
## between the server's corrections.
var net_client: bool = false
## Online server rule from the master prompt: once placements have started, the race also
## ends when only one racer is still unresolved.
var end_when_one_left: bool = false
## Prompt 2: once anyone reaches the exit, the race ends through the Freedom Duel instead.
## Null for harnesses that want the old first-to-exit race.
var duel: FreedomDuel
## Prompt 3: the cave phase's deadline in seconds after GO. 0 in Normal: no limit at all.
var cave_time_limit: float = 0.0
## Set once when a Rush cave runs out, whatever happens next.
var cave_expired: bool = false
signal cave_time_up(qualifiers: int)

var _countdown_remaining: float = 0.0
var _last_tick: int = -1
var _next_place: int = 1
var _finish_area: Area3D


## Add a racer before calling begin_countdown(). `body` must expose `health`.
## Registration order is the racer id (`rid`) that online events use.
func register_racer(body: Node3D, display_name: String, is_bot: bool = false) -> void:
	var entry := {
		"rid": racers.size(),
		"body": body,
		"name": display_name,
		"is_bot": is_bot,
		"finished": false,
		"place": 0,
		"finish_time": 0.0,
		"eliminated": false,
		"elimination_time": 0.0,
		"disconnected": false,
		## 1 or 2 for the two racers who qualified for the Freedom Duel, else 0.
		"qualified": 0,
		## 1 Champion, 2 duel runner-up, 0 for everyone else.
		"duel_place": 0,
		"duel_stats": {},
		## Racers still in the cave when the duel began: hops they had left to the exit.
		"stopped_by_duel": false,
		"progress": 999,
	}
	racers.append(entry)
	var health: PlayerHealth = body.get("health")
	if health != null:
		health.eliminated.connect(_on_racer_eliminated.bind(body))


func begin_countdown() -> void:
	if net_client:
		# Frozen until the server says GO; nothing here may start the race on its own.
		phase = Phase.PENDING
		_set_racers_active(false)
		return
	_finish_area = WorldScope.first(self, "finish_area") as Area3D
	if _finish_area != null:
		_finish_area.body_entered.connect(_on_finish_body_entered)
	else:
		push_warning("MatchController found no finish area; the race cannot be won.")

	_countdown_remaining = float(AppConfig.MATCH_COUNTDOWN_SECONDS)
	_last_tick = -1
	phase = Phase.COUNTDOWN
	# A racer must never be able to move or take damage before GO.
	_set_racers_active(false)


func _process(delta: float) -> void:
	if net_client:
		if phase == Phase.RACING:
			elapsed += delta
		return
	match phase:
		Phase.COUNTDOWN:
			_advance_countdown(delta)
		Phase.RACING:
			elapsed += delta
			if cave_time_limit > 0.0 and not cave_expired and elapsed >= cave_time_limit:
				_expire_cave()
		_:
			pass


func _advance_countdown(delta: float) -> void:
	_countdown_remaining -= delta
	var tick := int(ceil(_countdown_remaining))
	if tick != _last_tick:
		_last_tick = tick
		countdown_tick.emit(maxi(tick, 0))

	if _countdown_remaining <= 0.0:
		phase = Phase.RACING
		elapsed = 0.0
		_set_racers_active(true)
		match_started.emit()


func _set_racers_active(active: bool) -> void:
	for racer: Dictionary in racers:
		var body: Node3D = racer["body"]
		if not is_instance_valid(body):
			continue
		if "input_enabled" in body:
			body.input_enabled = active
		var health: PlayerHealth = body.get("health")
		if health != null:
			health.set_damage_enabled(active)


func _on_finish_body_entered(body: Node3D) -> void:
	if phase != Phase.RACING:
		return
	# Rush: an arrival at or before the deadline counts, a later one does not.
	if cave_expired or (cave_time_limit > 0.0 and elapsed > cave_time_limit):
		return
	var racer := _find_racer(body)
	if racer.is_empty() or racer["finished"] or racer["eliminated"]:
		return

	racer["finished"] = true
	racer["place"] = _next_place
	racer["finish_time"] = elapsed
	_next_place += 1

	# A finished racer stops competing but stays visible to the others.
	if "input_enabled" in body:
		body.input_enabled = false
	_unsolid(body)

	racer_finished.emit(racer["name"], racer["place"], racer["finish_time"])
	if duel != null:
		duel.on_racer_finished(body as PlayerController)
	_check_for_end()


func _on_racer_eliminated(body: Node3D) -> void:
	if net_client:
		return
	var racer := _find_racer(body)
	if racer.is_empty() or racer["finished"] or racer["eliminated"]:
		return

	racer["eliminated"] = true
	racer["elimination_time"] = elapsed
	if "input_enabled" in body:
		body.input_enabled = false
	_unsolid(body)

	racer_eliminated.emit(racer["name"], racer["elimination_time"])
	_check_for_end()


func _check_for_end() -> void:
	if duel != null and duel.claims_end():
		duel.on_resolution_changed()
		return
	var unresolved := 0
	var finished := 0
	for racer: Dictionary in racers:
		if racer["finished"]:
			finished += 1
		elif not racer["eliminated"]:
			unresolved += 1
	if unresolved == 0:
		_end_match()
	elif end_when_one_left and unresolved <= 1 and finished >= 1 and racers.size() >= 2:
		_end_match()


## Rush expiry, exactly once. It ends the cave phase only: a duel already started keeps its own
## timing, and nobody is crowned from distance to a hidden exit.
##   two qualifiers  -> the duel is already running; unfinished racers were stopped as DNF
##   one qualifier   -> Qualified 1st is Champion by default ("Rush time up")
##   no qualifiers   -> the race ends: time up, no qualifiers, no Champion
func _expire_cave() -> void:
	cave_expired = true
	var qualifiers := 0
	for racer: Dictionary in racers:
		if int(racer.get("qualified", 0)) > 0:
			qualifiers += 1
	cave_time_up.emit(qualifiers)
	for racer: Dictionary in racers:
		if racer["finished"] or racer["eliminated"]:
			continue
		var body: Node3D = racer["body"]
		if duel != null and duel.is_finalist(body):
			continue
		racer["stopped_by_time"] = true
		if is_instance_valid(body) and "input_enabled" in body:
			body.input_enabled = false
	if duel == null or duel.phase == FreedomDuel.Phase.OFF:
		_end_match()
	elif duel.phase == FreedomDuel.Phase.WAITING:
		duel.resolve_by_default("Rush time up")


## Online server: a human dropped and was not replaced by a bot. They are out of the race,
## recorded as disconnected rather than as losing to a hazard.
func mark_disconnected(body: Node3D) -> void:
	var racer := _find_racer(body)
	if racer.is_empty():
		return
	racer["disconnected"] = true
	if racer["finished"] or racer["eliminated"]:
		# A finalist has already finished the cave; leaving still decides the duel.
		if duel != null and duel.claims_end():
			duel.on_resolution_changed()
		return
	racer["eliminated"] = true
	racer["elimination_time"] = elapsed
	if "input_enabled" in body:
		body.input_enabled = false
	_unsolid(body)
	racer_eliminated.emit(racer["name"], racer["elimination_time"])
	_check_for_end()


# --- Online client mirror -------------------------------------------------------------

func net_countdown(value: int) -> void:
	if phase == Phase.RACING or phase == Phase.ENDED:
		return
	phase = Phase.COUNTDOWN
	_set_racers_active(false)
	countdown_tick.emit(value)


func net_go(server_elapsed: float = 0.0) -> void:
	if phase == Phase.RACING or phase == Phase.ENDED:
		return
	phase = Phase.RACING
	elapsed = server_elapsed
	_set_racers_active(true)
	match_started.emit()


func net_sync_clock(server_elapsed: float) -> void:
	if phase == Phase.RACING and absf(server_elapsed - elapsed) > 0.25:
		elapsed = server_elapsed


func net_finish(rid: int, place: int, time: float) -> void:
	if rid < 0 or rid >= racers.size():
		return
	var racer: Dictionary = racers[rid]
	if racer["finished"]:
		return
	racer["finished"] = true
	racer["place"] = place
	racer["finish_time"] = time
	_next_place = maxi(_next_place, place + 1)
	var body: Node3D = racer["body"]
	if is_instance_valid(body) and "input_enabled" in body:
		body.input_enabled = false
	_unsolid(body)
	racer_finished.emit(racer["name"], place, time)


func net_eliminate(rid: int, time: float, disconnected: bool = false) -> void:
	if rid < 0 or rid >= racers.size():
		return
	var racer: Dictionary = racers[rid]
	racer["disconnected"] = racer["disconnected"] or disconnected
	if racer["eliminated"] or racer["finished"]:
		return
	racer["eliminated"] = true
	racer["elimination_time"] = time
	var body: Node3D = racer["body"]
	if is_instance_valid(body) and "input_enabled" in body:
		body.input_enabled = false
	_unsolid(body)
	racer_eliminated.emit(racer["name"], time)


func net_rename(rid: int, new_name: String, is_bot: bool) -> void:
	if rid < 0 or rid >= racers.size():
		return
	racers[rid]["name"] = new_name
	racers[rid]["is_bot"] = is_bot


func net_end(results: Array, server_elapsed: float) -> void:
	if phase == Phase.ENDED:
		return
	elapsed = server_elapsed
	phase = Phase.ENDED
	_set_racers_active(false)
	match_ended.emit(results)


## Ends the race now. Used when the local racer is done and nobody should wait on bots.
## Once someone has qualified, "now" means Qualified 1st takes it by default -- unless the
## duel is already being fought, which is never cut short.
func force_end() -> void:
	if phase != Phase.RACING:
		return
	if duel != null and duel.claims_end():
		if duel.phase == FreedomDuel.Phase.WAITING:
			duel.resolve_by_default("race ended early")
		return
	_end_match()


## FreedomDuel: the Champion is decided.
func end_after_duel() -> void:
	_end_match()


func _end_match() -> void:
	if phase == Phase.ENDED:
		return
	phase = Phase.ENDED
	_set_racers_active(false)
	match_ended.emit(build_results())


## Prompt 2: the Champion, then the duel runner-up, then finishers by place, then eliminated
## racers latest-first (surviving longer ranks higher), then anyone still unresolved --
## closest to the exit first when the duel stopped them.
func build_results() -> Array:
	var duelists: Array = []
	var finishers: Array = []
	var eliminated: Array = []
	var unresolved: Array = []

	for racer: Dictionary in racers:
		if int(racer.get("duel_place", 0)) > 0:
			duelists.append(racer)
		elif racer["finished"]:
			finishers.append(racer)
		elif racer["eliminated"]:
			eliminated.append(racer)
		else:
			unresolved.append(racer)

	# Every tie breaks on the racer id, so two machines always print the same order.
	finishers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["place"]) != int(b["place"]):
			return int(a["place"]) < int(b["place"])
		return int(a["rid"]) < int(b["rid"]))
	eliminated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["elimination_time"]), float(b["elimination_time"])):
			return float(a["elimination_time"]) > float(b["elimination_time"])
		return int(a["rid"]) < int(b["rid"]))
	unresolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("progress", 999)) != int(b.get("progress", 999)):
			return int(a.get("progress", 999)) < int(b.get("progress", 999))
		return int(a["rid"]) < int(b["rid"]))
	duelists.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["duel_place"]) < int(b["duel_place"]))

	var out: Array = []
	out.append_array(duelists)
	out.append_array(finishers)
	out.append_array(eliminated)
	out.append_array(unresolved)
	return out


## Finished and eliminated racers stop blocking the living. FreedomDuel makes finalists
## solid again in the arena.
func _unsolid(body: Node3D) -> void:
	if is_instance_valid(body) and body.has_method("set_solid"):
		body.call("set_solid", false)


func _find_racer(body: Node3D) -> Dictionary:
	for racer: Dictionary in racers:
		if racer["body"] == body:
			return racer
	return {}


static func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := seconds - float(minutes * 60)
	return "%d:%05.2f" % [minutes, secs]
