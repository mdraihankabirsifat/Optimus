extends Control
## Main menu. Play leads to the mode choice: offline Bot Race, Online Race, Mixed Race.

func _ready() -> void:
	UiKit.setup_screen(self)
	# Arriving here always means leaving any online session behind.
	if GameState.net_role == "client":
		GameState.net_role = ""
	if NetManager.in_room():
		NetManager.leave_room()
	var col := UiKit.centre_column(self, 12)
	col.add_child(UiKit.logo(96.0))
	col.add_child(UiKit.title(AppConfig.GAME_TITLE, 76))
	col.add_child(UiKit.title("Five Moves. Six directions. One hidden exit.", 22, UiKit.TEXT_DIM))
	col.add_child(UiKit.label(""))

	var race := UiKit.button("Play", func() -> void: SceneRouter.go_to(SceneRouter.MODE_SELECT))
	col.add_child(race)
	col.add_child(UiKit.button("How to Play", func() -> void: SceneRouter.go_to(SceneRouter.HOW_TO_PLAY)))
	col.add_child(UiKit.button("Settings", func() -> void: SceneRouter.go_to(SceneRouter.SETTINGS)))
	col.add_child(UiKit.button("About the Theme", func() -> void: SceneRouter.go_to(SceneRouter.ABOUT)))
	col.add_child(UiKit.button("Credits", func() -> void: SceneRouter.go_to(SceneRouter.CREDITS)))
	# A browser tab cannot be quit from inside the page.
	if OS.get_name() != "Web":
		col.add_child(UiKit.button("Quit", func() -> void: SceneRouter.quit_game()))

	if SettingsManager.best_time > 0.0:
		col.add_child(UiKit.label(""))
		var best := UiKit.title("Best time  %s   (seed %d)" % [
			MatchController.format_time(SettingsManager.best_time), SettingsManager.best_time_seed],
			18, UiKit.TEXT_DIM)
		col.add_child(best)
	if not SettingsManager.seen_tutorial:
		col.add_child(UiKit.title("New here? Read How to Play first.", 18, UiKit.EMBER))

	race.grab_focus.call_deferred()
