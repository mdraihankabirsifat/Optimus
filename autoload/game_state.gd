extends Node
## Match state carried between scenes: seed, roster size, results, per-racer stats.
## Single source of truth for "what race are we in". Never touches nodes or UI.
## See docs/ARCHITECTURE.md.

signal stats_changed()

## The cave seed for the next / current match.
var seed_value: int = 0
## 1-4 bots, giving 2-5 racers in total.
var bot_count: int = 2
## 0 Easy, 1 Normal, 2 Hard. See BotController.skill.
var bot_skill: int = 0
## Set by the lobby so GameWorld knows to read this state instead of its export defaults.
## Test harnesses that instantiate game_world.tscn directly never set it.
var launched_from_menu: bool = false

## Results as produced by MatchController.build_results(), copied at match end.
var last_results: Array = []
## Racer name -> {boxes, moves_used, damage_taken, shifts, colour}
var stats: Dictionary = {}
var last_match_seed: int = 0
var last_match_duration: float = 0.0
## Where the pause menu's "Settings" should return to. Cleared by the settings scene.
var settings_return_scene: String = ""


func randomise_seed() -> int:
	seed_value = randi() % 1000000
	return seed_value


func prepare_match(p_seed: int, p_bots: int) -> void:
	seed_value = p_seed
	bot_count = clampi(p_bots, 1, 4)
	launched_from_menu = true
	stats.clear()
	last_results.clear()


func register_racer_stats(racer_name: String, colour: Color, is_bot: bool) -> void:
	stats[racer_name] = {
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
	stats_changed.emit()


func record_results(results: Array, p_seed: int, duration: float) -> void:
	last_results = results.duplicate(true)
	# Bodies are freed with the scene; strip them so results survive the transition.
	for entry: Dictionary in last_results:
		entry.erase("body")
	last_match_seed = p_seed
	last_match_duration = duration
