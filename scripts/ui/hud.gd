class_name RaceHUD
extends CanvasLayer
## The racing HUD: hearts, Move charges, timer, DOF, gravity frame, the G-chord preview,
## box results, clues, and spectator state. Reads game state; never changes it.

const HEART_RED := Color(0.95, 0.25, 0.3)
const PIP_ON := Color(0.36, 0.8, 1.0)
const PIP_OFF := Color(0.2, 0.22, 0.26)

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
	g.vacuum_recovered.connect(func(_dmg: float) -> void:
		toast("The void spat you back.  -1 heart", UiKit.DANGER))
	_player.health.damaged.connect(func(_a: float, _s: String) -> void:
		_flash = Color(1.0, 0.1, 0.05, 0.35)
		_heart_pulse = 1.0)
	_player.health.shield_absorbed.connect(func() -> void:
		_flash = Color(0.6, 0.9, 1.0, 0.3)
		toast("Shield absorbed the hit", UiKit.SKY))
	_player.health.eliminated.connect(func() -> void:
		show_centre("ELIMINATED", 3.0, UiKit.DANGER))
	var interaction := _player.get_node_or_null("Interaction") as PlayerInteraction
	if interaction != null:
		interaction.target_changed.connect(func(p: String) -> void: _prompt_label.text = p)

	_match.countdown_tick.connect(func(v: int) -> void:
		if v > 0:
			show_centre(str(v), 1.0, UiKit.EMBER))
	_match.match_started.connect(func() -> void: show_centre("GO!", 0.9, Color(0.5, 1.0, 0.55)))
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

	if _centre_timer > 0.0:
		_centre_timer -= delta
		if _centre_timer <= 0.0:
			_centre_label.text = ""
	if _deny_text_timer > 0.0:
		_deny_text_timer -= delta
		if _deny_text_timer <= 0.0:
			_status_label.add_theme_color_override("font_color", UiKit.TEXT_DIM)

	_timer_label.text = MatchController.format_time(_match.elapsed)
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
		l.text = "%s  %s %s" % ["SPACE" if key == "Space" else key, verb, surface_name(dir)]
		if g.charges <= 0:
			l.text = "%s  no Moves left" % ("SPACE" if key == "Space" else key)
		l.add_theme_color_override("font_color", UiKit.SKY if g.charges > 0 else UiKit.DANGER)
		l.position = centre + spots[key] - l.size * 0.5


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
