extends Control
## Settings screen. The controls themselves live in UiKit.settings_panel() so the pause
## menu shows the same ones.

func _ready() -> void:
	UiKit.setup_screen(self)
	var col := UiKit.centre_column(self, 20)
	col.add_child(UiKit.title("Settings", 64))
	var panel := PanelContainer.new()
	panel.add_child(UiKit.settings_panel())
	col.add_child(panel)
	var back := UiKit.button("Back", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(back)
	back.grab_focus.call_deferred()
