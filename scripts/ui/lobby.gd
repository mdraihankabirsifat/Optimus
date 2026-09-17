extends Control
## Bot Race setup: how many bots and which cave. The seed is shown and editable so a race
## can be replayed exactly, or shared with someone else.

const SKILLS: Array[String] = ["Easy", "Normal", "Hard"]

var _bots := 2
var _skill_buttons: Array[Button] = []
var _size_buttons: Array[Button] = []
var _theme_buttons: Array[Button] = []
var _rules_buttons: Array[Button] = []
var _rush_buttons: Array[Button] = []
var _rush_row: HBoxContainer
var _bot_label: Label
var _seed_edit: LineEdit
var _rules_note: Label


func _ready() -> void:
	UiKit.setup_screen(self)
	if GameState.seed_value == 0:
		GameState.randomise_seed()
	_bots = GameState.bot_count

	var col := UiKit.centre_column(self, 12)
	col.add_child(UiKit.title("Race Setup", 52))

	var panel := PanelContainer.new()
	col.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	panel.add_child(inner)

	var rules_row := HBoxContainer.new()
	rules_row.add_theme_constant_override("separation", 14)
	rules_row.add_child(_fixed(UiKit.label("Ruleset", 22), 140))
	for i in AppConfig.RACING_RULESETS.size():
		var b := UiKit.button(["Normal", "Rush"][i], func() -> void: _set_ruleset(AppConfig.RACING_RULESETS[i]), 118)
		b.toggle_mode = true
		rules_row.add_child(b)
		_rules_buttons.append(b)
	inner.add_child(rules_row)
	_rush_row = HBoxContainer.new()
	_rush_row.add_theme_constant_override("separation", 14)
	_rush_row.add_child(_fixed(UiKit.label("Rush length", 22), 140))
	for secs: int in AppConfig.RUSH_DURATIONS:
		var b := UiKit.button("%d min" % (secs / 60), func() -> void: _set_rush(secs), 118)
		b.toggle_mode = true
		_rush_row.add_child(b)
		_rush_buttons.append(b)
	inner.add_child(_rush_row)
	_rules_note = UiKit.label("", 15, UiKit.TEXT_DIM)
	inner.add_child(_rules_note)

	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 14)
	bot_row.add_child(_fixed(UiKit.label("Bots", 22), 140))
	bot_row.add_child(UiKit.button("-", func() -> void: _set_bots(_bots - 1), 56))
	_bot_label = UiKit.label("", 22, UiKit.EMBER)
	_bot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bot_row.add_child(_fixed(_bot_label, 220))
	bot_row.add_child(UiKit.button("+", func() -> void: _set_bots(_bots + 1), 56))
	inner.add_child(bot_row)

	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 14)
	skill_row.add_child(_fixed(UiKit.label("Bot skill", 22), 140))
	for i in SKILLS.size():
		var b := UiKit.button(SKILLS[i], func() -> void: _set_skill(i), 118)
		b.toggle_mode = true
		skill_row.add_child(b)
		_skill_buttons.append(b)
	inner.add_child(skill_row)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 14)
	size_row.add_child(_fixed(UiKit.label("Cave size", 22), 140))
	for i in CaveGenerator.SIZE_PRESETS.size():
		var b := UiKit.button(CaveGenerator.SIZE_PRESETS[i]["name"], func() -> void: _set_cave_size(i), 118)
		b.toggle_mode = true
		size_row.add_child(b)
		_size_buttons.append(b)
	inner.add_child(size_row)

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 10)
	theme_row.add_child(_fixed(UiKit.label("Environment", 22), 140))
	for id: String in CaveTheme.IDS:
		var b := UiKit.button(CaveTheme.by_id(id).display_name, func() -> void: _set_theme(id), 118)
		b.toggle_mode = true
		theme_row.add_child(b)
		_theme_buttons.append(b)
	inner.add_child(theme_row)

	var regen_row := HBoxContainer.new()
	regen_row.add_theme_constant_override("separation", 14)
	regen_row.add_child(_fixed(UiKit.label("Move regen", 22), 140))
	var regen := CheckButton.new()
	regen.text = "+1 Move every %ds (off: five Moves, no more)" % int(AppConfig.MOVE_REGEN_INTERVAL)
	regen.button_pressed = GameState.move_regen
	regen.toggled.connect(func(on: bool) -> void: GameState.move_regen = on)
	regen_row.add_child(regen)
	inner.add_child(regen_row)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 14)
	seed_row.add_child(_fixed(UiKit.label("Cave seed", 22), 140))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(GameState.seed_value)
	_seed_edit.custom_minimum_size = Vector2(230, 48)
	_seed_edit.max_length = 9
	seed_row.add_child(_seed_edit)
	seed_row.add_child(UiKit.button("Random", func() -> void:
		_seed_edit.text = str(GameState.randomise_seed()), 120))
	seed_row.add_child(UiKit.button("Daily", func() -> void:
		_seed_edit.text = str(GameState.daily_seed())
		_set_cave_size(1), 100))
	inner.add_child(seed_row)

	inner.add_child(UiKit.label("Same seed and size, same cave, on every machine. Daily is today's cave for everyone.", 15, UiKit.TEXT_DIM))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	buttons.add_child(UiKit.button("Back", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU), 200))
	var start := UiKit.button("Start Race", _start, 320)
	buttons.add_child(start)

	_set_bots(_bots)
	_set_skill(GameState.bot_skill)
	_set_cave_size(GameState.cave_size)
	_set_theme(GameState.theme_id)
	_set_ruleset(GameState.ruleset)
	_set_rush(GameState.rush_seconds)
	start.grab_focus.call_deferred()


