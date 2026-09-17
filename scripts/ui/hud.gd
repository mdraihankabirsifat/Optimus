class_name RaceHUD
extends CanvasLayer
## The racing HUD: hearts, Move charges, timer, DOF, gravity frame, the G-chord preview,
## box results, clues, and spectator state. Reads game state; never changes it.

const HEART_RED := Color(0.95, 0.25, 0.3)
const PIP_ON := Color(0.36, 0.8, 1.0)
const PIP_OFF := Color(0.2, 0.22, 0.26)
## Which action each gravity-preview label stands for; the text shows its current binding.
const PREVIEW_ACTIONS := {"W": "move_forward", "S": "move_back", "A": "move_left", "D": "move_right", "Space": "jump"}

var _world: Node
var _player: PlayerController
var _match: MatchController

var _root: Control
var _stats_draw: Control
var _overlay_draw: Control
var _timer_label: Label
var _status_label: Label
var _dof_label: Label
var _axes_label: Label
var _floor_label: Label
var _centre_label: Label
var _prompt_label: Label
var _banner_label: Label
## Prompt 3: the last-heart deadline and the heart-trade hint.
var _grace_label: Label
var _exchange_hint: Label
var _toasts: VBoxContainer
var _preview: Dictionary = {}

var _flash := Color(0, 0, 0, 0)
var _pip_pulse: Array[float] = []
var _deny_shake: float = 0.0
var _deny_text_timer: float = 0.0
var _centre_timer: float = 0.0
var _clue_dir := Vector3.ZERO
var _clue_vertical: int = 0
var _clue_timer: float = 0.0
var _heart_pulse: float = 0.0
var _last_dof: int = -1
var _dof_pop: float = 0.0
var _last_hearts: float = AppConfig.HEARTS_MAX
var _last_charges: int = AppConfig.MOVE_CHARGES_START
var _go_burst: float = 0.0
var _time: float = 0.0
var _racer_list: VBoxContainer
var _map_open := false


