class_name BattleMode
extends Node
## Master Prompt 4: Battle Timer Mode. Everyone in one cave, free-for-all, for a fixed time;
## a kill scores a point and the victim comes back a few seconds later somewhere far away.
## Highest score when the clock runs out wins.
##
## This is NOT a race and has nothing to do with the Freedom Duel: there is no exit to reach,
## nobody qualifies, and no Champion is crowned. It reuses what already exists instead of a
## second system:
##   - the arena lobby and join-by-code flow (ruleset "battle")
##   - MatchController's countdown and the Rush cave deadline as the match clock
##   - Combat.hitscan and the Pulse Blaster numbers from the Freedom Duel
##   - PlayerHealth.duel_mode: zero hearts is a signal, not a cave elimination
## The difference is the branch taken at zero hearts: respawn, not spectate.
##
## Offline (test harnesses) and on a server this is the authority. On a client it mirrors.
##
## Defaults (see docs/CORE_MECHANICS.md):
##   - a death with no attacker (fire, spider, a fall) scores nothing for anyone, +1 death
##   - respawn after 3 s, 2 s of spawn protection
##   - ranking: score, then fewer deaths, then who reached that score first, then racer id;
##     a draw only when the top two tie on score, deaths and time reached
##   - spawn points 3+ hops apart; a respawn picks the point farthest from every living
##     racer, never within 16 units of whoever made the kill

signal killed(killer: PlayerController, victim: PlayerController)
signal respawned(body: PlayerController, position: Vector3)
signal shot(shooter: PlayerController, from: Vector3, to: Vector3, hit: PlayerController)
signal scores_changed()
signal battle_over(ranking: Array, draw: bool)

const SPAWN_POINTS := 12
const SPAWN_MIN_HOPS := 3
const KILLER_CLEARANCE := 16.0

var net_client: bool = false
var mc: MatchController
var world: Node3D
var graph: CaveGraph
var spawn_points: Array[Vector3] = []
## Body -> {score, deaths, dead, respawn_left, protect_left, pulse_cd, reached_at, pending, killer}
var fighters: Dictionary = {}
var over: bool = false


func setup(p_world: Node3D, p_mc: MatchController, p_graph: CaveGraph) -> void:
	world = p_world
	mc = p_mc
	graph = p_graph
	add_to_group("battle_mode")
	spawn_points = pick_spawn_points(graph, SPAWN_POINTS)
	for r: Dictionary in mc.racers:
		var body := r["body"] as PlayerController
		fighters[body] = {"score": 0, "deaths": 0, "dead": false, "respawn_left": 0.0,
			"protect_left": 0.0, "pulse_cd": 0.0, "reached_at": 0.0, "pending": null, "killer": null}
		body.health.duel_mode = true
		body.health.duel_down.connect(_on_down.bind(body))


## Spread-out spawn points: farthest-point sampling over the cave graph from the spawn cell,
## skipping holes and hazards. Deterministic from the graph alone, so every machine agrees.
static func pick_spawn_points(g: CaveGraph, count: int) -> Array[Vector3]:
	var hazard := {}
	for h: Dictionary in g.hazards:
		hazard[h["cell"]] = true
	for f: Dictionary in g.features:
		if f["kind"] in ["piston", "spider", "crumble"]:
			hazard[f["cell"]] = true
	var cells: Array[Vector3i] = []
	for c: Vector3i in g.sorted_cells():
		if not hazard.has(c) and not g.is_linked(c, CaveGraph.DIR_DOWN):
			cells.append(c)
	var chosen: Array[Vector3i] = [g.spawn_cell]
	var nearest := g.distances_from(g.spawn_cell)
	while chosen.size() < count:
		var best := Vector3i.ZERO
		var best_d := -1
		for c: Vector3i in cells:
			var d := int(nearest.get(c, 0))
			if d > best_d:
				best_d = d
				best = c
		if best_d < SPAWN_MIN_HOPS:
			break
		chosen.append(best)
		var from_new := g.distances_from(best)
		for c: Vector3i in cells:
			nearest[c] = mini(int(nearest.get(c, 999)), int(from_new.get(c, 999)))
	var out: Array[Vector3] = []
	for c: Vector3i in chosen:
		out.append(CaveBuilder.floor_position(c))
	return out


## Match start: racer id i to spawn point i, which the sampling already spread apart.
func place_everyone() -> void:
	for r: Dictionary in mc.racers:
		var body := r["body"] as PlayerController
		var spot := spawn_points[int(r["rid"]) % spawn_points.size()]
		if net_client and body.net_puppet:
			continue
		_put(body, spot)
		body.health.begin_duel(AppConfig.DUEL_HEARTS)


