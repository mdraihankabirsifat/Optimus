extends Control
## Main menu. Offline Bot Race is the whole game for the jam; online play is not offered
## unless AppConfig.NETWORKING_ENABLED is on (it is not).

func _ready() -> void:
	UiKit.setup_screen(self)
	var col := UiKit.centre_column(self, 12)
	col.add_child(UiKit.title(AppConfig.GAME_TITLE, 84))
	col.add_child(UiKit.title("Five Moves. Six directions. One hidden exit.", 22, UiKit.TEXT_DIM))
	col.add_child(UiKit.label(""))

	var race := UiKit.button("Bot Race", func() -> void: SceneRouter.go_to(SceneRouter.LOBBY))
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
