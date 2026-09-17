class_name PlayerHealth
extends Node
## Hearts, damage cooldown, invulnerability and elimination.
##
## This file decides how much health a racer has. It does not decide what deals damage —
## hazards call apply_damage(). See docs/ARCHITECTURE.md.

signal damaged(amount: float, source: String)
signal hearts_changed(hearts: float)
signal eliminated()
signal shield_changed(active: bool)
signal shield_absorbed()
signal second_chance_changed(active: bool)
signal second_chance_used()
## Freedom Duel: hearts ran out. Never eliminated() -- losing the duel is not a cave death.
signal duel_down()
## Prompt 3: a heart was traded for a Move. `last_heart` when it started the grace deadline.
signal heart_exchanged(last_heart: bool)
signal last_heart_started(seconds: float)

var hearts: float = 5.0
var is_eliminated: bool = false
var is_invulnerable: bool = false
## A mystery-box shield soaks the next hit entirely. Never stacks.
var has_shield: bool = false
## HEALTH-005: survive one hit that would have eliminated you, on half a heart.
var has_second_chance: bool = false

## Per-source cooldowns. Prevents a single hazard draining hearts every physics frame.
var _source_cooldowns: Dictionary = {}
var _invuln_timer: float = 0.0
## Blocks all damage during countdown, spawn and loading.
var _damage_enabled: bool = true
## Online client: hearts belong to the server. Local hazards still animate and still
## overlap this racer, but only the server's copy of them can take a heart.
var net_client: bool = false
## Freedom Duel rules: short invulnerability, no Second Chance, zero hearts is duel_down.
var duel_mode: bool = false
## Prompt 3, last-heart grace: seconds left before elimination after trading the final heart.
## -1 when not in grace. Set once; nothing extends or resets it. Qualifying clears it.
var grace_left: float = -1.0


func _ready() -> void:
	hearts = AppConfig.HEARTS_MAX
	hearts_changed.emit(hearts)


func _process(delta: float) -> void:
	if grace_left >= 0.0 and not is_eliminated:
		grace_left -= delta
		if grace_left <= 0.0:
			grace_left = 0.0
			# A client only shows the countdown; the server's copy eliminates.
			if not net_client:
				grace_left = -1.0
				eliminate()
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
		if _invuln_timer <= 0.0:
			is_invulnerable = false

	for source: String in _source_cooldowns.keys():
		_source_cooldowns[source] -= delta
		if _source_cooldowns[source] <= 0.0:
			_source_cooldowns.erase(source)


## Enable or disable all damage. Called by MatchController during countdown and spawn.
func set_damage_enabled(enabled: bool) -> void:
	_damage_enabled = enabled


func apply_damage(amount: float, source: String = "unknown", cooldown: float = 0.0) -> bool:
	if net_client or is_eliminated or is_invulnerable or not _damage_enabled:
		return false
	if _source_cooldowns.has(source):
		return false

	if cooldown > 0.0:
		_source_cooldowns[source] = cooldown
	is_invulnerable = true
	_invuln_timer = AppConfig.DUEL_INVULNERABILITY if duel_mode else AppConfig.INVULNERABILITY_TIME

	if has_shield:
		has_shield = false
		shield_changed.emit(false)
		shield_absorbed.emit()
		return true

	hearts = maxf(0.0, hearts - amount)
	if duel_mode:
		damaged.emit(amount, source)
		hearts_changed.emit(hearts)
		if hearts <= 0.0:
			duel_down.emit()
		return true
	if hearts <= 0.0 and has_second_chance:
		has_second_chance = false
		hearts = 0.5
		second_chance_changed.emit(false)
		second_chance_used.emit()
	damaged.emit(amount, source)
	hearts_changed.emit(hearts)

	if hearts <= 0.0:
		eliminate()
	return true


func grant_second_chance() -> void:
	if is_eliminated:
		return
	has_second_chance = true
	second_chance_changed.emit(true)


