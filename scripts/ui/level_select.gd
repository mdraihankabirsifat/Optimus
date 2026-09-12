extends MenuBase

func _ready() -> void:
	super()
	add_header(GameManager.selected_difficulty + " Protocol", "SELECT ARENA", "Complete an arena to unlock the next test chamber.")
	for index: int in GameManager.LEVELS.size():
		var level := index + 1
		var locked := level > SaveManager.unlocked_level_count
		var score := SaveManager.get_high_score(GameManager.selected_difficulty, level)
		var label := "LOCKED  //  LEVEL %d" % level if locked else "LEVEL %d  ·  BEST %d" % [level, score]
		add_button(label, _select.bind(level), level == SaveManager.last_selected_level, locked)
	add_button("BACK", go_back.bind("res://scenes/ui/mode_select.tscn"))

func _select(level: int) -> void:
	GameManager.selected_level = level
	SaveManager.remember_selection(GameManager.selected_difficulty, level)
	GameManager.go_to("res://scenes/game/prototype_arena.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back("res://scenes/ui/mode_select.tscn")
