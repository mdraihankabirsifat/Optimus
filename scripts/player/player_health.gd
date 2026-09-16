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

var hearts: float = 5.0
var is_eliminated: bool = false
var is_invulnerable: bool = false
## A mystery-box shield soaks the next hit entirely. Never stacks.
var has_shield: bool = false

## Per-source cooldowns. Prevents a single hazard draining hearts every physics frame.
var _source_cooldowns: Dictionary = {}
var _invuln_timer: float = 0.0
## Blocks all damage during countdown, spawn and loading.
var _damage_enabled: bool = true


func _ready() -> void:
	hearts = AppConfig.HEARTS_MAX
	hearts_changed.emit(hearts)


func _process(delta: float) -> void:
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
	if is_eliminated or is_invulnerable or not _damage_enabled:
		return false
	if _source_cooldowns.has(source):
		return false

	if cooldown > 0.0:
		_source_cooldowns[source] = cooldown
	is_invulnerable = true
	_invuln_timer = AppConfig.INVULNERABILITY_TIME

	if has_shield:
		has_shield = false
		shield_changed.emit(false)
		shield_absorbed.emit()
		return true

	hearts = maxf(0.0, hearts - amount)
	damaged.emit(amount, source)
	hearts_changed.emit(hearts)

	if hearts <= 0.0:
		eliminate()
	return true


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


func eliminate() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	hearts = 0.0
	hearts_changed.emit(hearts)
	eliminated.emit()