func grant_shield() -> void:
	if is_eliminated:
		return
	has_shield = true
	shield_changed.emit(true)


## Heart Refill. Restores hearts up to the cap.
## It must NEVER bring back an eliminated racer.
func refill(amount: float) -> void:
	if is_eliminated:
		return
	hearts = minf(AppConfig.HEARTS_MAX, hearts + amount)
	hearts_changed.emit(hearts)


## Online: apply the server's health state and fire the same signals a local change would,
## so the HUD, audio and rig cannot tell the difference.
func net_apply(p_hearts: float, shield: bool, second_chance: bool, p_eliminated: bool) -> void:
	if is_eliminated:
		return
	var lost := hearts - p_hearts
	if has_shield and not shield and lost <= 0.0:
		shield_absorbed.emit()
	if has_shield != shield:
		has_shield = shield
		shield_changed.emit(shield)
	if has_second_chance and not second_chance and p_hearts > 0.0 and p_hearts <= 0.5:
		second_chance_used.emit()
	if has_second_chance != second_chance:
		has_second_chance = second_chance
		second_chance_changed.emit(second_chance)
	if not is_equal_approx(p_hearts, hearts):
		hearts = clampf(p_hearts, 0.0, AppConfig.HEARTS_MAX)
		if lost > 0.0:
			damaged.emit(lost, "server")
		hearts_changed.emit(hearts)
	if duel_mode:
		return
	if p_eliminated or (hearts <= 0.0 and grace_left < 0.0):
		eliminate()


## Online client: the server's grace deadline, or -1 for none.
func net_set_grace(seconds: float) -> void:
	if seconds >= 0.0 and grace_left < 0.0:
		grace_left = seconds
		last_heart_started.emit(seconds)
	elif seconds < 0.0:
		grace_left = -1.0
	elif absf(seconds - grace_left) > 0.5:
		grace_left = seconds


func in_grace() -> bool:
	return grace_left >= 0.0


## Why a heart cannot be traded right now, or "" if it can. The caller (GameWorld) adds the
## race-phase checks; this is the health side of the rule.
func exchange_problem() -> String:
	if duel_mode:
		return "not in the Freedom Duel"
	if is_eliminated:
		return "eliminated"
	if not _damage_enabled:
		return "not during the countdown"
	if hearts < AppConfig.HEART_EXCHANGE_COST:
		return "you need a full heart"
	return ""


## The health half of the transaction: take exactly one heart, and start the grace deadline
## if that was the last. Not damage: shields, invulnerability and Second Chance play no part.
func exchange_heart() -> bool:
	if exchange_problem() != "":
		return false
	hearts = maxf(0.0, hearts - AppConfig.HEART_EXCHANGE_COST)
	var last := hearts <= 0.0
	hearts_changed.emit(hearts)
	if last and grace_left < 0.0:
		grace_left = AppConfig.LAST_HEART_GRACE
		last_heart_started.emit(grace_left)
	heart_exchanged.emit(last)
	return true


## Qualifying, the duel or leaving the cave ends the cave-only deadline.
func clear_grace() -> void:
	grace_left = -1.0


## Freedom Duel start: full hearts, no invulnerability or cave power-ups carried in.
func begin_duel(p_hearts: float) -> void:
	grace_left = -1.0
	duel_mode = true
	is_eliminated = false
	is_invulnerable = false
	_invuln_timer = 0.0
	_source_cooldowns.clear()
	if has_second_chance:
		has_second_chance = false
		second_chance_changed.emit(false)
	if has_shield:
		has_shield = false
		shield_changed.emit(false)
	hearts = p_hearts
	hearts_changed.emit(hearts)


func drop_shield() -> void:
	if has_shield:
		has_shield = false
		shield_changed.emit(false)


func eliminate() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	hearts = 0.0
	hearts_changed.emit(hearts)
	eliminated.emit()