func setup(world: Node, player: PlayerController, match_controller: MatchController) -> void:
	_world = world
	_player = player
	_match = match_controller
	layer = 10

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	_overlay_draw = _full_rect_drawer(_draw_overlay)
	_stats_draw = _full_rect_drawer(_draw_stats)

	_timer_label = _anchored_label(Control.PRESET_CENTER_TOP, 40, Vector2(0, 16))
	_status_label = _anchored_label(Control.PRESET_CENTER_TOP, 17, Vector2(0, 66), UiKit.TEXT_DIM)
	_dof_label = _anchored_label(Control.PRESET_TOP_RIGHT, 44, Vector2(-28, 14), UiKit.SKY)
	_axes_label = _anchored_label(Control.PRESET_TOP_RIGHT, 16, Vector2(-28, 70), UiKit.TEXT_DIM)
	_floor_label = _anchored_label(Control.PRESET_TOP_RIGHT, 18, Vector2(-28, 94))
	_centre_label = _anchored_label(Control.PRESET_CENTER, 110, Vector2(0, -120), UiKit.EMBER)
	_prompt_label = _anchored_label(Control.PRESET_CENTER, 22, Vector2(0, 60), Color(1, 0.9, 0.6))
	_banner_label = _anchored_label(Control.PRESET_CENTER_BOTTOM, 22, Vector2(0, -70))
	_grace_label = _anchored_label(Control.PRESET_CENTER_TOP, 30, Vector2(0, 96), UiKit.DANGER)
	_exchange_hint = _anchored_label(Control.PRESET_TOP_LEFT, 16, Vector2(30, 175), UiKit.SKY)
	_banner_label.add_theme_constant_override("outline_size", 6)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.position.y -= 130
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)

	for key: String in ["W", "A", "S", "D", "Space"]:
		var l := _anchored_label(Control.PRESET_CENTER, 18, Vector2.ZERO, UiKit.SKY)
		l.add_theme_constant_override("outline_size", 6)
		_preview[key] = l

	for i in AppConfig.MOVE_CHARGES_MAX:
		_pip_pulse.append(0.0)

	var g := _player.gravity
	g.shift_started.connect(func(_d: Vector3) -> void:
		_flash = Color(0.4, 0.8, 1.0, 0.18)
		_pip_pulse[g.charges] = 1.0)
	g.shift_denied.connect(_on_shift_denied)
	# FEEL-007: gains pulse too, not only losses.
	g.charges_changed.connect(func(c: int) -> void:
		if c > _last_charges and c - 1 < _pip_pulse.size():
			_pip_pulse[c - 1] = 1.0
		_last_charges = c)
	_player.health.hearts_changed.connect(func(h: float) -> void:
		if h > _last_hearts:
			_heart_pulse = 1.0
			_flash = Color(0.4, 1.0, 0.5, 0.12)
		_last_hearts = h)
	_player.health.second_chance_used.connect(func() -> void:
		_flash = Color(1.0, 0.85, 0.3, 0.35)
		show_centre("SECOND CHANCE", 1.6, Color(1.0, 0.85, 0.35)))
	g.vacuum_recovered.connect(func(_dmg: float) -> void:
		toast("The void spat you back.  -1 heart", UiKit.DANGER))
	_player.health.damaged.connect(func(_a: float, _s: String) -> void:
		_flash = Color(1.0, 0.1, 0.05, 0.35)
		_heart_pulse = 1.0)
	_player.health.shield_absorbed.connect(func() -> void:
		_flash = Color(0.6, 0.9, 1.0, 0.3)
		toast("Shield absorbed the hit", UiKit.SKY))
	_player.health.last_heart_started.connect(func(_s: float) -> void:
		_flash = Color(1.0, 0.1, 0.05, 0.4)
		AudioManager.play_sfx("heartbeat")
		toast("Last heart spent: reach the exit in %d seconds" % int(AppConfig.LAST_HEART_GRACE), UiKit.DANGER, 3.0))
	_player.health.eliminated.connect(func() -> void:
		show_centre("ELIMINATED", 3.0, UiKit.DANGER))
	var interaction := _player.get_node_or_null("Interaction") as PlayerInteraction
	if interaction != null:
		interaction.target_changed.connect(func(p: String) -> void: _prompt_label.text = p)

	_match.countdown_tick.connect(func(v: int) -> void:
		if v > 0:
			show_centre(str(v), 1.0, UiKit.EMBER))
	_match.match_started.connect(func() -> void:
		show_centre("GO!", 0.9, Color(0.5, 1.0, 0.55))
		_go_burst = 1.0)

	_racer_list = VBoxContainer.new()
	_racer_list.position = Vector2(20, 176)
	_racer_list.add_theme_constant_override("separation", 2)
	_racer_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_racer_list)
	_match.racer_finished.connect(func(n: String, place: int, t: float) -> void:
		if n == _player.display_name:
			show_centre("FINISHED  %s" % _ordinal(place), 4.0, UiKit.EMBER)
		else:
			toast("%s found the exit  --  %s  %s" % [n, _ordinal(place), MatchController.format_time(t)],
				UiKit.EMBER))
	_match.racer_eliminated.connect(func(n: String, _t: float) -> void:
		if n != _player.display_name:
			toast("%s was eliminated" % n, UiKit.DANGER))


## Called by GameWorld for boxes, so the HUD never has to find them itself.
func on_box_opened(racer: PlayerController, reward: String, description: String) -> void:
	if racer != _player:
		return
	var colour := UiKit.SKY
	if reward in ["slow", "lose_move"]:
		colour = UiKit.DANGER
	elif reward == "clue":
		colour = UiKit.EMBER
	toast(description, colour, 4.5 if reward == "clue" else 3.0)


func on_clue(racer: PlayerController, direction: Vector3, vertical: int) -> void:
	if racer != _player:
		return
	_clue_dir = direction
	_clue_vertical = vertical
	_clue_timer = AppConfig.CLUE_TIME


func toggle_map() -> void:
	_map_open = not _map_open


