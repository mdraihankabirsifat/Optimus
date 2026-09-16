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

var _countdown_remaining: float = 0.0
var _last_tick: int = -1
var _next_place: int = 1
var _finish_area: Area3D


## Add a racer before calling begin_countdown(). `body` must expose `health`.
func register_racer(body: Node3D, display_name: String, is_bot: bool = false) -> void:
	var entry := {
		"body": body,
		"name": display_name,
		"is_bot": is_bot,
		"finished": false,
		"place": 0,
		"finish_time": 0.0,
		"eliminated": false,
		"elimination_time": 0.0,
	}
	racers.append(entry)
	var health: PlayerHealth = body.get("health")
	if health != null:
		health.eliminated.connect(_on_racer_eliminated.bind(body))


func begin_countdown() -> void:
	_finish_area = get_tree().get_first_node_in_group("finish_area") as Area3D
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
	match phase:
		Phase.COUNTDOWN:
			_advance_countdown(delta)
		Phase.RACING:
			elapsed += delta
			if elapsed >= AppConfig.MATCH_TIME_LIMIT:
				_end_match()
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

	racer_finished.emit(racer["name"], racer["place"], racer["finish_time"])
	_check_for_end()


func _on_racer_eliminated(body: Node3D) -> void:
	var racer := _find_racer(body)
	if racer.is_empty() or racer["finished"] or racer["eliminated"]:
		return

	racer["eliminated"] = true
	racer["elimination_time"] = elapsed
	if "input_enabled" in body:
		body.input_enabled = false

	racer_eliminated.emit(racer["name"], racer["elimination_time"])
	_check_for_end()


func _check_for_end() -> void:
	for racer: Dictionary in racers:
		if not racer["finished"] and not racer["eliminated"]:
			return
	_end_match()


## Ends the race now. Used when the local racer is done and nobody should wait on bots.
func force_end() -> void:
	if phase == Phase.RACING:
		_end_match()


func _end_match() -> void:
	if phase == Phase.ENDED:
		return
	phase = Phase.ENDED
	_set_racers_active(false)
	match_ended.emit(build_results())


## Finishers by place, then eliminated racers latest-first (surviving longer ranks higher),
## then anyone still unresolved when the clock ran out.
func build_results() -> Array:
	var finishers: Array = []
	var eliminated: Array = []
	var unresolved: Array = []

	for racer: Dictionary in racers:
		if racer["finished"]:
			finishers.append(racer)
		elif racer["eliminated"]:
			eliminated.append(racer)
		else:
			unresolved.append(racer)

	finishers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["place"]) < int(b["place"]))
	eliminated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["elimination_time"]) > float(b["elimination_time"]))

	var out: Array = []
	out.append_array(finishers)
	out.append_array(eliminated)
	out.append_array(unresolved)
	return out


func _find_racer(body: Node3D) -> Dictionary:
	for racer: Dictionary in racers:
		if racer["body"] == body:
			return racer
	return {}


static func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := seconds - float(minutes * 60)
	return "%d:%05.2f" % [minutes, secs]
