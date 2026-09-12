extends MenuBase

func _ready() -> void:
	super()
	add_header("Project Brief", "ABOUT PROJECT DOF", "A two-player robotics prototype where movement abilities represent mechanical degrees of freedom.")
	_add_info("TEAM", "Optimus")
	_add_info("THEME", "Degrees of Freedom")
	_add_info("ENGINE", "Godot 4.7.2 · Compatibility")
	_add_info("CREDITS", "Team members: To be added\nThird-party assets: None\nSubstantial AI-assisted material: To be documented")
	add_button("BACK", go_back.bind(GameManager.MAIN_MENU))

func _add_info(heading: String, body: String) -> void:
	var label := UIFactory.make_label(heading + "\n" + body, 15, UIFactory.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back(GameManager.MAIN_MENU)