func _put(body: PlayerController, spot: Vector3) -> void:
	body.velocity = Vector3.ZERO
	if body.gravity.gravity_dir != Vector3.DOWN or body.gravity.is_transitioning:
		body.gravity.net_force_state(Vector3.DOWN, body.gravity.charges)
	body.global_position = spot
	body.net_target_position = spot
	body.net_target_rotation = body.global_basis.get_rotation_quaternion()


func is_alive(body: Node3D) -> bool:
	return fighters.has(body) and not fighters[body]["dead"]


func _physics_process(delta: float) -> void:
	if mc == null or mc.phase != MatchController.Phase.RACING or over:
		return
	for body: PlayerController in fighters:
		var st: Dictionary = fighters[body]
		st["pulse_cd"] = maxf(0.0, float(st["pulse_cd"]) - delta)
		if net_client:
			st["respawn_left"] = maxf(0.0, float(st["respawn_left"]) - delta)
			st["protect_left"] = maxf(0.0, float(st["protect_left"]) - delta)
			continue
		if st["dead"]:
			st["respawn_left"] = float(st["respawn_left"]) - delta
			if st["respawn_left"] <= 0.0:
				_respawn(body)
		elif st["protect_left"] > 0.0:
			st["protect_left"] = float(st["protect_left"]) - delta
			if st["protect_left"] <= 0.0:
				body.health.set_damage_enabled(true)


## Pull the trigger. Returns false if this racer may not fire now (dead, cooldown, time up).
func fire(shooter: PlayerController, from: Vector3, dir: Vector3) -> bool:
	if net_client or over or mc.phase != MatchController.Phase.RACING or mc.cave_expired:
		return false
	if not is_alive(shooter):
		return false
	var st: Dictionary = fighters[shooter]
	if st["pulse_cd"] > 0.0:
		return false
	st["pulse_cd"] = AppConfig.PULSE_COOLDOWN
	var cast := Combat.hitscan(shooter, from, dir)
	var hit: PlayerController = null
	if cast["body"] != null and is_alive(cast["body"]):
		hit = cast["body"]
	shot.emit(shooter, from, cast["to"], hit)
	if hit != null:
		var vst: Dictionary = fighters[hit]
		vst["pending"] = shooter
		hit.health.apply_damage(AppConfig.PULSE_DAMAGE, "battle_pulse")
		vst["pending"] = null
	return true


## Zero hearts. From a shot, `pending` names the shooter; from anything else it is null.
func _on_down(body: PlayerController) -> void:
	if net_client or over or not fighters.has(body):
		return
	var st: Dictionary = fighters[body]
	if st["dead"]:
		return
	st["dead"] = true
	st["deaths"] += 1
	st["respawn_left"] = AppConfig.BATTLE_RESPAWN_DELAY
	var killer: PlayerController = st["pending"]
	st["killer"] = killer
	if killer != null and killer != body and fighters.has(killer):
		fighters[killer]["score"] += 1
		fighters[killer]["reached_at"] = mc.elapsed
	_set_down(body, true)
	killed.emit(killer, body)
	scores_changed.emit()


func _set_down(body: PlayerController, down: bool) -> void:
	body.input_enabled = not down
	body.set_solid(not down)
	body.visible = not down
	if down:
		body.move_input = Vector2.ZERO


func _respawn(body: PlayerController) -> void:
	var st: Dictionary = fighters[body]
	var spot := choose_respawn(body, st["killer"])
	st["dead"] = false
	st["killer"] = null
	st["protect_left"] = AppConfig.BATTLE_SPAWN_PROTECTION
	_put(body, spot)
	body.gravity.net_set_charges(AppConfig.MOVE_CHARGES_START)
	body.health.begin_duel(AppConfig.DUEL_HEARTS)
	body.health.set_damage_enabled(false)
	_set_down(body, false)
	respawned.emit(body, spot)
	scores_changed.emit()


## The point farthest from every living racer, never close to the killer when avoidable.
func choose_respawn(body: PlayerController, killer: PlayerController) -> Vector3:
	var best := spawn_points[0]
	var best_score := -INF
	for i in spawn_points.size():
		var p := spawn_points[i]
		if killer != null and is_instance_valid(killer) and p.distance_to(killer.global_position) < KILLER_CLEARANCE:
			continue
		var nearest := INF
		for other: PlayerController in fighters:
			if other == body or not is_alive(other) or not is_instance_valid(other):
				continue
			nearest = minf(nearest, p.distance_to(other.global_position))
		if nearest > best_score:
			best_score = nearest
			best = p
	return best


