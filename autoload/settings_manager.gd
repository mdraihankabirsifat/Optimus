extends Node
## User preferences and persistence. Saves to user://settings.cfg.
## Knows nothing about gameplay; it only stores values and tells listeners they changed.

signal changed()

const PATH := "user://settings.cfg"

var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8
## Multiplier applied on top of AppConfig.MOUSE_SENSITIVITY.
var sensitivity: float = 1.0
var fullscreen: bool = false
## Best finish time on any seed, in seconds. 0 means none yet.
var best_time: float = 0.0
var best_time_seed: int = 0
## Set once the player has read How To Play or finished a race.
var seen_tutorial: bool = false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	sensitivity = float(cfg.get_value("input", "sensitivity", sensitivity))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	best_time = float(cfg.get_value("records", "best_time", best_time))
	best_time_seed = int(cfg.get_value("records", "best_time_seed", best_time_seed))
	seen_tutorial = bool(cfg.get_value("progress", "seen_tutorial", seen_tutorial))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("records", "best_time", best_time)
	cfg.set_value("records", "best_time_seed", best_time_seed)
	cfg.set_value("progress", "seen_tutorial", seen_tutorial)
	cfg.save(PATH)


## Push the stored values into the engine: audio buses and window mode.
func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	# Headless test runs have no window; only touch it when one exists.
	if DisplayServer.get_name() != "headless":
		var target := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
			else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target:
			DisplayServer.window_set_mode(target)
	changed.emit()


func set_and_save(property: String, value: Variant) -> void:
	set(property, value)
	apply()
	save_settings()


## Records a finish time if it beats the stored best. Returns true when it is a new record.
func submit_time(seconds: float, p_seed: int) -> bool:
	if best_time > 0.0 and seconds >= best_time:
		return false
	best_time = seconds
	best_time_seed = p_seed
	save_settings()
	return true


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)