func _set_ruleset(r: String) -> void:
	GameState.ruleset = r if r in AppConfig.RACING_RULESETS else AppConfig.RULESET_NORMAL
	for k in _rules_buttons.size():
		_rules_buttons[k].set_pressed_no_signal(AppConfig.RACING_RULESETS[k] == GameState.ruleset)
	var rush := GameState.ruleset == AppConfig.RULESET_RUSH
	_rush_row.visible = rush
	_rules_note.text = ("Rush: an easier cave and a clock. When it runs out, one qualifier is Champion by default; none means no Champion. Every other option still applies."
		if rush else "Normal: the full cave, no time limit. The first two out fight the Freedom Duel.")


func _set_rush(secs: int) -> void:
	GameState.rush_seconds = secs if secs in AppConfig.RUSH_DURATIONS else AppConfig.RUSH_DEFAULT
	for k in _rush_buttons.size():
		_rush_buttons[k].set_pressed_no_signal(AppConfig.RUSH_DURATIONS[k] == GameState.rush_seconds)


func _fixed(c: Control, width: float) -> Control:
	c.custom_minimum_size.x = width
	return c


func _set_bots(n: int) -> void:
	_bots = clampi(n, 0, 4)
	_bot_label.text = "Time trial" if _bots == 0 else "%d   (%d racers)" % [_bots, _bots + 1]


func _set_skill(i: int) -> void:
	GameState.bot_skill = i
	for k in _skill_buttons.size():
		_skill_buttons[k].set_pressed_no_signal(k == i)


func _set_theme(id: String) -> void:
	GameState.theme_id = id if id in CaveTheme.IDS else "stone_age"
	for k in _theme_buttons.size():
		_theme_buttons[k].set_pressed_no_signal(CaveTheme.IDS[k] == GameState.theme_id)


func _set_cave_size(i: int) -> void:
	GameState.cave_size = i
	for k in _size_buttons.size():
		_size_buttons[k].set_pressed_no_signal(k == i)


func _start() -> void:
	var digits := ""
	for ch in _seed_edit.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	var seed_value := int(digits) if digits != "" else GameState.randomise_seed()
	GameState.prepare_match(seed_value, _bots)
	SceneRouter.start_match()
