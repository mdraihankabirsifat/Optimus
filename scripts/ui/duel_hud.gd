class_name DuelHUD
extends CanvasLayer
## Everything a local viewer sees and hears of the Freedom Duel: qualification callouts, the
## waiting screen, the duel panel (both finalists' hearts, freedom and locks), the arena
## state (timer, DOF shift, Freedom Core, sudden death), weapon cooldowns, the spectator
## line, shot tracers and the Champion moment. Reads the duel; never changes it.
##
## Laid out in 1080p units and scaled to the window height, so 1280x720 through 1920x1080
## all show the same composition.

const GOLD := Color(1.0, 0.82, 0.35)
const LOCK_COLOUR := Color(0.78, 0.45, 1.0)
const PULSE_COLOUR := Color(0.45, 0.9, 1.0)
const SHIFT_COLOURS := {
	"FULL FREEDOM": Color(0.4, 0.95, 0.5),
	"Y AXIS LOCKED": Color(1.0, 0.45, 0.35),
	"FREEDOM SURGE": Color(0.45, 0.8, 1.0),
}

var _world: Node3D
var _duel: FreedomDuel
var _player: PlayerController
var _race_hud: RaceHUD
var _root: Control
var _draw: Control
var _centre_text := ""
var _centre_sub := ""
var _centre_colour := GOLD
var _centre_timer := 0.0
var _centre_pop := 0.0
var _hit_flash := 0.0
var _hurt_flash := 0.0
var _time := 0.0
var _last_hearts := {}


func setup(world: Node3D, duel: FreedomDuel, player: PlayerController, race_hud: RaceHUD) -> void:
	_world = world
	_duel = duel
	_player = player
	_race_hud = race_hud
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_root.add_child(_draw)

	duel.qualified.connect(_on_qualified)
	duel.phase_changed.connect(_on_phase)
	duel.countdown.connect(_on_countdown)
	duel.shot.connect(_on_shot)
	duel.axis_locked.connect(_on_locked)
	duel.axis_restored.connect(_on_restored)
	duel.lock_resisted.connect(func(t: PlayerController) -> void:
		_centre("IMMUNE", "%s shook off the lock" % t.display_name, LOCK_COLOUR, 1.0, false))
	duel.core_spawned.connect(func(_p: Vector3) -> void:
		AudioManager.play_sfx("core_spawn", -2.0))
	duel.core_captured.connect(_on_core)
	duel.dof_shift.connect(_on_shift)
	duel.dof_shift_ended.connect(func() -> void: AudioManager.play_sfx("axis_restored", -6.0))
	duel.sudden_death_started.connect(func() -> void:
		_centre("SUDDEN DEATH", "TOTAL FREEDOM  -  both finalists 3DOF, shields gone, hits hurt more", UiKit.DANGER, 2.5)
		AudioManager.play_sfx("sudden_death"))
	duel.duel_ended.connect(_on_ended)


# --- Events -------------------------------------------------------------------------

func _on_qualified(body: PlayerController, order: int) -> void:
	AudioManager.play_sfx("qualified", 0.0 if body == _player else -6.0)
	if body == _player:
		if order == 1:
			_centre("QUALIFIED 1ST", "for the Freedom Duel. You start with 3DOF.", GOLD, 3.5)
		else:
			_centre("QUALIFIED 2ND", "for the Freedom Duel. You start with 2DOF and a shield.", GOLD, 3.0)
	elif _race_hud != null:
		_race_hud.toast("%s qualified %s for the Freedom Duel" % [body.display_name, "1st" if order == 1 else "2nd"],
			body.racer_colour, 3.5)


func _on_phase(p: FreedomDuel.Phase) -> void:
	match p:
		FreedomDuel.Phase.INTRO:
			var a := _duel.finalist_a
			var b := _duel.finalist_b
			_centre("FREEDOM DUEL", "%s  vs  %s" % [a.display_name, b.display_name], GOLD, 1.5)
			AudioManager.play_sfx("duel_intro")
			AudioManager.play_music("music_duel", -14.0)
		FreedomDuel.Phase.FIGHT:
			_centre("FIGHT", "", GOLD, 0.8)
			AudioManager.play_sfx("go")
		_:
			pass


func _on_countdown(v: int) -> void:
	if v > 0:
		_centre(str(v), "", GOLD, 0.9, false)
		AudioManager.play_sfx("countdown")


