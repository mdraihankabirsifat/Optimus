extends Node

const SAVE_PATH: String = "user://save_data.cfg"
var unlocked_level_count: int = 1
var last_selected_difficulty: String = "Easy"
var last_selected_level: int = 1
var high_scores: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	reset_data()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var unlocked: Variant = config.get_value("progress", "unlocked_level_count", 1)
	var difficulty: Variant = config.get_value("progress", "last_selected_difficulty", "Easy")
	var level: Variant = config.get_value("progress", "last_selected_level", 1)
	var scores: Variant = config.get_value("scores", "high_scores", {})
	if typeof(unlocked) == TYPE_INT:
		unlocked_level_count = clampi(unlocked, 1, 3)
	if typeof(difficulty) == TYPE_STRING and GameManager.DIFFICULTIES.has(difficulty):
		last_selected_difficulty = difficulty
	if typeof(level) == TYPE_INT:
		last_selected_level = clampi(level, 1, unlocked_level_count)
	if typeof(scores) == TYPE_DICTIONARY:
		high_scores = scores

func reset_data() -> void:
	unlocked_level_count = 1
	last_selected_difficulty = "Easy"
	last_selected_level = 1
	high_scores = {}

func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "unlocked_level_count", unlocked_level_count)
	config.set_value("progress", "last_selected_difficulty", last_selected_difficulty)
	config.set_value("progress", "last_selected_level", last_selected_level)
	config.set_value("scores", "high_scores", high_scores)
	config.save(SAVE_PATH)

func get_high_score(difficulty: String, level: int) -> int:
	return int(high_scores.get(_score_key(difficulty, level), 0))

func record_result(difficulty: String, level: int, score: int) -> bool:
	var key := _score_key(difficulty, level)
	var is_new := score > int(high_scores.get(key, 0))
	if is_new:
		high_scores[key] = score
	if level < 3:
		unlocked_level_count = maxi(unlocked_level_count, level + 1)
	last_selected_difficulty = difficulty
	last_selected_level = clampi(level, 1, unlocked_level_count)
	save_data()
	return is_new

func remember_selection(difficulty: String, level: int) -> void:
	last_selected_difficulty = difficulty
	last_selected_level = level
	save_data()

func _score_key(difficulty: String, level: int) -> String:
	return "%s_level_%d" % [difficulty.to_lower(), level]
