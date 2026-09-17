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
## Comfort: head bob and camera shake/hitstop can each be switched off.
var head_bob: bool = true
var camera_effects: bool = true
## FEEL-005/006 playtest tuning. Defaults are the locked design values.
var turn_time: float = AppConfig.GRAVITY_TRANSITION_TIME
var acceleration: float = AppConfig.ACCELERATION
## MATCH-006: best finish per cave, keyed "seed:size".
var best_times: Dictionary = {}
## Set once the player has read How To Play or finished a race.
var seen_tutorial: bool = false
## Invert vertical mouse look.
var invert_y: bool = false
## 0 Low (lower 3D resolution), 1 Medium, 2 High (antialiasing). Kept to one choice.
var graphics_quality: int = 1
## Online: the name shown to other racers, and the last server used.
var player_name: String = ""
var server_url: String = ""
## Remapped keys: action -> physical keycode. Only changed actions are stored.
var key_bindings: Dictionary = {}

## Prompt 3: there is no Window Size setting any more. The OS resizes the window; this is only
## the size a window is restored to when it has none that fits the screen.
const WINDOWED_DEFAULT := Vector2i(1280, 720)
## Room left for the title bar and taskbar when fitting a window onto a monitor.
const TITLE_BAR_ROOM := 48
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Actions a player may rebind from Settings.
const REMAPPABLE: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "jump",
	"sprint", "gravity_mod", "interact", "toggle_map", "exchange_heart", "duel_fire", "duel_lock"]

var _default_keys: Dictionary = {}
var _default_events: Dictionary = {}
var _window_checked := false


func _ready() -> void:
	for action: String in REMAPPABLE:
		_default_keys[action] = _first_key(action)
		# Some actions ship with more than one default -- the duel fires on left mouse and
		# locks on right mouse or Q. Keep every default event so a reset restores them all.
		_default_events[action] = InputMap.action_get_events(action).duplicate()
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
	head_bob = bool(cfg.get_value("comfort", "head_bob", head_bob))
	camera_effects = bool(cfg.get_value("comfort", "camera_effects", camera_effects))
	turn_time = clampf(float(cfg.get_value("feel", "turn_time", turn_time)), 0.2, 0.6)
	acceleration = clampf(float(cfg.get_value("feel", "acceleration", acceleration)), 4.0, 30.0)
	best_times = cfg.get_value("records", "best_times", best_times)
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	# Old saves may hold ["video", "resolution"]. It is ignored on purpose: a 1920x1080 window
	# on a 1080p monitor is what pushed the title bar off the top of the screen.
	graphics_quality = clampi(int(cfg.get_value("video", "quality", graphics_quality)), 0, 2)
	player_name = String(cfg.get_value("online", "player_name", player_name))
	server_url = String(cfg.get_value("online", "server_url", server_url))
	var keys: Variant = cfg.get_value("input", "key_bindings", {})
	if keys is Dictionary:
		key_bindings = keys
		for action: String in key_bindings:
			if action in REMAPPABLE:
				_bind(action, int(key_bindings[action]))


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
	cfg.set_value("comfort", "head_bob", head_bob)
	cfg.set_value("comfort", "camera_effects", camera_effects)
	cfg.set_value("feel", "turn_time", turn_time)
	cfg.set_value("feel", "acceleration", acceleration)
	cfg.set_value("records", "best_times", best_times)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("online", "player_name", player_name)
	cfg.set_value("online", "server_url", server_url)
	cfg.set_value("input", "key_bindings", key_bindings)
	cfg.save(PATH)


## Rebind a remappable action to one key, and remember it. Returns the action that key was
## taken from, if another action used it, so the caller can warn about the swap.
func remap_action(action: String, physical_keycode: int) -> String:
	if action not in REMAPPABLE:
		return ""
	var clashed := ""
	for other: String in REMAPPABLE:
		if other != action and _first_key(other) == physical_keycode:
			# Swap, so no action is ever left unbound.
			var previous := _first_key(action)
			_bind(other, previous)
			key_bindings[other] = previous
			clashed = other
	_bind(action, physical_keycode)
	key_bindings[action] = physical_keycode
	save_settings()
	changed.emit()
	return clashed


func reset_keys() -> void:
	for action: String in REMAPPABLE:
		if _default_events.has(action):
			InputMap.action_erase_events(action)
			for ev: InputEvent in _default_events[action]:
				InputMap.action_add_event(action, ev)
		else:
			_bind(action, int(_default_keys[action]))
	key_bindings.clear()
	save_settings()
	changed.emit()


