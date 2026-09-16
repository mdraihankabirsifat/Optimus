extends Control
## Online Race and Mixed Race: connect, create or join a room, fill the 2-5 slots, start.
##
## Everything shown here is a mirror of the server's lobby snapshot; every button sends a
## request and waits for the next snapshot. Nothing on this screen decides anything.
## The whole screen rebuilds on each snapshot or connection change: a lobby holds at most
## five rows, so rebuilding is simpler and cannot drift out of sync.

const SKILLS: Array[String] = ["Easy", "Normal", "Hard"]

var _body: VBoxContainer
var _notice: Label
var _name_edit: LineEdit
var _url_edit: LineEdit
var _code_edit: LineEdit
var _seed_edit: LineEdit


func _ready() -> void:
	UiKit.setup_screen(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)

	# Bound methods, not lambdas: Godot drops these connections when this screen is freed.
	NetManager.state_changed.connect(_on_state_changed)
	NetManager.lobby_updated.connect(_on_lobby_updated)
	NetManager.latency_updated.connect(_on_latency)
	NetManager.notice.connect(_show_notice)
	_rebuild()


func _on_state_changed(_s: int) -> void:
	_rebuild()


func _on_lobby_updated(_l: Dictionary) -> void:
	_rebuild()


func _on_latency(_ms: int) -> void:
	_update_status_only()


func _mode() -> String:
	if NetManager.in_room():
		return String(NetManager.lobby.get("mode", GameState.online_mode))
	return GameState.online_mode


func _rebuild() -> void:
	var keep_notice := _notice.text if _notice != null else ""
	var keep_colour := _notice.get_theme_color("font_color") if _notice != null else UiKit.TEXT
	for child in _body.get_children():
		child.queue_free()

	var heading := "Mixed Race" if _mode() == LobbyState.MODE_MIXED else "Online Race"
	_body.add_child(UiKit.title(heading, 52))
	_body.add_child(_status_label())

	_notice = UiKit.label(keep_notice, 18, keep_colour)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	match NetManager.state:
		NetManager.State.CONNECTED:
			if NetManager.in_room():
				_build_room()
			else:
				_build_room_choice()
		NetManager.State.CONNECTING, NetManager.State.RECONNECTING:
			_build_waiting()
		_:
			_build_connect()

	_body.add_child(_notice)


func _status_label() -> Label:
	var l := UiKit.label(_status_text(), 20, _status_colour())
	l.name = "Status"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _status_text() -> String:
	var s := "Status: %s" % NetManager.state_name()
	if NetManager.state == NetManager.State.CONNECTED:
		s += "  to %s" % NetManager.server_url
		if NetManager.latency_ms >= 0:
			s += "   ·   %d ms" % NetManager.latency_ms
	return s


func _status_colour() -> Color:
	match NetManager.state:
		NetManager.State.CONNECTED: return Color(0.5, 1.0, 0.55)
		NetManager.State.FAILED: return UiKit.DANGER
		NetManager.State.CONNECTING, NetManager.State.RECONNECTING: return UiKit.EMBER
	return UiKit.TEXT_DIM


func _update_status_only() -> void:
	var l := _body.get_node_or_null("Status") as Label
	if l != null:
		l.text = _status_text()


func _show_notice(text: String, is_error: bool) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.add_theme_color_override("font_color", UiKit.DANGER if is_error else UiKit.SKY)


# --- Not connected ----------------------------------------------------------------------

