extends Node
## Match state carried between scenes: seed, roster size, results, per-racer stats.
## Single source of truth for "what race are we in". Never touches nodes or UI.
## See docs/ARCHITECTURE.md.

signal stats_changed()

## The cave seed for the next / current match.
var seed_value: int = 0
## 0-4 bots. Zero is Time Trial: just you, your ghost and the clock.
var bot_count: int = 2
## 0 Easy, 1 Normal, 2 Hard. See BotController.skill.
var bot_skill: int = 0
## Index into CaveGenerator.SIZE_PRESETS. 1 is Standard.
var cave_size: int = 1
## AXIS-010: slow Move regeneration, off by default.
var move_regen: bool = false
## ART-012: environment for the next offline race, a CaveTheme id. Visual only.
var theme_id: String = "stone_age"
## Set by the lobby so GameWorld knows to read this state instead of its export defaults.
## Test harnesses that instantiate game_world.tscn directly never set it.
var launched_from_menu: bool = false

## Results as produced by MatchController.build_results(), copied at match end.
var last_results: Array = []
## Racer name -> {boxes, moves_used, damage_taken, shifts, colour}
var stats: Dictionary = {}
var last_match_seed: int = 0
var last_match_duration: float = 0.0
## Freedom Duel summary for results: {fought, duration, reason}. Empty when there was no duel.
var last_duel: Dictionary = {}
## Set when the local racer's finish beat their best on this cave. Read by results.
var new_record: bool = false
var last_cave_size: int = 1
## Where the pause menu's "Settings" should return to. Cleared by the settings scene.
var settings_return_scene: String = ""

# --- Online ---------------------------------------------------------------------------
## "" offline (the default, and all the judging fallback ever sees), "client" in an online
## race on this machine, "server" for the whole process on a dedicated server.
var net_role: String = ""
## The match configuration the server sent: seed, size, roster, local racer id, room code.
var net_config: Dictionary = {}
## True when last_results came from an online race, so results offers the lobby.
var last_results_online: bool = false
var net_local_name: String = ""
## Which online lobby the Play screen asked for: "online" (humans only) or "mixed".
var online_mode: String = "mixed"


## FUN-006: the same cave for everyone on the same calendar day.
static func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return absi(hash("daily-%04d-%02d-%02d" % [d["year"], d["month"], d["day"]])) % 1000000


func randomise_seed() -> int:
	seed_value = randi() % 1000000
	return seed_value


func prepare_match(p_seed: int, p_bots: int) -> void:
	seed_value = p_seed
	bot_count = clampi(p_bots, 0, 4)
	launched_from_menu = true
	# Starting an offline race always leaves online mode, whatever came before.
	if net_role == "client":
		net_role = ""
		net_config = {}
	last_results_online = false
	stats.clear()
	last_results.clear()
	new_record = false


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