func _bind(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action) or physical_keycode == 0:
		return
	# A rebind replaces the keyboard binding but keeps any mouse button the action had, so
	# rebinding the duel's Axis Lock key does not take the mouse button away with it.
	var kept: Array[InputEvent] = []
	for existing: InputEvent in InputMap.action_get_events(action):
		if not (existing is InputEventKey):
			kept.append(existing)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode as Key
	InputMap.action_add_event(action, ev)
	for extra: InputEvent in kept:
		InputMap.action_add_event(action, extra)


func _first_key(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return int((ev as InputEventKey).physical_keycode)
	return 0


## Push the stored values into the engine: audio buses and window mode.
func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	# Headless test runs have no window; only touch it when one exists.
	if DisplayServer.get_name() != "headless":
		_apply_window_mode()
		_apply_frame_pacing()
	var vp := get_viewport()
	if vp != null:
		# GL Compatibility: bilinear 3D scaling and MSAA are the two cheap, reliable levers.
		vp.scaling_3d_scale = 0.75 if graphics_quality == 0 else 1.0
		vp.msaa_3d = Viewport.MSAA_2X if graphics_quality == 2 else Viewport.MSAA_DISABLED
	changed.emit()


## macOS runs GL Compatibility on Apple's OpenGL-over-Metal layer, which does not honour the
## vsync swap interval: frames arrived 6-19 ms apart on a 60 Hz MacBook (about 94 fps), so
## motion judders and tears. Capping to the display's refresh rate restores even 16.7 ms
## frames (late frames 9.8% -> 1.6%, measured). Windows and web already pace correctly.
func _apply_frame_pacing() -> void:
	if OS.get_name() != "macOS":
		return
	var hz := roundi(DisplayServer.screen_get_refresh_rate())
	Engine.max_fps = clampi(hz, 30, 240) if hz > 0 else 60


## Prompt 3: fullscreen OFF must be a normal decorated window -- title bar, minimise,
## maximise, close -- that fits on the monitor. A maximised window is left maximised.
func _apply_window_mode() -> void:
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen:
		if not is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if OS.get_name() == "Web":
		# The browser owns its own chrome; only leave browser fullscreen.
		if is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return
	if is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_window_checked = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	if not _window_checked and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		_window_checked = true
		# After leaving fullscreen the OS restores the size on the next frame; fit it then.
		_fit_window.call_deferred()


## Keep a windowed window, title bar included, inside the usable area of its monitor.
func _fit_window() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var room := Vector2i(usable.size.x - 16, usable.size.y - TITLE_BAR_ROOM)
	var size := DisplayServer.window_get_size()
	if size.x > room.x or size.y > room.y or size.x < 640 or size.y < 360:
		size = Vector2i(mini(WINDOWED_DEFAULT.x, room.x), mini(WINDOWED_DEFAULT.y, room.y))
		DisplayServer.window_set_size(size)
	var pos := DisplayServer.window_get_position()
	var min_pos := usable.position + Vector2i(0, TITLE_BAR_ROOM / 2)
	var max_pos := usable.position + usable.size - size
	if pos.x < usable.position.x or pos.y < min_pos.y or pos.x > max_pos.x or pos.y > max_pos.y:
		pos = usable.position + (usable.size - size) / 2
		pos.y = maxi(pos.y, min_pos.y)
		DisplayServer.window_set_position(pos)


func set_and_save(property: String, value: Variant) -> void:
	set(property, value)
	apply()
	save_settings()


## `tag` (GameState.make_record_tag) separates rulesets, Rush lengths, generator versions
## and regeneration. Without one the key is the old "seed:size" form, kept for old files.
static func cave_key(p_seed: int, size: int, tag: String = "") -> String:
	if tag == "":
		return "%d:%d" % [p_seed, size]
	return "%s:%d:%d" % [tag, p_seed, size]


func best_for(p_seed: int, size: int, tag: String = "") -> float:
	return float(best_times.get(cave_key(p_seed, size, tag), 0.0))


## Top five times on one cave, fastest first.
func leaderboard(p_seed: int, size: int, tag: String = "") -> Array:
	return (best_times.get(cave_key(p_seed, size, tag) + ":board", []) as Array).duplicate()


## MATCH-006: records a finish on this cave. Returns true when it beats the previous best.
func submit_cave_time(seconds: float, p_seed: int, size: int, tag: String = "") -> bool:
	var key := cave_key(p_seed, size, tag)
	var board: Array = best_times.get(key + ":board", [])
	board.append(seconds)
	board.sort()
	best_times[key + ":board"] = board.slice(0, 5)
	var previous := float(best_times.get(key, 0.0))
	var record := previous <= 0.0 or seconds < previous
	if record:
		best_times[key] = seconds
	submit_time(seconds, p_seed)
	save_settings()
	return record


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
