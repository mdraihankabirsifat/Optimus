extends Control
## Title card. Any key or click skips straight to the main menu.

const HOLD := 1.8
const SERVER_SCENE := "res://scenes/net/server.tscn"

var _leaving := false


func _ready() -> void:
	# Dedicated server launch: `Escave.exe --headless -- --server --port=8910`.
	# Exported release builds refuse a scene path on the command line, so the flag is read
	# here, in the main scene, and works the same from source and from an exported build.
	if "--server" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred(SERVER_SCENE)
		return
	UiKit.setup_screen(self)
	var col := UiKit.centre_column(self, 10)
	col.add_child(UiKit.logo(170.0))
	col.add_child(UiKit.title(AppConfig.GAME_TITLE, 96))
	col.add_child(UiKit.title("gravity is yours alone", 26, UiKit.TEXT_DIM))
	col.add_child(UiKit.label(""))
	var team := UiKit.title("%s  ·  BUET Robotics Society GameJam 2026" % AppConfig.TEAM_NAME, 18, UiKit.TEXT_DIM)
	col.add_child(team)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)
	await get_tree().create_timer(HOLD).timeout
	_leave()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	SceneRouter.go_to(SceneRouter.MAIN_MENU)
