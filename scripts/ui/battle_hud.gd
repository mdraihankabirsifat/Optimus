class_name BattleHUD
extends CanvasLayer
## Master Prompt 4: what a racer sees of Battle Mode -- the live scoreboard, a crosshair, the
## blaster cooldown, the kill feed (through the race HUD's toasts), the respawn countdown and
## the final result. Reads BattleMode; never changes it. Scaled to the window height like the
## duel HUD so 1280x720 to 1920x1080 look the same.

const PULSE_COLOUR := Color(0.45, 0.9, 1.0)

var _world: Node3D
var _battle: BattleMode
var _player: PlayerController
var _race_hud: RaceHUD
var _root: Control
var _draw: Control
var _hit_flash := 0.0
var _hurt_flash := 0.0
var _result_text := ""
var _result_sub := ""


func setup(world: Node3D, battle: BattleMode, player: PlayerController, race_hud: RaceHUD) -> void:
	_world = world
	_battle = battle
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

	battle.shot.connect(_on_shot)
	battle.killed.connect(_on_killed)
	battle.respawned.connect(func(body: PlayerController, _p: Vector3) -> void:
		if body == _player:
			AudioManager.play_sfx("go", -6.0)
			_race_hud.show_centre("BACK IN", 0.8, UiKit.SKY))
	battle.battle_over.connect(_on_over)
	world.match_controller.match_started.connect(func() -> void:
		_race_hud.show_centre("BATTLE!", 1.2, UiKit.EMBER))


func _on_shot(shooter: PlayerController, from: Vector3, to: Vector3, hit: PlayerController) -> void:
	if shooter == null:
		return
	var muzzle := from if shooter != _player else from - Vector3(0, 0.25, 0) + (to - from).normalized() * 0.6
	_tracer(muzzle if shooter == _player else shooter.global_position + Vector3(0, 0.9, 0), to)
	if shooter == _player:
		AudioManager.play_sfx("blaster", -3.0, 0.05)
	else:
		AudioManager.play_sfx_3d("blaster", shooter.global_position, 0.0)
	if hit == _player:
		_hurt_flash = 1.0
		AudioManager.play_sfx("duel_hurt")
	elif hit != null and shooter == _player:
		_hit_flash = 1.0
		AudioManager.play_sfx("duel_hit_confirm", -4.0)


func _on_killed(killer: PlayerController, victim: PlayerController) -> void:
	if victim == null:
		return
	var line := "%s eliminated %s" % [killer.display_name, victim.display_name] if killer != null and killer != victim \
		else "%s was knocked out by the cave" % victim.display_name
	_race_hud.toast(line, killer.racer_colour if killer != null else UiKit.TEXT_DIM, 2.5)
	if victim == _player:
		AudioManager.play_sfx("duel_down", -4.0)
	elif killer == _player:
		AudioManager.play_sfx("qualified", -6.0)


func _on_over(ranking: Array, draw: bool) -> void:
	AudioManager.play_sfx("champion", -4.0)
	if ranking.is_empty():
		return
	_result_text = "DRAW" if draw else "%s WINS" % String(ranking[0]["name"]).to_upper()
	_result_sub = "Battle Mode result: %d kills" % int(ranking[0].get("battle_score", 0))


func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 2.5)
	_draw.queue_redraw()


func _on_draw() -> void:
	var s := _root.get_viewport_rect().size.y / 1080.0
	var vs := _root.get_viewport_rect().size
	var font := _root.get_theme_default_font()
	if _hurt_flash > 0.0:
		_draw.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.1, 0.1, 0.2 * _hurt_flash))

	# Scoreboard, where the racer list usually is.
	var ranking := _battle.build_ranking()
	var x := 30.0 * s
	var y := 270.0 * s
	_text(font, "SCOREBOARD   kills / deaths", Vector2(x, y), 18.0 * s, UiKit.TEXT_DIM)
	for i in ranking.size():
		var r: Dictionary = ranking[i]
		var body := r["body"] as PlayerController
		var st: Dictionary = _battle.fighters.get(body, {})
		y += 30.0 * s
		var name := String(r["name"])
		var status := ""
		if st.get("dead", false):
			status = "  (respawning)"
		var colour: Color = body.racer_colour if is_instance_valid(body) else UiKit.TEXT
		_text(font, "%d. %s   %d / %d%s" % [i + 1, name, int(st.get("score", 0)), int(st.get("deaths", 0)), status],
			Vector2(x, y), (24.0 if body == _player else 21.0) * s, colour)

	var mine: Dictionary = _battle.fighters.get(_player, {})
	if mine.get("dead", false):
		_text_c(font, "ELIMINATED", Vector2(vs.x * 0.5, vs.y * 0.42), 72.0 * s, UiKit.DANGER)
		_text_c(font, "respawning in %d" % ceili(float(mine.get("respawn_left", 0.0))), Vector2(vs.x * 0.5, vs.y * 0.42 + 56.0 * s), 30.0 * s, UiKit.TEXT)
	elif _world.match_controller.phase == MatchController.Phase.RACING:
		_crosshair(vs, s)
		if float(mine.get("protect_left", 0.0)) > 0.0:
			_text_c(font, "spawn protection", Vector2(vs.x * 0.5, vs.y * 0.5 + 60.0 * s), 20.0 * s, UiKit.SKY)
		var cd := float(mine.get("pulse_cd", 0.0))
		var w := 240.0 * s
		var bar := Rect2(Vector2(vs.x * 0.5 - w * 0.5, vs.y - 150.0 * s), Vector2(w, 12.0 * s))
		var fill := 1.0 - clampf(cd / AppConfig.PULSE_COOLDOWN, 0.0, 1.0)
		_draw.draw_rect(bar.grow(3.0 * s), Color(0, 0, 0, 0.5))
		_draw.draw_rect(Rect2(bar.position, Vector2(w * fill, bar.size.y)), Color(PULSE_COLOUR, 1.0 if fill >= 1.0 else 0.45))
		_text_c(font, "PULSE BLASTER  [%s]" % UiKit.binding_text("duel_fire"), bar.position + Vector2(w * 0.5, -8.0 * s), 17.0 * s, UiKit.TEXT)

	if _result_text != "":
		_text_c(font, _result_text, Vector2(vs.x * 0.5, vs.y * 0.36), 80.0 * s, UiKit.EMBER)
		_text_c(font, _result_sub, Vector2(vs.x * 0.5, vs.y * 0.36 + 54.0 * s), 26.0 * s, UiKit.TEXT)


func _crosshair(vs: Vector2, s: float) -> void:
	var c := vs * 0.5
	var col := Color(1.0, 0.4, 0.3) if _hit_flash > 0.0 else Color(1, 1, 1, 0.85)
	var r := 9.0 * s + _hit_flash * 6.0 * s
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_draw.draw_line(c + d * r * 0.5, c + d * (r + 8.0 * s), col, 2.0 * s)


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.045, length)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(PULSE_COLOUR, 0.9)
	beam.material_override = mat
	_world.add_child(beam)
	var dir := (to - from).normalized()
	beam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT), (from + to) * 0.5)
	var tween := beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.tween_callback(beam.queue_free)


func _text(font: Font, text: String, at: Vector2, size: float, colour: Color) -> void:
	var fs := maxi(8, int(size))
	_draw.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 7), Color(0, 0, 0, 0.85))
	_draw.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)


func _text_c(font: Font, text: String, at: Vector2, size: float, colour: Color) -> void:
	var fs := maxi(8, int(size))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(font, text, at - Vector2(w * 0.5, 0.0), size, colour)
