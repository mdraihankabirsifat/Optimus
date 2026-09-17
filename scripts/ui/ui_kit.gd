class_name UiKit
extends RefCounted
## Shared look for every menu screen. Screens are assembled in code from these helpers so
## a colour or font size changes in one place, and no screen needs hand-built .tscn layout.

const BG := Color(0.035, 0.03, 0.04)
const PANEL := Color(0.09, 0.075, 0.085, 0.92)
const PANEL_EDGE := Color(0.32, 0.24, 0.18)
const TEXT := Color(0.93, 0.89, 0.83)
const TEXT_DIM := Color(0.62, 0.57, 0.52)
const EMBER := Color(1.0, 0.62, 0.24)
const SKY := Color(0.36, 0.78, 1.0)
const DANGER := Color(1.0, 0.36, 0.3)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)

	var normal := _box(Color(0.14, 0.11, 0.1), PANEL_EDGE, 2)
	var hover := _box(Color(0.24, 0.16, 0.1), EMBER, 2)
	var pressed := _box(Color(0.34, 0.2, 0.1), EMBER, 3)
	var disabled := _box(Color(0.1, 0.09, 0.09), Color(0.2, 0.18, 0.17), 1)
	for style_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = {"normal": normal, "hover": hover, "pressed": pressed,
			"focus": hover, "disabled": disabled}[style_name]
		t.set_stylebox(style_name, "Button", box)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.85))
	t.set_color("font_focus_color", "Button", Color(1, 0.95, 0.85))
	t.set_color("font_pressed_color", "Button", EMBER)
	t.set_font_size("font_size", "Button", 22)

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, PANEL_EDGE, 2, 10))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.06, 0.05, 0.06), PANEL_EDGE, 2))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.06, 0.05, 0.06), EMBER, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)

	var slider_track := StyleBoxFlat.new()
	slider_track.bg_color = Color(0.2, 0.16, 0.14)
	slider_track.content_margin_top = 4
	slider_track.content_margin_bottom = 4
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = EMBER
	slider_fill.content_margin_top = 4
	slider_fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_track)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	return t


static func _box(bg: Color, edge: Color, width: int, radius: int = 6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	return b


## Full-screen root setup: theme, dark background with a warm glow from below.
static func setup_screen(root: Control) -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.25, 0.08, 0.35))
	grad.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 1.1)
	tex.fill_to = Vector2(0.5, 0.1)
	tex.width = 256
	tex.height = 256
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)
	AudioManager.play_music("music_menu")


static func title(text: String, size: int = 72, colour: Color = EMBER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.0))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	return l


## ART-011: the six gravity directions around a cube. Four in the screen plane in ember,
## the two depth axes in sky blue, drawn slightly offset so the mark reads as 3D.
static func logo(size: float = 140.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var t0 := Time.get_ticks_msec()
	c.draw.connect(func() -> void:
		var mid := c.size * 0.5
		var r := size * 0.46
		var pulse := 1.0 + 0.04 * sin(float(Time.get_ticks_msec() - t0) * 0.003)
		for k in 4:
			var d := Vector2.from_angle(float(k) * PI * 0.5 - PI * 0.5)
			var tip := mid + d * r * pulse
			c.draw_line(mid + d * size * 0.16, tip - d * size * 0.08, EMBER, size * 0.05)
			var side := Vector2(-d.y, d.x) * size * 0.07
			c.draw_colored_polygon(PackedVector2Array([tip, tip - d * size * 0.12 + side, tip - d * size * 0.12 - side]), EMBER)
		for k in 2:
			var d := Vector2(-1, -1).normalized() * (1.0 if k == 0 else -1.0)
			var tip := mid + d * r * 0.78 * pulse
			c.draw_line(mid + d * size * 0.16, tip - d * size * 0.07, SKY, size * 0.04)
			var side := Vector2(-d.y, d.x) * size * 0.06
			c.draw_colored_polygon(PackedVector2Array([tip, tip - d * size * 0.11 + side, tip - d * size * 0.11 - side]), SKY)
		var box := Rect2(mid - Vector2.ONE * size * 0.11, Vector2.ONE * size * 0.22)
		c.draw_rect(box, EMBER)
		c.draw_rect(box.grow(-size * 0.05), BG)
		c.queue_redraw())
	return c


static func label(text: String, size: int = 20, colour: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


static func button(text: String, on_press: Callable, min_width: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void: AudioManager.play_sfx("ui_hover", -8.0))
	b.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", -2.0)
		on_press.call())
	return b


## Centred column inside a margin, for menu-style screens.
static func centre_column(root: Control, separation: int = 14) -> VBoxContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", separation)
	centre.add_child(col)
	return col


## A text page with a heading, scrolling rich text and a Back button. How To Play, About
## and Credits are all this.
static func text_page(root: Control, heading: String, bbcode: String) -> void:
	setup_screen(root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 120)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)
	col.add_child(title(heading, 52))

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.text = bbcode
	text.scroll_active = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(text)

	var back := button("Back", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU), 240.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(back)
	back.grab_focus.call_deferred()


