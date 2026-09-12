extends MenuBase

func _ready() -> void:
	super()
	add_header("Mission Control", "SELECT PLAY MODE", "Phase 1 validates local movement and game flow.")
	add_button("LOCAL PROTOTYPE", GameManager.go_to.bind("res://scenes/ui/mode_select.tscn"), true)
	add_button("3D PROTOTYPE", _start_3d)
	add_button("HOST GAME  ·  COMING IN PHASE 2", _unavailable, false, true)
	add_button("JOIN GAME  ·  COMING IN PHASE 2", _unavailable, false, true)
	add_button("BACK", go_back.bind(GameManager.MAIN_MENU))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back(GameManager.MAIN_MENU)

func _unavailable() -> void:
	pass

func _start_3d() -> void:
	GameManager.selected_difficulty = SaveManager.last_selected_difficulty
	GameManager.selected_level = SaveManager.last_selected_level
	GameManager.go_to("res://scenes/game/prototype_arena_3d.tscn")
