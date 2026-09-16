extends Node
## Every scene change in the game goes through here, with a short fade so transitions
## never pop. Holds no gameplay state.

const SPLASH := "res://scenes/ui/splash.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const LOBBY := "res://scenes/ui/lobby.tscn"
const SETTINGS := "res://scenes/ui/settings.tscn"
const HOW_TO_PLAY := "res://scenes/ui/how_to_play.tscn"
const ABOUT := "res://scenes/ui/about.tscn"
const CREDITS := "res://scenes/ui/credits.tscn"
const RESULTS := "res://scenes/ui/results.tscn"
const GAME := "res://scenes/game/game_world.tscn"
const LOADING := "res://scenes/ui/loading.tscn"

const FADE_TIME := 0.28

var _layer: CanvasLayer
var _fade: ColorRect
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.03, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


func is_busy() -> bool:
	return _busy


func go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tween.finished

	# Menus need a visible cursor; the game re-captures it in the player's _ready.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame

	var out := create_tween()
	out.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	await out.finished
	_busy = false


## Starts a race using whatever GameState currently holds.
func start_match() -> void:
	GameState.launched_from_menu = true
	go_to(LOADING)


func quit_game() -> void:
	SettingsManager.save_settings()
	get_tree().quit()