## Called once by MatchController when the clock runs out, before the results are built.
func on_time_up() -> void:
	if over:
		return
	over = true
	var ranking := build_ranking()
	var draw := is_draw(ranking)
	for i in ranking.size():
		var r: Dictionary = ranking[i]
		var st: Dictionary = fighters.get(r["body"], {})
		r["battle_rank"] = i + 1
		r["battle_score"] = int(st.get("score", 0))
		r["battle_deaths"] = int(st.get("deaths", 0))
		r["battle_winner"] = i == 0 and not draw
		r["battle_draw"] = draw and i < 2
	battle_over.emit(ranking, draw)


## Racer dictionaries, best first: score, fewer deaths, earlier to reach the score, racer id.
func build_ranking() -> Array:
	var out: Array = mc.racers.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: Dictionary = fighters.get(a["body"], {})
		var sb: Dictionary = fighters.get(b["body"], {})
		if int(sa.get("score", 0)) != int(sb.get("score", 0)):
			return int(sa.get("score", 0)) > int(sb.get("score", 0))
		if int(sa.get("deaths", 0)) != int(sb.get("deaths", 0)):
			return int(sa.get("deaths", 0)) < int(sb.get("deaths", 0))
		if not is_equal_approx(float(sa.get("reached_at", 0.0)), float(sb.get("reached_at", 0.0))):
			return float(sa.get("reached_at", 0.0)) < float(sb.get("reached_at", 0.0))
		return int(a["rid"]) < int(b["rid"]))
	return out


func is_draw(ranking: Array) -> bool:
	if ranking.size() < 2:
		return false
	var a: Dictionary = fighters.get(ranking[0]["body"], {})
	var b: Dictionary = fighters.get(ranking[1]["body"], {})
	return int(a.get("score", 0)) == int(b.get("score", 0)) \
		and int(a.get("deaths", 0)) == int(b.get("deaths", 0)) \
		and is_equal_approx(float(a.get("reached_at", 0.0)), float(b.get("reached_at", 0.0)))


# --- Online ----------------------------------------------------------------------------

func _rid(body: Node3D) -> int:
	for r: Dictionary in mc.racers:
		if r["body"] == body:
			return int(r["rid"])
	return -1


func _body_of(rid: int) -> PlayerController:
	if rid < 0 or rid >= mc.racers.size():
		return null
	return mc.racers[rid]["body"] as PlayerController


## Server -> clients: the scoreboard and who is down, a few times a second and on change.
func net_state() -> Array:
	var out := []
	for body: PlayerController in fighters:
		var st: Dictionary = fighters[body]
		out.append([_rid(body), st["score"], st["deaths"], st["dead"], st["respawn_left"], st["protect_left"], st["reached_at"]])
	return out


func net_apply_state(rows: Array) -> void:
	var changed := false
	for row: Array in rows:
		var body := _body_of(int(row[0]))
		if body == null or not fighters.has(body):
			continue
		var st: Dictionary = fighters[body]
		if st["score"] != int(row[1]) or st["deaths"] != int(row[2]):
			changed = true
		st["score"] = int(row[1])
		st["deaths"] = int(row[2])
		st["respawn_left"] = float(row[4])
		st["protect_left"] = float(row[5])
		st["reached_at"] = float(row[6])
		var dead := bool(row[3])
		if dead != bool(st["dead"]):
			st["dead"] = dead
			_set_down(body, dead)
			if body.net_puppet:
				body.input_enabled = false
	if changed:
		scores_changed.emit()


## Server -> clients: a kill, a respawn (with where), a shot.
func net_event(kind: String, args: Array) -> void:
	match kind:
		"kill":
			var victim := _body_of(int(args[1]))
			if victim != null and fighters.has(victim) and not fighters[victim]["dead"]:
				fighters[victim]["dead"] = true
				_set_down(victim, true)
			killed.emit(_body_of(int(args[0])), victim)
		"respawn":
			var body := _body_of(int(args[0]))
			if body == null:
				return
			fighters[body]["dead"] = false
			if not body.net_puppet:
				_put(body, args[1])
				body.health.begin_duel(AppConfig.DUEL_HEARTS)
				body.gravity.net_set_charges(AppConfig.MOVE_CHARGES_START)
			_set_down(body, false)
			if body.net_puppet:
				body.input_enabled = false
			respawned.emit(body, args[1])
		"shot":
			shot.emit(_body_of(int(args[0])), args[1], args[2], _body_of(int(args[3])))
