extends Control
## Title card. Any key or click skips straight to the main menu.

const HOLD := 1.8

var _leaving := false


func _ready() -> void:
	UiKit.setup_screen(self)
	var col := UiKit.centre_column(self, 10)
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
