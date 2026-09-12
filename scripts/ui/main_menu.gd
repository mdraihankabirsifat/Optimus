extends MenuBase

func _ready() -> void:
	super()
	add_header("Team Optimus // Phase 1", "PROJECT DOF", "Freedom is a mechanical property.")
	add_button("PLAY", GameManager.go_to.bind("res://scenes/ui/play_menu.tscn"), true)
	add_button("SETTINGS", GameManager.go_to.bind("res://scenes/ui/settings_menu.tscn"))
	add_button("ABOUT", GameManager.go_to.bind("res://scenes/ui/about_menu.tscn"))
	if not OS.has_feature("web"):
		add_button("QUIT", get_tree().quit)
	var first := content.get_child(4) as Control
	if first:
		first.grab_focus()