func _on_shot(shooter: PlayerController, kind: String, from: Vector3, to: Vector3, hit: PlayerController) -> void:
	if shooter == null:
		return
	var colour := PULSE_COLOUR if kind == "pulse" else LOCK_COLOUR
	# Start the tracer at the gun, not the eye, so it reads from behind the shooter too.
	var muzzle := from
	if shooter != _player:
		muzzle = shooter.global_position + Vector3(0, 0.9, 0)
	else:
		muzzle = from - Vector3(0, 0.25, 0) + (to - from).normalized() * 0.6
	_tracer(muzzle, to, colour, 0.9 if kind == "pulse" else 1.6)
	var sfx := "blaster" if kind == "pulse" else "lock_fire"
	if shooter == _player:
		AudioManager.play_sfx(sfx, -3.0, 0.05)
	else:
		AudioManager.play_sfx_3d(sfx, shooter.global_position, 0.0)
	if hit == null:
		return
	_spark(to, colour)
	if shooter == _player:
		_hit_flash = 1.0
		AudioManager.play_sfx("duel_hit_confirm", -4.0)
	if hit == _player:
		_hurt_flash = 1.0
		AudioManager.play_sfx("duel_hurt")
	else:
		AudioManager.play_sfx_3d("duel_hurt", hit.global_position, -2.0)


func _on_locked(target: PlayerController, removed: String) -> void:
	AudioManager.play_sfx("lock_hit")
	if target == _player:
		_centre("%s AXIS LOCKED" % removed, "%.0f seconds" % AppConfig.AXIS_LOCK_DURATION, LOCK_COLOUR, 1.4, false)
	else:
		_centre("LOCKED %s" % target.display_name.to_upper(), "%s axis removed" % removed, LOCK_COLOUR, 1.2, false)
	if target != null:
		_ring(target)


func _on_restored(target: PlayerController) -> void:
	if target == _player:
		AudioManager.play_sfx("axis_restored")
		_centre("AXIS RESTORED", "", Color(0.6, 1.0, 0.7), 0.9, false)


func _on_core(body: PlayerController, effect: String) -> void:
	AudioManager.play_sfx("core_capture", 0.0 if body == _player else -4.0)
	var what: String = {"dof": "+1 DOF", "shield": "Shield", "surge": "Speed burst"}.get(effect, "")
	_centre("FREEDOM CORE", "%s: %s" % [body.display_name, what], GOLD, 1.6, false)


func _on_shift(shift: String) -> void:
	AudioManager.play_sfx("dof_shift")
	var sub: String = {
		"FULL FREEDOM": "Everyone moves in 3DOF",
		"Y AXIS LOCKED": "Nobody can jump",
		"FREEDOM SURGE": "Everyone moves faster",
	}.get(shift, "")
	_centre(shift, sub, SHIFT_COLOURS.get(shift, GOLD), 2.0)


func _on_ended(champion: PlayerController, runner: PlayerController, reason: String) -> void:
	AudioManager.stop_music()
	if champion == null:
		return
	if runner != null:
		AudioManager.play_sfx("duel_down")
	AudioManager.play_sfx("champion")
	var sub := "wins the Freedom Duel"
	if runner == null:
		sub = "Champion by default: %s" % reason
	elif reason == "time":
		sub = "wins on hearts when time ran out"
	elif reason == "opponent left":
		sub = "wins: the other finalist left"
	var title := "CHAMPION" if champion != _player else "YOU ARE CHAMPION"
	_centre(title, "%s %s" % [champion.display_name, sub], GOLD, 6.0)
	champion.rig.cheer()
	champion.rig.emote("CHAMPION!")


func _centre(text: String, sub: String, colour: Color, seconds: float, pop: bool = true) -> void:
	_centre_text = text
	_centre_sub = sub
	_centre_colour = colour
	_centre_timer = seconds
	_centre_pop = 1.0 if pop else 0.4


# --- VFX ----------------------------------------------------------------------------

func _tracer(from: Vector3, to: Vector3, colour: Color, width: float) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05 * width, 0.05 * width, length)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(colour, 0.9)
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(beam)
	var mid := (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	beam.global_transform = Transform3D(Basis.looking_at(dir, up), mid)
	var tween := beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.tween_callback(beam.queue_free)


func _spark(at: Vector3, colour: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 18
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mesh.material = mat
	p.mesh = mesh
	_world.add_child(p)
	p.global_position = at
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## A violet ring around a locked fighter's waist while the lock lasts.
func _ring(target: PlayerController) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(LOCK_COLOUR, 0.85)
	ring.material_override = mat
	target.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "rotation:y", TAU * 3.0, AppConfig.AXIS_LOCK_DURATION)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.25, AppConfig.AXIS_LOCK_DURATION)
	tween.tween_callback(ring.queue_free)


