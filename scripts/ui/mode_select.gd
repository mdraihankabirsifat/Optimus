extends MenuBase

func _ready() -> void:
	super()
	add_header("Local Prototype", "SELECT DIFFICULTY", "Difficulty changes time, speed, and hazard damage.")
	for difficulty: String in GameManager.DIFFICULTIES:
		var data: Dictionary = GameManager.DIFFICULTIES[difficulty]
		var score := SaveManager.get_high_score(difficulty, SaveManager.last_selected_level)
		var label := "%s  ·  %ds  ·  BEST %d" % [difficulty.to_upper(), int(data.duration), score]
		add_button(label, _select.bind(difficulty), difficulty == SaveManager.last_selected_difficulty)
	add_button("BACK", go_back.bind("res://scenes/ui/play_menu.tscn"))

func _select(difficulty: String) -> void:
	GameManager.selected_difficulty = difficulty
	SaveManager.last_selected_difficulty = difficulty
	SaveManager.save_data()
	GameManager.go_to("res://scenes/ui/level_select.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back("res://scenes/ui/play_menu.tscn")