func show_centre(text: String, seconds: float, colour: Color = UiKit.EMBER) -> void:
	_centre_label.text = text
	_centre_label.add_theme_color_override("font_color", colour)
	_centre_label.scale = Vector2.ONE * 1.25
	_centre_label.pivot_offset = _centre_label.size * 0.5
	create_tween().tween_property(_centre_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_centre_timer = seconds


func set_banner(text: String) -> void:
	_banner_label.text = text


func toast(text: String, colour: Color = UiKit.TEXT, seconds: float = 3.0) -> void:
	var l := UiKit.label(text, 24, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tween := l.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(l, "modulate:a", 0.0, 0.5)
	tween.tween_callback(l.queue_free)


func _process(delta: float) -> void:
	if _player == null:
		return
	_flash.a = maxf(0.0, _flash.a - delta * 0.9)
	_heart_pulse = maxf(0.0, _heart_pulse - delta * 3.0)
	_deny_shake = maxf(0.0, _deny_shake - delta * 2.5)
	_dof_pop = maxf(0.0, _dof_pop - delta * 3.0)
	for i in _pip_pulse.size():
		_pip_pulse[i] = maxf(0.0, _pip_pulse[i] - delta * 2.2)
	_clue_timer = maxf(0.0, _clue_timer - delta)
	_go_burst = maxf(0.0, _go_burst - delta * 1.4)
	_time += delta
	_update_racer_list()

	if _centre_timer > 0.0:
		_centre_timer -= delta
		if _centre_timer <= 0.0:
			_centre_label.text = ""
	if _deny_text_timer > 0.0:
		_deny_text_timer -= delta
		if _deny_text_timer <= 0.0:
			_status_label.add_theme_color_override("font_color", UiKit.TEXT_DIM)

	if _match.cave_time_limit > 0.0 and not _match.cave_expired:
		var left := maxf(0.0, _match.cave_time_limit - _match.elapsed)
		_timer_label.text = "RUSH  %s" % MatchController.format_time(left)
		_timer_label.add_theme_color_override("font_color", UiKit.DANGER if left <= 30.0 else UiKit.EMBER)
	else:
		_timer_label.text = "Elapsed  %s" % MatchController.format_time(_match.elapsed)
	if _deny_text_timer <= 0.0:
		var active := 0
		for r: Dictionary in _match.racers:
			if not r["finished"] and not r["eliminated"]:
				active += 1
		_status_label.text = "%d of %d racers still searching" % [active, _match.racers.size()]

	var dof: int = _world.player_degrees_of_freedom()
	if dof != _last_dof:
		if _last_dof != -1:
			_dof_pop = 1.0
		_last_dof = dof
	_dof_label.text = "DOF %d" % dof
	_dof_label.scale = Vector2.ONE * (1.0 + 0.25 * _dof_pop)
	_dof_label.pivot_offset = Vector2(_dof_label.size.x, 0)
	_axes_label.text = _axes_text()
	_floor_label.text = "Standing on: %s" % surface_name(_player.gravity.gravity_dir)

	var h := _player.health
	if h.in_grace() and not h.is_eliminated:
		var pulse := 0.7 + 0.3 * sin(_time * 8.0)
		_grace_label.text = "LAST HEART SPENT  -  %ds remaining" % ceili(h.grace_left)
		_grace_label.modulate = Color(1, 1, 1, pulse)
	else:
		_grace_label.text = ""
	_exchange_hint.text = ""
	if _exchange_allowed() and _player.gravity.charges < AppConfig.MOVE_CHARGES_MAX and h.hearts >= AppConfig.HEART_EXCHANGE_COST:
		if _player.gravity.charges == 0:
			_exchange_hint.text = "[%s] trade a heart for a Move" % UiKit.binding_text("exchange_heart")

	_update_preview()
	_stats_draw.queue_redraw()
	_overlay_draw.queue_redraw()


func _update_preview() -> void:
	var armed := _player.gravity_armed and _player.input_enabled
	var g := _player.gravity
	var centre := _root.size * 0.5
	var spots := {"W": Vector2(0, -95), "S": Vector2(0, 95), "A": Vector2(-210, 0), "D": Vector2(210, 0),
		"Space": Vector2(0, 150)}
	var locals := {"W": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "A": Vector3(-1, 0, 0), "D": Vector3(1, 0, 0)}
	for key: String in _preview:
		var l: Label = _preview[key]
		l.visible = armed
		if not armed:
			continue
		var dir: Vector3
		if key == "Space":
			dir = -g.gravity_dir
		else:
			dir = _player.preview_shift_direction(locals[key])
		var verb := "flip to" if key == "Space" else "walk on"
		var label := UiKit.binding_text(PREVIEW_ACTIONS[key]).to_upper()
		l.text = "%s  %s %s" % [label, verb, surface_name(dir)]
		if g.charges <= 0:
			l.text = "%s  no Moves left" % label
			if key == "Space" and _exchange_allowed():
				l.text += "  -  [%s] trade a heart" % UiKit.binding_text("exchange_heart")
		l.add_theme_color_override("font_color", UiKit.SKY if g.charges > 0 else UiKit.DANGER)
		l.position = centre + spots[key] - l.size * 0.5


## UI-011: who is still out there. Finished racers show their place and time; racers still
## searching are listed with their hearts, never with any hint of how close they are.
func _update_racer_list() -> void:
	var rows: Array = []
	for r: Dictionary in _match.racers:
		rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := 0 if a["finished"] else (2 if a["eliminated"] else 1)
		var kb := 0 if b["finished"] else (2 if b["eliminated"] else 1)
		if ka != kb:
			return ka < kb
		if ka == 0:
			return int(a["place"]) < int(b["place"])
		return String(a["name"]) < String(b["name"]))
	while _racer_list.get_child_count() < rows.size():
		var l := UiKit.label("", 16)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		_racer_list.add_child(l)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var body := r["body"] as PlayerController
		var l := _racer_list.get_child(i) as Label
		var status := ""
		if r["finished"]:
			status = "%s  %s" % [_ordinal(int(r["place"])), MatchController.format_time(float(r["finish_time"]))]
		elif r["eliminated"]:
			status = "out"
		elif is_instance_valid(body):
			status = "%.1f hearts" % body.health.hearts
		var marker := "> " if body == _player else "   "
		l.text = "%s%s   %s" % [marker, r["name"], status]
		var colour: Color = body.racer_colour if is_instance_valid(body) else UiKit.TEXT
		l.add_theme_color_override("font_color", colour.darkened(0.45) if r["eliminated"] else colour)


func _axes_text() -> String:
	if _world.graph == null:
		return ""
	var c: Vector3i = _world.player_cell()
	if not _world.graph.has_cell(c):
		return ""
	var names: Array[String] = []
	var g: CaveGraph = _world.graph
	if g.is_linked(c, CaveGraph.DIR_PLUS_X) or g.is_linked(c, CaveGraph.DIR_MINUS_X):
		names.append("east-west")
	if g.is_linked(c, CaveGraph.DIR_PLUS_Z) or g.is_linked(c, CaveGraph.DIR_MINUS_Z):
		names.append("north-south")
	if g.is_linked(c, CaveGraph.DIR_UP) or g.is_linked(c, CaveGraph.DIR_DOWN):
		names.append("up-down")
	return "  ·  ".join(names)


## The surface you stand on when gravity points this way.
static func surface_name(dir: Vector3) -> String:
	if dir.is_equal_approx(Vector3.DOWN): return "the ground"
	if dir.is_equal_approx(Vector3.UP): return "the ceiling"
	if dir.is_equal_approx(Vector3.RIGHT): return "the east wall"
	if dir.is_equal_approx(Vector3.LEFT): return "the west wall"
	if dir.is_equal_approx(Vector3.FORWARD): return "the north wall"
	if dir.is_equal_approx(Vector3.BACK): return "the south wall"
	return "?"


func _on_shift_denied(reason: String) -> void:
	# Denial must never be silent, or players assume the game is broken.
	if reason == "transitioning":
		return
	_deny_shake = 1.0
	_deny_text_timer = 1.4
	_flash = Color(1.0, 0.2, 0.1, 0.2)
	_status_label.text = "NO MOVES LEFT" if reason == "no_charges" else "Already falling that way"
	_status_label.add_theme_color_override("font_color", UiKit.DANGER)


# --- Drawing ----------------------------------------------------------------------

func _draw_stats(c: Control) -> void:
	var h := _player.health
	var origin := Vector2(34, 40)
	var beat := 1.0 + 0.18 * _heart_pulse
	for i in int(AppConfig.HEARTS_MAX):
		var centre := origin + Vector2(i * 44, 0)
		_draw_heart(c, centre, 16.0 * beat, Color(0.16, 0.08, 0.09), 1.0)
		var fill := clampf(h.hearts - float(i), 0.0, 1.0)
		if fill >= 1.0:
			_draw_heart(c, centre, 16.0 * beat, HEART_RED, 1.0)
		elif fill >= 0.5:
			_draw_heart(c, centre, 16.0 * beat, HEART_RED, 0.5)
	if h.has_second_chance:
		var sc := origin + Vector2(int(AppConfig.HEARTS_MAX) * 44 + (34 if h.has_shield else 0), 0)
		c.draw_arc(sc, 15, 0, TAU, 24, Color(1.0, 0.85, 0.35), 3.0)
		c.draw_string(ThemeDB.fallback_font, sc + Vector2(-9, 6), "2nd",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.35))
	if h.has_shield:
		c.draw_arc(origin + Vector2(int(AppConfig.HEARTS_MAX) * 44, 0), 15, 0, TAU, 24, UiKit.SKY, 3.0)
		c.draw_string(ThemeDB.fallback_font, origin + Vector2(int(AppConfig.HEARTS_MAX) * 44 - 5, 6),
			"S", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.SKY)

	var g := _player.gravity
	var shake := Vector2(sin(Time.get_ticks_msec() * 0.08) * 8.0 * _deny_shake, 0)
	var pip_origin := Vector2(34, 96) + shake
	c.draw_string(ThemeDB.fallback_font, pip_origin + Vector2(-14, -22), "GRAVITY MOVES",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.TEXT_DIM)
	var shown: int = maxi(AppConfig.MOVE_CHARGES_START, g.charges)
	for i in shown:
		var p := pip_origin + Vector2(i * 36, 0)
		var on := i < g.charges
		var col := PIP_ON if on else PIP_OFF
		if not on and _deny_shake > 0.0:
			col = PIP_OFF.lerp(UiKit.DANGER, _deny_shake)
		var s := 12.0 + 8.0 * _pip_pulse[i]
		var diamond := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.75, 0),
			p + Vector2(0, s), p + Vector2(-s * 0.75, 0)])
		if _pip_pulse[i] > 0.0:
			var ring := Color(PIP_ON, _pip_pulse[i])
			c.draw_arc(p, 14.0 + 18.0 * (1.0 - _pip_pulse[i]), 0, TAU, 20, ring, 2.0)
		c.draw_colored_polygon(diamond, col)

	var effects := ""
	if _player.speed_effect_remaining() > 0.0:
		effects = ("FAST  %ds" if _player.speed_multiplier > 1.0 else "SLOWED  %ds") \
			% ceili(_player.speed_effect_remaining())
	if effects != "":
		c.draw_string(ThemeDB.fallback_font, Vector2(20, 140), effects, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 18, UiKit.SKY if _player.speed_multiplier > 1.0 else UiKit.DANGER)

	_draw_gravity_gauge(c, Vector2(c.size.x - 70, 190))
	_draw_compass(c, Vector2(c.size.x - 70, 300))