# --- Drawing ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_centre_timer = maxf(0.0, _centre_timer - delta)
	_centre_pop = maxf(0.0, _centre_pop - delta * 4.0)
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 2.5)
	visible = _duel.phase != FreedomDuel.Phase.OFF
	_draw.queue_redraw()


func _unit() -> float:
	return _root.get_viewport_rect().size.y / 1080.0


func _on_draw() -> void:
	var s := _unit()
	var vs := _root.get_viewport_rect().size
	var font := _root.get_theme_default_font()
	var local_in_arena := _duel.is_finalist(_player)

	if _hurt_flash > 0.0:
		_draw.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.1, 0.1, 0.22 * _hurt_flash))

	match _duel.phase:
		FreedomDuel.Phase.WAITING:
			if _duel.finalist_a == _player:
				_draw_waiting(font, s, vs)
		FreedomDuel.Phase.INTRO, FreedomDuel.Phase.FIGHT, FreedomDuel.Phase.ENDED:
			_draw_panel(font, s, vs)
			if local_in_arena and _duel.phase == FreedomDuel.Phase.FIGHT:
				_draw_crosshair(s, vs)
				_draw_weapons(font, s, vs)
			elif not local_in_arena:
				var target := _spectated_name()
				var line := "SPECTATING %s    [Tab] switch finalist" % target.to_upper()
				_text(font, line, Vector2(vs.x * 0.5, vs.y - 40.0 * s), 22.0 * s, UiKit.TEXT, true)
		_:
			pass

	if _centre_timer > 0.0 and _centre_text != "":
		var alpha := clampf(_centre_timer / 0.3, 0.0, 1.0)
		var size := (86.0 + 30.0 * _centre_pop) * s
		var y := vs.y * 0.36
		_text(font, _centre_text, Vector2(vs.x * 0.5, y), size, Color(_centre_colour, alpha), true)
		if _centre_sub != "":
			_text(font, _centre_sub, Vector2(vs.x * 0.5, y + 52.0 * s), 28.0 * s, Color(UiKit.TEXT, alpha), true)


func _spectated_name() -> String:
	if _world.has_method("_spectate_target_name"):
		return _world.call("_spectate_target_name")
	return ""


func _draw_waiting(font: Font, s: float, vs: Vector2) -> void:
	var w := 820.0 * s
	var rect := Rect2(Vector2((vs.x - w) * 0.5, 40.0 * s), Vector2(w, 150.0 * s))
	_panel(rect, s)
	_text(font, "QUALIFIED 1ST FOR THE FREEDOM DUEL", rect.position + Vector2(w * 0.5, 50.0 * s), 38.0 * s, GOLD, true)
	var left := maxf(0.0, AppConfig.DUEL_QUALIFY_TIMEOUT - _duel.wait_time)
	var racing := 0
	for r: Dictionary in _duel.mc.racers:
		if r["body"] != _player and not r["finished"] and not r["eliminated"]:
			racing += 1
	_text(font, "Waiting for a second finalist  -  %d still in the cave  -  %ds" % [racing, ceili(left)],
		rect.position + Vector2(w * 0.5, 94.0 * s), 24.0 * s, UiKit.TEXT, true)
	var hint := "You are safe here. Warm up: you will start with 3DOF (move and jump)."
	if _duel.wait_time >= AppConfig.DUEL_SKIP_AFTER and GameState.net_role == "":
		hint = "[Enter] stop waiting and take Champion by default"
	_text(font, hint, rect.position + Vector2(w * 0.5, 128.0 * s), 20.0 * s, UiKit.TEXT_DIM, true)


