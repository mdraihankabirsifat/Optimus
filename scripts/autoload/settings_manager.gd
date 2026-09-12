extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULTS: Dictionary = {"master_volume": 0.8, "music_volume": 0.7, "sfx_volume": 0.8, "master_muted": false, "fullscreen": false}
var values: Dictionary = DEFAULTS.duplicate(true)

func _ready() -> void:
	load_settings()
	apply_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		values = DEFAULTS.duplicate(true)
		return
	for key: String in DEFAULTS:
		var loaded: Variant = config.get_value("settings", key, DEFAULTS[key])
		if typeof(loaded) == typeof(DEFAULTS[key]):
			values[key] = loaded

func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in values:
		config.set_value("settings", key, values[key])
	config.save(SETTINGS_PATH)

func apply_settings() -> void:
	_set_bus_volume("Master", float(values.master_volume))
	_set_bus_volume("Music", float(values.music_volume))
	_set_bus_volume("SFX", float(values.sfx_volume))
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, bool(values.master_muted))
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(values.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func reset_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	apply_settings()

func _set_bus_volume(bus_name: String, normalized: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(normalized, 0.001, 1.0)))