## Volume, sensitivity and fullscreen. Used by the Settings screen and the pause menu, so
## changing a setting mid-race never throws the race away.
static func settings_panel() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(540, 0)
	scroll.add_child(col)
	col.add_child(_slider_row("Master volume", "master_volume", 0.0, 1.0))
	col.add_child(_slider_row("Music volume", "music_volume", 0.0, 1.0))
	col.add_child(_slider_row("Effects volume", "sfx_volume", 0.0, 1.0))
	col.add_child(_slider_row("Mouse sensitivity", "sensitivity", 0.2, 3.0))

	col.add_child(_toggle("Invert mouse Y", "invert_y"))

	col.add_child(_toggle("Fullscreen", "fullscreen"))
	if OS.get_name() != "Web":
		var sizes: Array[String] = []
		for r: Vector2i in SettingsManager.RESOLUTIONS:
			sizes.append("%d x %d" % [r.x, r.y])
		col.add_child(_option_row("Window size", "resolution", sizes))
	col.add_child(_option_row("Graphics quality", "graphics_quality", SettingsManager.QUALITY_NAMES))
	col.add_child(_toggle("Head bob", "head_bob"))
	col.add_child(_toggle("Camera shake and hitstop", "camera_effects"))

	col.add_child(label("Controls  (click, then press a key)", 17, TEXT_DIM))
	col.add_child(_remap_grid())

	var feel := label("Playtest tuning  (applies from the next race)", 17, TEXT_DIM)
	col.add_child(feel)
	col.add_child(_slider_row("Gravity turn time", "turn_time", 0.2, 0.6, "%.2fs"))
	col.add_child(_slider_row("Acceleration", "acceleration", 4.0, 30.0, "%.0f"))
	col.add_child(button("Reset tuning to defaults", func() -> void:
		SettingsManager.set_and_save("turn_time", AppConfig.GRAVITY_TRANSITION_TIME)
		SettingsManager.set_and_save("acceleration", AppConfig.ACCELERATION), 300))
	return scroll


## Every control, read from the live InputMap so a remapped key shows its new binding.
## Used by the pause menu and the Settings screen.
static func controls_table() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 6)
	var rows := [
		["Look", "Mouse"],
		["Walk", "%s %s %s %s" % [key_for("move_forward"), key_for("move_left"), key_for("move_back"), key_for("move_right")]],
		["Sprint", key_for("sprint")],
		["Jump (tap for a hop)", key_for("jump")],
		["Gravity Move 90 degrees", "%s + walk key" % key_for("gravity_mod")],
		["Gravity Move 180 degrees", "%s + %s" % [key_for("gravity_mod"), key_for("jump")]],
		["Open mystery box", key_for("interact")],
		["Discovered map", key_for("toggle_map")],
		["Emotes", "%s %s %s" % [key_for("emote_1"), key_for("emote_2"), key_for("emote_3")]],
		["Menu", key_for("pause")],
		["Freedom Duel: Pulse Blaster", "Left mouse"],
		["Freedom Duel: Axis Lock", "Right mouse / Q"],
		["Spectate next racer", key_for("spectate_next")],
		["End race early (offline, once resolved)", key_for("skip_wait")],
	]
	for row: Array in rows:
		grid.add_child(label(String(row[0]), 19, TEXT_DIM))
		grid.add_child(label(String(row[1]), 19, TEXT))
	return grid


## The first key bound to an action, as a player would read it.
static func key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	return "unbound"


static func _option_row(text: String, property: String, names: Array[String]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := label(text, 20)
	name_label.custom_minimum_size = Vector2(200, 0)
	row.add_child(name_label)
	var opt := OptionButton.new()
	for n in names:
		opt.add_item(n)
	opt.selected = clampi(int(SettingsManager.get(property)), 0, names.size() - 1)
	opt.custom_minimum_size = Vector2(220, 40)
	opt.item_selected.connect(func(i: int) -> void: SettingsManager.set_and_save(property, i))
	row.add_child(opt)
	return row


const ACTION_LABELS := {
	"move_forward": "Forward", "move_back": "Back", "move_left": "Left", "move_right": "Right",
	"jump": "Jump / flip", "sprint": "Sprint", "gravity_mod": "Gravity Move",
	"interact": "Open box", "toggle_map": "Map",
}


## Rebindable keys. Taking a key another action uses swaps the two, so nothing is ever
## left unbound. Mouse look, Esc and the emote keys stay fixed.
static func _remap_grid() -> Control:
	var col := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var buttons := {}
	var refresh := func() -> void:
		for action: String in buttons:
			(buttons[action] as Button).text = key_for(action)
	for action: String in SettingsManager.REMAPPABLE:
		grid.add_child(label(String(ACTION_LABELS.get(action, action)), 18, TEXT_DIM))
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 36)
		b.text = key_for(action)
		b.toggle_mode = true
		buttons[action] = b
		grid.add_child(b)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				b.text = "press a key"
			else:
				b.text = key_for(action))
		b.gui_input.connect(func(event: InputEvent) -> void:
			if not b.button_pressed:
				return
			var key := event as InputEventKey
			if key == null or not key.pressed or key.echo:
				return
			b.accept_event()
			if key.physical_keycode != KEY_ESCAPE:
				SettingsManager.remap_action(action, int(key.physical_keycode))
			b.set_pressed_no_signal(false)
			refresh.call())
	col.add_child(button("Reset keys to defaults", func() -> void:
		SettingsManager.reset_keys()
		refresh.call(), 300))
	return col


static func _toggle(text: String, property: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = bool(SettingsManager.get(property))
	b.toggled.connect(func(on: bool) -> void: SettingsManager.set_and_save(property, on))
	return b


static func _slider_row(text: String, property: String, lo: float, hi: float,
		fmt: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := label(text, 20)
	name_label.custom_minimum_size = Vector2(200, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.01 if hi - lo <= 1.0 else 0.05
	slider.value = float(SettingsManager.get(property))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 28)
	row.add_child(slider)

	var value_label := label("", 20, TEXT_DIM)
	value_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(value_label)
	var show := func(v: float) -> void:
		if fmt != "":
			value_label.text = fmt % v
		else:
			value_label.text = ("%d%%" % roundi(v * 100.0)) if hi <= 1.0 else ("%.2fx" % v)
	show.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		show.call(v)
		SettingsManager.set_and_save(property, v))
	return row