func _draw_panel(font: Font, s: float, vs: Vector2) -> void:
	var w := 900.0 * s
	var h := 150.0 * s
	var rect := Rect2(Vector2((vs.x - w) * 0.5, 14.0 * s), Vector2(w, h))
	_panel(rect, s)
	var title := "SUDDEN DEATH" if _duel.sudden_death else "FINAL FREEDOM DUEL"
	var title_colour := UiKit.DANGER if _duel.sudden_death else GOLD
	_text(font, title, rect.position + Vector2(w * 0.5, 34.0 * s), 28.0 * s, title_colour, true)
	var clock := MatchController.format_time(_duel.duel_time).substr(0, 4)
	if _duel.phase == FreedomDuel.Phase.INTRO:
		clock = "0:00"
	_text(font, clock, rect.position + Vector2(w * 0.5, 82.0 * s), 40.0 * s, UiKit.TEXT, true)
	_text(font, "VS", rect.position + Vector2(w * 0.5, 118.0 * s), 20.0 * s, UiKit.TEXT_DIM, true)

	_fighter_block(font, _duel.finalist_a, Rect2(rect.position + Vector2(18.0 * s, 48.0 * s), Vector2(w * 0.5 - 90.0 * s, h - 56.0 * s)), false, s)
	_fighter_block(font, _duel.finalist_b, Rect2(rect.position + Vector2(w * 0.5 + 72.0 * s, 48.0 * s), Vector2(w * 0.5 - 90.0 * s, h - 56.0 * s)), true, s)

	# Arena state under the panel: DOF shift and Freedom Core.
	var y := rect.end.y + 26.0 * s
	if _duel.shift_name != "":
		var c: Color = SHIFT_COLOURS.get(_duel.shift_name, GOLD)
		_text(font, "%s  %ds" % [_duel.shift_name, ceili(_duel.shift_left)], Vector2(vs.x * 0.5, y), 26.0 * s, c, true)
		y += 30.0 * s
	var core_text := "FREEDOM CORE ACTIVE" if _duel.core_active else "Freedom Core charging"
	var core_colour := GOLD if _duel.core_active else UiKit.TEXT_DIM
	if _duel.phase == FreedomDuel.Phase.FIGHT:
		var pulse := 0.75 + 0.25 * sin(_time * 6.0) if _duel.core_active else 1.0
		_text(font, core_text, Vector2(vs.x * 0.5, y), 20.0 * s, Color(core_colour, pulse), true)


func _fighter_block(font: Font, body: PlayerController, rect: Rect2, right: bool, s: float) -> void:
	if body == null:
		return
	var st: Dictionary = _duel.fighters.get(body, {})
	var align_x := rect.end.x if right else rect.position.x
	var name := body.display_name
	if body == _player and name != "You":
		name += " (you)"
	var tag := "Q2" if body == _duel.finalist_b else "Q1"
	_text(font, "%s  %s" % [name, tag] if not right else "%s  %s" % [tag, name],
		Vector2(align_x, rect.position.y + 14.0 * s), 24.0 * s, body.racer_colour, false, right)
	# Hearts.
	var hearts := body.health.hearts
	var hx := rect.position.x if not right else rect.end.x - 5.0 * 26.0 * s
	for i in 5:
		var portion := clampf(hearts - float(i), 0.0, 1.0)
		var c := Vector2(hx + (float(i) + 0.5) * 26.0 * s, rect.position.y + 42.0 * s)
		_heart(c, 10.0 * s, portion)
	if body.health.has_shield:
		var sx := hx - 22.0 * s if not right else hx - 22.0 * s
		if not right:
			sx = hx + 5.0 * 26.0 * s + 16.0 * s
		_draw.draw_arc(Vector2(sx, rect.position.y + 42.0 * s), 10.0 * s, 0.0, TAU, 20, Color(0.55, 0.85, 1.0), 3.0 * s)
	# Axis boxes and DOF.
	var axes := _duel.axes_of(body)
	var labels := ["X", "Y", "Z"]
	var colours := [DuelArena.X_COLOUR, DuelArena.Y_COLOUR, DuelArena.Z_COLOUR]
	var bw := 30.0 * s
	var bx := rect.position.x if not right else rect.end.x - (3.0 * (bw + 6.0 * s) + 64.0 * s)
	var by := rect.position.y + 62.0 * s
	for i in 3:
		var box := Rect2(Vector2(bx + float(i) * (bw + 6.0 * s), by), Vector2(bw, bw))
		if axes[i]:
			_draw.draw_rect(box, Color(colours[i], 0.85))
			_text(font, labels[i], box.get_center() + Vector2(0, 7.0 * s), 20.0 * s, Color(0.05, 0.05, 0.08), true)
		else:
			_draw.draw_rect(box, Color(0.2, 0.2, 0.24, 0.8))
			_draw.draw_rect(box, Color(colours[i], 0.35), false, 2.0 * s)
			_draw.draw_line(box.position, box.end, Color(colours[i], 0.5), 2.0 * s)
	var dof := _duel.shown_dof(body) if not st.is_empty() else body.duel_dof
	_text(font, "%dDOF" % dof, Vector2(bx + 3.0 * (bw + 6.0 * s) + 4.0 * s, by + 23.0 * s), 24.0 * s, UiKit.TEXT, false)
	# Status line: lock, immunity, core.
	var status := ""
	var status_colour := UiKit.TEXT_DIM
	if float(st.get("lock_left", 0.0)) > 0.0:
		status = "%s LOCKED %.1fs" % [st.get("removed", ""), st["lock_left"]]
		status_colour = LOCK_COLOUR
	elif float(st.get("core_left", 0.0)) > 0.0:
		status = "CORE +1 DOF %.0fs" % st["core_left"]
		status_colour = GOLD
	elif float(st.get("immune_left", 0.0)) > 0.0:
		status = "lock immune %.1fs" % st["immune_left"]
	if status != "":
		_text(font, status, Vector2(align_x, by + 50.0 * s), 18.0 * s, status_colour, false, right)