## A ring showing where the world's own floor is, from your point of view. When you are
## walking on a wall, the arrow points sideways -- the private frame, made visible.
func _draw_gravity_gauge(c: Control, centre: Vector2) -> void:
	c.draw_circle(centre, 40, Color(0, 0, 0, 0.45))
	c.draw_arc(centre, 40, 0, TAU, 32, Color(UiKit.SKY, 0.5), 2.0)
	var cam := _player.camera.global_basis
	var world_down := cam.inverse() * Vector3.DOWN
	var flat := Vector2(world_down.x, -world_down.y)
	var tip := centre + flat * 30.0
	if flat.length() > 0.15:
		c.draw_line(centre, tip, UiKit.EMBER, 4.0)
		c.draw_circle(tip, 5, UiKit.EMBER)
	else:
		# World down is straight ahead or behind you.
		c.draw_circle(centre, 7 if world_down.z < 0 else 4, UiKit.EMBER)
	c.draw_string(ThemeDB.fallback_font, centre + Vector2(-44, 60), "world floor",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.TEXT_DIM)


## Prompt 3: a compass fixed to the WORLD, deliberately. North is -Z, east +X, whatever
## gravity you are under: turning your gravity never renames the directions, and a wall or
## ceiling walker facing the same world direction reads the same bearing. This is the one
## place world axes are the point, so it stays in the HUD and never feeds movement. It shows
## only your own facing -- never the exit.
func _draw_compass(c: Control, centre: Vector2) -> void:
	var heading := compass_heading(_view_camera(), _last_bearing)
	_last_bearing = heading["bearing"]
	var bearing: float = heading["bearing"]
	c.draw_circle(centre, 40, Color(0, 0, 0, 0.45))
	c.draw_arc(centre, 40, 0, TAU, 32, Color(UiKit.EMBER, 0.45), 2.0)
	var font := ThemeDB.fallback_font
	var labels := {"N": 0.0, "E": 90.0, "S": 180.0, "W": 270.0}
	for name: String in labels:
		# Screen angle: your facing is always at the top.
		var a := deg_to_rad(float(labels[name]) - bearing)
		var p := centre + Vector2(sin(a), -cos(a)) * 29.0
		var colour := UiKit.DANGER if name == "N" else UiKit.TEXT
		c.draw_string(font, p + Vector2(-5, 6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
	c.draw_line(centre + Vector2(0, -12), centre + Vector2(0, -40), Color(UiKit.EMBER, 0.9), 2.0)
	var caption := "%s  %03d" % [bearing_name(bearing), roundi(bearing) % 360]
	if heading["vertical"] != "":
		caption = "looking %s" % heading["vertical"]
	c.draw_string(font, centre + Vector2(-44, 60), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.TEXT_DIM)


var _last_bearing: float = 0.0


func _view_camera() -> Camera3D:
	var cam := _root.get_viewport().get_camera_3d()
	return cam if cam != null else _player.camera


## {bearing: degrees clockwise from world north (-Z), vertical: "" or "up"/"down"}.
## Looking almost straight up or down there is no reliable heading, so the last one is kept.
static func compass_heading(cam: Camera3D, last_bearing: float) -> Dictionary:
	var fwd := -cam.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	if flat.length() < 0.2:
		return {"bearing": last_bearing, "vertical": "up" if fwd.y > 0.0 else "down"}
	var bearing := rad_to_deg(atan2(flat.x, -flat.y))
	return {"bearing": fposmod(bearing, 360.0), "vertical": ""}


static func bearing_name(bearing: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[roundi(fposmod(bearing, 360.0) / 45.0) % 8]


func _draw_heart(c: Control, centre: Vector2, size: float, colour: Color, portion: float) -> void:
	var pts := PackedVector2Array()
	var steps := 28
	var t_start := PI if portion < 1.0 else 0.0
	for i in steps + 1:
		var t := lerpf(t_start, TAU, float(i) / float(steps))
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(centre + Vector2(x, -y) * (size / 17.0))
	c.draw_colored_polygon(pts, colour)


func _draw_overlay(c: Control) -> void:
	if _flash.a > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), _flash)
	_draw_low_health(c)
	_draw_speed_lines(c)
	if _go_burst > 0.0:
		var r := (1.0 - _go_burst) * c.size.length() * 0.6
		c.draw_arc(c.size * 0.5, r, 0, TAU, 64, Color(0.5, 1.0, 0.55, _go_burst * 0.8), 10.0 * _go_burst + 2.0)
	var mid := c.size * 0.5
	if _player.input_enabled:
		var ch := Color(1, 1, 1, 0.8)
		c.draw_line(mid + Vector2(-9, 0), mid + Vector2(-3, 0), ch, 2.0)
		c.draw_line(mid + Vector2(3, 0), mid + Vector2(9, 0), ch, 2.0)
		c.draw_line(mid + Vector2(0, -9), mid + Vector2(0, -3), ch, 2.0)
		c.draw_line(mid + Vector2(0, 3), mid + Vector2(0, 9), ch, 2.0)
	if _player.gravity_armed and _player.input_enabled:
		c.draw_arc(mid, 60, 0, TAU, 40, Color(UiKit.SKY, 0.6), 2.0)
	if _clue_timer > 0.0:
		_draw_clue(c, Vector2(mid.x, 150))
	if _map_open:
		_draw_map(c)


## UI-015: a top-down map of your current level, drawn only from cells you have stood in and
## the openings you saw from them. The exit is never marked, even if you walked through it.
func _draw_map(c: Control) -> void:
	var visited: Dictionary = _world.visited_cells
	var g: CaveGraph = _world.graph
	var here: Vector3i = _world.player_cell()
	var cell_px := 34.0
	var panel := Rect2(c.size.x - 320, c.size.y - 330, 300, 310)
	c.draw_rect(panel, Color(0.05, 0.04, 0.05, 0.82))
	c.draw_rect(panel, Color(UiKit.PANEL_EDGE, 1.0), false, 2.0)
	var levels := {}
	for cell: Vector3i in visited:
		levels[cell.y] = true
	c.draw_string(ThemeDB.fallback_font, panel.position + Vector2(12, 22),
		"MAP  ·  level %d  ·  %d cells found  [%s]" % [here.y + 1, visited.size(), UiKit.binding_text("toggle_map")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.TEXT_DIM)
	var origin := panel.position + panel.size * 0.5 + Vector2(0, 14) - Vector2(here.x, here.z) * cell_px
	for cell: Vector3i in visited:
		if cell.y != here.y:
			continue
		var p := origin + Vector2(cell.x, cell.z) * cell_px
		if not panel.grow(-8).has_point(p):
			continue
		var box := Rect2(p - Vector2.ONE * cell_px * 0.34, Vector2.ONE * cell_px * 0.68)
		c.draw_rect(box, Color(0.45, 0.4, 0.34, 0.9))
		for d: int in CaveGraph.FLAT_DIRS:
			if g.is_linked(cell, d):
				var dv := Vector2(CaveGraph.DIRS[d].x, CaveGraph.DIRS[d].z)
				c.draw_line(p + dv * cell_px * 0.34, p + dv * cell_px * 0.5, Color(0.45, 0.4, 0.34, 0.9), cell_px * 0.3)
		if g.is_linked(cell, CaveGraph.DIR_UP):
			c.draw_string(ThemeDB.fallback_font, p + Vector2(-5, -1), "^", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.SKY)
		if g.is_linked(cell, CaveGraph.DIR_DOWN):
			c.draw_string(ThemeDB.fallback_font, p + Vector2(-4, 12), "v", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.SKY)
		if cell == g.spawn_cell:
			c.draw_circle(p, 4, UiKit.TEXT_DIM)
	var me := origin + Vector2(here.x, here.z) * cell_px
	var look := -_player.camera.global_basis.z
	var f := Vector2(look.x, look.z)
	f = f.normalized() if f.length() > 0.05 else Vector2(0, -1)
	var side := Vector2(-f.y, f.x)
	c.draw_colored_polygon(PackedVector2Array([me + f * 11, me - f * 7 + side * 7, me - f * 7 - side * 7]), UiKit.SKY)
	c.draw_string(ThemeDB.fallback_font, panel.position + Vector2(12, panel.size.y - 10),
		"N ^    other levels: %d" % maxi(0, levels.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.TEXT_DIM)


## HEALTH-006: red creeping in from the edges, breathing with the heartbeat.
func _draw_low_health(c: Control) -> void:
	var h := _player.health
	if h.is_eliminated or h.hearts > AppConfig.LOW_HEALTH:
		return
	var beat := 0.5 + 0.5 * pow(absf(sin(_time * (3.6 if h.hearts <= 0.5 else 2.8))), 6.0)
	var a := (0.35 if h.hearts <= 0.5 else 0.22) * (0.6 + 0.4 * beat)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.35, 0.35, 0.35, 0.08))
	var s := c.size
	var depth := minf(s.x, s.y) * 0.22
	var edge := Color(0.75, 0.0, 0.05, a)
	var clear := Color(0.75, 0.0, 0.05, 0.0)
	var o := [Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]
	var i := [Vector2(depth, depth), Vector2(s.x - depth, depth), Vector2(s.x - depth, s.y - depth), Vector2(depth, s.y - depth)]
	for k in 4:
		var n := (k + 1) % 4
		c.draw_polygon(PackedVector2Array([o[k], o[n], i[n], i[k]]),
			PackedColorArray([edge, edge, clear, clear]))


## VFX-003: streaks at the edges once you are moving faster than a sprint.
func _draw_speed_lines(c: Control) -> void:
	if not _player.input_enabled:
		return
	var up := _player.gravity.local_up()
	var speed := (_player.velocity - up * _player.velocity.dot(up)).length()
	var fall := absf(_player.velocity.dot(up))
	var amount := clampf((maxf(speed, fall * 0.6) - AppConfig.SPRINT_SPEED * 1.05) / 6.0, 0.0, 1.0)
	if amount <= 0.0:
		return
	var mid := c.size * 0.5
	var reach := c.size.length() * 0.5
	for k in 28:
		var ang := float(k) * 2.39996 + floorf(_time * 20.0 + float(k)) * 0.37
		var dir := Vector2(cos(ang), sin(ang))
		var start := 0.62 + 0.25 * fmod(float(k) * 0.618 + _time * 3.0, 1.0)
		var p0 := mid + dir * reach * start
		var p1 := mid + dir * reach * minf(1.1, start + 0.18 * amount)
		c.draw_line(p0, p1, Color(1, 1, 1, 0.22 * amount), 2.0)


func _draw_clue(c: Control, at: Vector2) -> void:
	var alpha := clampf(_clue_timer, 0.0, 1.0)
	var local := _player.camera.global_basis.inverse() * _clue_dir
	var angle := atan2(local.x, -local.z)
	var fwd := Vector2(sin(angle), -cos(angle))
	var side := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([at + fwd * 34, at - fwd * 18 + side * 20, at - fwd * 18 - side * 20])
	c.draw_circle(at, 46, Color(0, 0, 0, 0.5 * alpha))
	c.draw_colored_polygon(tri, Color(UiKit.EMBER, alpha))
	var extra := " (above)" if _clue_vertical > 0 else (" (below)" if _clue_vertical < 0 else "")
	c.draw_string(ThemeDB.fallback_font, at + Vector2(-150, 70), "exit this way" + extra,
		HORIZONTAL_ALIGNMENT_CENTER, 300, 16, Color(UiKit.EMBER, alpha))


func _full_rect_drawer(fn: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn.bind(c))
	_root.add_child(c)
	return c


func _anchored_label(preset: Control.LayoutPreset, size: int, offset: Vector2,
		colour: Color = UiKit.TEXT) -> Label:
	var l := UiKit.label("", size, colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", maxi(4, size / 7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	match preset:
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER:
			l.grow_horizontal = Control.GROW_DIRECTION_BOTH
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Control.PRESET_TOP_RIGHT:
			l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if preset == Control.PRESET_CENTER:
		l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.position += offset
	return l


static func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n


## Heart trading is a cave action, switched off by Move regeneration.
func _exchange_allowed() -> bool:
	return not bool(_world.get("_move_regen")) and _match.phase == MatchController.Phase.RACING 		and _player.input_enabled and not _player.health.is_eliminated and _player.duel_dof == 0
