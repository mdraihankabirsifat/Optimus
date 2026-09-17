extends Control
## Play: pick how to race. Bot Race needs nothing but this machine and is always offered
## first -- it is the mode that works with no network at all.

var _name_edit: LineEdit
var _name_note: Label


func _ready() -> void:
	UiKit.setup_screen(self)
	var col := UiKit.centre_column(self, 14)
	col.add_child(UiKit.title("Play", 64))

	# Prompt 3: your name, before any mode. Saved, and used offline and online alike.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_child(UiKit.label("Your name", 22))
	_name_edit = LineEdit.new()
	_name_edit.max_length = LobbyState.NAME_MAX
	_name_edit.custom_minimum_size = Vector2(360, 46)
	_name_edit.placeholder_text = "1-%d characters" % LobbyState.NAME_MAX
	_name_edit.text = SettingsManager.player_name
	_name_edit.text_changed.connect(func(_t: String) -> void: _name_note.text = "")
	name_row.add_child(_name_edit)
	col.add_child(name_row)
	_name_note = UiKit.label("", 16, UiKit.DANGER)
	_name_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name_note)

	var bot := _mode_card(col, "Bot Race",
		"You against 1-4 bots. Offline, no internet needed.",
		func() -> void:
			if _save_name():
				SceneRouter.go_to(SceneRouter.LOBBY))
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


## Validate and save the name. Blank is refused with a message rather than silently renamed.
func _save_name() -> bool:
	var problem := LobbyState.name_problem(_name_edit.text)
	if problem != "":
		_name_note.text = problem
		_name_edit.grab_focus()
		return false
	SettingsManager.player_name = LobbyState.clean_name(_name_edit.text)
	_name_edit.text = SettingsManager.player_name
	SettingsManager.save_settings()
	return true


func _online(mode: String) -> void:
	if not _save_name():
		return
	GameState.online_mode = mode
	SceneRouter.go_to(SceneRouter.ONLINE_LOBBY)
