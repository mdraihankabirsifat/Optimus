extends Control
## Play: pick how to race. Bot Race needs nothing but this machine and is always offered
## first -- it is the mode that works with no network at all.

func _ready() -> void:
	UiKit.setup_screen(self)
	var col := UiKit.centre_column(self, 14)
	col.add_child(UiKit.title("Play", 64))

	var bot := _mode_card(col, "Bot Race",
		"You against 1-4 bots. Offline, no internet needed.",
		func() -> void: SceneRouter.go_to(SceneRouter.LOBBY))
	_mode_card(col, "Online Race",
		"2-5 humans. Create a room and share its code, or join one.",
		func() -> void: _online("online"))
	_mode_card(col, "Mixed Race",
		"Humans and bots together, 2-5 racers. Fill empty slots with bots.",
		func() -> void: _online("mixed"))

	if not AppConfig.NETWORKING_ENABLED:
		col.add_child(UiKit.label("Online play is switched off in this build.", 16, UiKit.TEXT_DIM))

	var back := UiKit.button("Back", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU), 240)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(back)
	bot.grab_focus.call_deferred()


func _mode_card(col: VBoxContainer, heading: String, blurb: String, action: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var b := UiKit.button(heading, action, 260)
	b.disabled = heading != "Bot Race" and not AppConfig.NETWORKING_ENABLED
	row.add_child(b)
	var text := UiKit.label(blurb, 18, UiKit.TEXT_DIM)
	text.custom_minimum_size = Vector2(430, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	col.add_child(row)
	return b


func _online(mode: String) -> void:
	GameState.online_mode = mode
	SceneRouter.go_to(SceneRouter.ONLINE_LOBBY)