func _build_connect() -> void:
	var panel := _panel()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)

	grid.add_child(UiKit.label("Your name", 22))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(420, 46)
	_name_edit.text = SettingsManager.player_name if SettingsManager.player_name != "" else "Racer"
	grid.add_child(_name_edit)

	grid.add_child(UiKit.label("Server", 22))
	_url_edit = LineEdit.new()
	_url_edit.custom_minimum_size = Vector2(420, 46)
	_url_edit.text = NetManager.server_url if NetManager.server_url != "" else NetManager.default_server_url()
	_url_edit.placeholder_text = "ws://127.0.0.1:8910  or  wss://your-server.onrender.com"
	grid.add_child(_url_edit)

	var hint := UiKit.label("Run a local server with  godot --headless --path . res://scenes/net/server.tscn  "
		+ "(see README). A sleeping free Render server can take up to a minute to wake.", 16, UiKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(760, 0)
	_body.add_child(hint)

	var row := _row()
	var connect := UiKit.button("Connect", _connect, 260)
	row.add_child(connect)
	row.add_child(UiKit.button("Back", _back, 200))
	row.add_child(UiKit.button("Play offline instead", func() -> void: SceneRouter.go_to(SceneRouter.LOBBY), 300))
	connect.grab_focus.call_deferred()


func _connect() -> void:
	var player_name := LobbyState.sanitize_name(_name_edit.text)
	SettingsManager.player_name = player_name
	SettingsManager.server_url = _url_edit.text.strip_edges()
	SettingsManager.save_settings()
	_show_notice("", false)
	NetManager.connect_to_server(_url_edit.text, player_name)


func _build_waiting() -> void:
	var text := "Connecting to %s ..." % NetManager.server_url
	if NetManager.state == NetManager.State.RECONNECTING:
		text = "Connection dropped. Reconnecting to %s ..." % NetManager.server_url
	var l := UiKit.title(text, 22, UiKit.EMBER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	var row := _row()
	row.add_child(UiKit.button("Cancel", func() -> void: NetManager.disconnect_from_server(), 240))


# --- Connected, not in a room -----------------------------------------------------------

func _build_room_choice() -> void:
	var panel := _panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var create := UiKit.button("Create a room", func() -> void: NetManager.create_room(GameState.online_mode), 360)
	col.add_child(create)
	col.add_child(UiKit.label("You host: pick the racer count%s, the cave, and start."
		% (", add bots" if GameState.online_mode == LobbyState.MODE_MIXED else ""), 17, UiKit.TEXT_DIM))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.max_length = LobbyState.CODE_LENGTH
	_code_edit.custom_minimum_size = Vector2(200, 50)
	_code_edit.text_submitted.connect(func(t: String) -> void: NetManager.join_room(t))
	join_row.add_child(_code_edit)
	join_row.add_child(UiKit.button("Join room", func() -> void: NetManager.join_room(_code_edit.text), 220))
	col.add_child(join_row)

	var row := _row()
	row.add_child(UiKit.button("Disconnect", func() -> void: NetManager.disconnect_from_server(), 240))
	row.add_child(UiKit.button("Back", _back, 200))
	create.grab_focus.call_deferred()


# --- In a room --------------------------------------------------------------------------

func _build_room() -> void:
	var lobby := NetManager.lobby
	var host := NetManager.is_host()
	var mixed := String(lobby["mode"]) == LobbyState.MODE_MIXED

	var code_row := _row()
	code_row.add_child(UiKit.title("ROOM  %s" % lobby["code"], 44, UiKit.SKY))
	code_row.add_child(UiKit.label("share this code", 17, UiKit.TEXT_DIM))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(columns)

	# Slots
	var slots_panel := PanelContainer.new()
	slots_panel.custom_minimum_size = Vector2(560, 0)
	columns.add_child(slots_panel)
	var slots := VBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	slots_panel.add_child(slots)
	var filled: Array = lobby["slots"]
	slots.add_child(UiKit.label("Racers  %d / %d" % [filled.size(), int(lobby["total_slots"])], 20, UiKit.EMBER))
	for i in int(lobby["total_slots"]):
		slots.add_child(_slot_row(i, filled[i] if i < filled.size() else {}))

	# Settings
	var cfg_panel := PanelContainer.new()
	cfg_panel.custom_minimum_size = Vector2(520, 0)
	columns.add_child(cfg_panel)
	var cfg := VBoxContainer.new()
	cfg.add_theme_constant_override("separation", 8)
	cfg_panel.add_child(cfg)
	if host:
		_build_host_controls(cfg, lobby, mixed)
	else:
		_build_guest_view(cfg, lobby, mixed)

	# Actions
	var actions := _row()
	if host:
		var problem := String(lobby.get("start_problem", ""))
		var start := UiKit.button("Start Race" if problem == "" else problem, func() -> void: NetManager.start_race(), 420)
		start.disabled = problem != ""
		actions.add_child(start)
		if problem == "":
			start.grab_focus.call_deferred()
	else:
		var me := _my_slot(filled)
		var ready_now := bool(me.get("ready", false))
		var ready := UiKit.button("Not ready" if ready_now else "Ready up", func() -> void:
			NetManager.set_ready(not ready_now), 300)
		actions.add_child(ready)
		ready.grab_focus.call_deferred()
	actions.add_child(UiKit.button("Leave room", func() -> void: NetManager.leave_room(), 220))
	if bool(lobby.get("in_match", false)):
		_body.add_child(UiKit.title("A race is running in this room.", 20, UiKit.EMBER))


func _slot_row(index: int, slot: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_fixed(UiKit.label("%d" % (index + 1), 20, UiKit.TEXT_DIM), 22))
	if slot.is_empty():
		row.add_child(UiKit.label("open slot", 20, UiKit.TEXT_DIM))
		return row
	var colour_index := int(slot["colour"]) % LobbyState.COLOURS.size()
	var swatch := ColorRect.new()
	swatch.color = LobbyState.COLOURS[colour_index]
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var you := int(slot["id"]) == NetManager.local_peer_id
	var name_text := String(slot["name"]) + ("  (you)" if you else "")
	row.add_child(_fixed(UiKit.label(name_text, 20, LobbyState.COLOURS[colour_index]), 190))
	# Never state by colour alone: the colour's name, role and readiness are all words.
	var role := "BOT" if slot["is_bot"] else ("HOST" if slot["host"] else "human")
	row.add_child(_fixed(UiKit.label(role, 17, UiKit.EMBER if slot["host"] else UiKit.TEXT_DIM), 60))
	row.add_child(_fixed(UiKit.label(LobbyState.COLOUR_NAMES[colour_index], 16, UiKit.TEXT_DIM), 80))
	var ready_text := "ready" if slot["ready"] else "not ready"
	row.add_child(UiKit.label(ready_text, 17, Color(0.5, 1.0, 0.55) if slot["ready"] else UiKit.DANGER))
	if not slot["is_bot"] and not slot["connected"]:
		row.add_child(UiKit.label("offline", 17, UiKit.DANGER))
	return row


func _build_host_controls(cfg: VBoxContainer, lobby: Dictionary, mixed: bool) -> void:
	cfg.add_child(UiKit.label("You are the host", 20, UiKit.EMBER))

	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	slots_row.add_child(_fixed(UiKit.label("Total racers", 19), 150))
	var total := int(lobby["total_slots"])
	slots_row.add_child(UiKit.button("-", func() -> void: NetManager.host_action("slots", total - 1), 50))
	slots_row.add_child(_fixed(UiKit.label(str(total), 22, UiKit.EMBER), 30))
	slots_row.add_child(UiKit.button("+", func() -> void: NetManager.host_action("slots", total + 1), 50))
	cfg.add_child(slots_row)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	mode_row.add_child(_fixed(UiKit.label("Mode", 19), 150))
	for m: String in [LobbyState.MODE_ONLINE, LobbyState.MODE_MIXED]:
		var b := UiKit.button("Humans only" if m == LobbyState.MODE_ONLINE else "Humans + bots",
			func() -> void: NetManager.host_action("mode", m), 160)
		b.toggle_mode = true
		b.set_pressed_no_signal(String(lobby["mode"]) == m)
		mode_row.add_child(b)
	cfg.add_child(mode_row)

	if mixed:
		var bot_row := HBoxContainer.new()
		bot_row.add_theme_constant_override("separation", 8)
		bot_row.add_child(UiKit.button("Add bot", func() -> void: NetManager.host_action("add_bot"), 120))
		bot_row.add_child(UiKit.button("Remove bot", func() -> void: NetManager.host_action("remove_bot"), 140))
		bot_row.add_child(UiKit.button("Fill empty slots with bots", func() -> void: NetManager.host_action("fill_bots"), 230))
		cfg.add_child(bot_row)
		cfg.add_child(_choice_row("Bot skill", SKILLS, int(lobby["bot_skill"]), "bot_skill"))

	var sizes: Array[String] = []
	for p: Dictionary in CaveGenerator.SIZE_PRESETS:
		sizes.append(String(p["name"]))
	cfg.add_child(_choice_row("Cave size", sizes, int(lobby["cave_size"]), "cave_size"))

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.add_child(_fixed(UiKit.label("Cave seed", 19), 150))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(lobby["seed"])
	_seed_edit.max_length = 9
	_seed_edit.custom_minimum_size = Vector2(130, 42)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _apply_seed())
	seed_row.add_child(_seed_edit)
	seed_row.add_child(UiKit.button("Set", _apply_seed, 70))
	seed_row.add_child(UiKit.button("Random", func() -> void: NetManager.host_action("random_seed"), 110))
	cfg.add_child(seed_row)

	var regen := CheckButton.new()
	regen.text = "Move regen (+1 Move every %ds)" % int(AppConfig.MOVE_REGEN_INTERVAL)
	regen.button_pressed = bool(lobby["move_regen"])
	regen.toggled.connect(func(on: bool) -> void: NetManager.host_action("move_regen", on))
	cfg.add_child(regen)
	var replace := CheckButton.new()
	replace.text = "A bot takes over anyone who disconnects"
	replace.button_pressed = bool(lobby["replace_disconnected"])
	replace.toggled.connect(func(on: bool) -> void: NetManager.host_action("replace_disconnected", on))
	cfg.add_child(replace)


func _build_guest_view(cfg: VBoxContainer, lobby: Dictionary, mixed: bool) -> void:
	cfg.add_child(UiKit.label("The host sets up the race", 20, UiKit.EMBER))
	var size_name := String(CaveGenerator.SIZE_PRESETS[int(lobby["cave_size"])]["name"])
	var lines := [
		"Mode:  %s" % ("humans and bots" if mixed else "humans only"),
		"Cave:  %s  ·  seed %d" % [size_name, int(lobby["seed"])],
		"Bot skill:  %s" % SKILLS[int(lobby["bot_skill"])] if mixed else "",
		"Move regen:  %s" % ("on" if lobby["move_regen"] else "off"),
		"If someone disconnects:  %s" % ("a bot takes over" if lobby["replace_disconnected"] else "they are out"),
	]
	for line: String in lines:
		if line != "":
			cfg.add_child(UiKit.label(line, 19))


func _choice_row(text: String, names: Array[String], current: int, action: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_fixed(UiKit.label(text, 19), 150))
	for i in names.size():
		var b := UiKit.button(names[i], func() -> void: NetManager.host_action(action, i), 100)
		b.toggle_mode = true
		b.set_pressed_no_signal(i == current)
		row.add_child(b)
	return row


func _apply_seed() -> void:
	var digits := ""
	for ch in _seed_edit.text:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != "":
		NetManager.host_action("seed", int(digits))


func _my_slot(slots: Array) -> Dictionary:
	for s: Dictionary in slots:
		if int(s["id"]) == NetManager.local_peer_id:
			return s
	return {}


# --- Helpers ----------------------------------------------------------------------------

func _panel() -> PanelContainer:
	var centre := CenterContainer.new()
	_body.add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	return panel


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_body.add_child(row)
	return row


func _fixed(c: Control, width: float) -> Control:
	c.custom_minimum_size.x = width
	return c


func _back() -> void:
	if NetManager.in_room():
		NetManager.leave_room()
	if NetManager.state != NetManager.State.OFFLINE:
		NetManager.disconnect_from_server()
	SceneRouter.go_to(SceneRouter.MODE_SELECT)