func _draw_weapons(font: Font, s: float, vs: Vector2) -> void:
	var st: Dictionary = _duel.fighters.get(_player, {})
	if st.is_empty():
		return
	var w := 240.0 * s
	var gap := 24.0 * s
	var y := vs.y - 86.0 * s
	var x0 := vs.x * 0.5 - w - gap * 0.5
	_weapon_bar(font, Rect2(Vector2(x0, y), Vector2(w, 16.0 * s)), "PULSE BLASTER  [LMB]",
		1.0 - float(st["pulse_cd"]) / AppConfig.PULSE_COOLDOWN, PULSE_COLOUR, s)
	_weapon_bar(font, Rect2(Vector2(x0 + w + gap, y), Vector2(w, 16.0 * s)), "AXIS LOCK  [RMB / Q]",
		1.0 - float(st["lock_cd"]) / AppConfig.AXIS_LOCK_COOLDOWN, LOCK_COLOUR, s)
	var hint := "3DOF: move + jump" if _player.duel_dof >= 3 else ("2DOF: no jump" if _player.duel_dof == 2 else "1DOF: one axis only")
	_text(font, hint, Vector2(vs.x * 0.5, y + 48.0 * s), 18.0 * s, UiKit.TEXT_DIM, true)


func _weapon_bar(font: Font, rect: Rect2, label: String, fill: float, colour: Color, s: float) -> void:
	fill = clampf(fill, 0.0, 1.0)
	_draw.draw_rect(rect.grow(3.0 * s), Color(0, 0, 0, 0.55))
	_draw.draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), Color(colour, 1.0 if fill >= 1.0 else 0.45))
	_text(font, label, rect.position + Vector2(rect.size.x * 0.5, -8.0 * s), 18.0 * s,
		UiKit.TEXT if fill >= 1.0 else UiKit.TEXT_DIM, true)


func _draw_crosshair(s: float, vs: Vector2) -> void:
	var c := vs * 0.5
	var col := Color(1, 1, 1, 0.85)
	if _hit_flash > 0.0:
		col = Color(1.0, 0.4, 0.3, 1.0)
	var r := 9.0 * s + _hit_flash * 6.0 * s
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_draw.draw_line(c + d * r * 0.5, c + d * (r + 8.0 * s), col, 2.0 * s)
	_draw.draw_circle(c, 1.8 * s, col)


func _panel(rect: Rect2, s: float) -> void:
	_draw.draw_rect(rect, Color(0.05, 0.045, 0.06, 0.82))
	_draw.draw_rect(rect, Color(UiKit.PANEL_EDGE, 0.9), false, 2.0 * s)


func _heart(c: Vector2, r: float, portion: float) -> void:
	var off := Color(0.25, 0.22, 0.24)
	_heart_shape(c, r, off)
	if portion > 0.0:
		var col := Color(0.95, 0.25, 0.3)
		if portion < 1.0:
			col = Color(col, 0.55 + 0.45 * portion)
		_heart_shape(c, r * (0.55 + 0.45 * portion), col)


func _heart_shape(c: Vector2, r: float, colour: Color) -> void:
	_draw.draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.55, colour)
	_draw.draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.55, colour)
	_draw.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 1.05, -r * 0.05), c + Vector2(r * 1.05, -r * 0.05), c + Vector2(0, r * 1.0)]), colour)


func _text(font: Font, text: String, at: Vector2, size: float, colour: Color, centred: bool, right: bool = false) -> void:
	var fs := maxi(8, int(size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at
	if centred:
		pos.x -= width * 0.5
	elif right:
		pos.x -= width
	_draw.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 7), Color(0, 0, 0, colour.a * 0.85))
	_draw.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)
