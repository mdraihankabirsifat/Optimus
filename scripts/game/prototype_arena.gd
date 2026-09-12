extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ENERGY_SCENE: PackedScene = preload("res://scenes/game/energy_node.tscn")
const HAZARD_SCENE: PackedScene = preload("res://scenes/game/hazard.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")

var players: Array[DOFPlayer] = []
var scores: Array[int] = [0, 0]
var time_remaining: float = 60.0
var game_finished: bool = false
var pause_menu: PauseMenu
var hud_labels: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	time_remaining = float(GameManager.difficulty_data().duration)
	queue_redraw()
	_spawn_players()
	_spawn_hazards()
	_spawn_energy()
	_build_hud()

func _process(delta: float) -> void:
	if game_finished:
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	_update_hud()
	if time_remaining <= 0.0:
		_finish_game("TEST WINDOW COMPLETE")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not game_finished:
		if get_tree().paused:
			_resume()
		else:
			_pause()

func _spawn_players() -> void:
	for index: int in 2:
		var player := PLAYER_SCENE.instantiate() as DOFPlayer
		player.player_id = index + 1
		player.dof = index + 1
		player.player_color = UIFactory.CYAN if index == 0 else UIFactory.ORANGE
		player.move_speed *= float(GameManager.difficulty_data().speed_scale)
		player.position = Vector2(260 if index == 0 else 1020, 390)
		player.health_changed.connect(_on_health_changed)
		add_child(player)
		players.append(player)

func _spawn_hazards() -> void:
	var count := int(GameManager.LEVELS[GameManager.selected_level - 1].hazard_count)
	var positions: Array[Vector2] = [Vector2(640, 390), Vector2(470, 520), Vector2(810, 260)]
	for index: int in count:
		var hazard := HAZARD_SCENE.instantiate() as ArenaHazard
		hazard.position = positions[index]
		hazard.damage = int(GameManager.difficulty_data().hazard_damage)
		add_child(hazard)

func _spawn_energy() -> void:
	if game_finished:
		return
	var energy := ENERGY_SCENE.instantiate() as EnergyNode
	energy.position = Vector2(rng.randf_range(100.0, 1180.0), rng.randf_range(190.0, 625.0))
	energy.collected.connect(_on_energy_collected)
	add_child(energy)

func _on_energy_collected(player_id: int) -> void:
	scores[player_id - 1] += 10
	_update_hud()
	get_tree().create_timer(0.35).timeout.connect(_spawn_energy)

func _on_health_changed(_player_id: int, health: int) -> void:
	_update_hud()
	if health <= 0:
		_finish_game("ROBOT DISABLED")

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var top := PanelContainer.new()
	top.position = Vector2(28, 20)
	top.size = Vector2(1224, 104)
	top.add_theme_stylebox_override("panel", UIFactory.panel_style(Color("0d1a2c"), 10, Color("244d6a")))
	layer.add_child(top)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 34)
	top.add_child(row)
	for key: String in ["p1", "center", "p2"]:
		var label := UIFactory.make_label("", 17)
		label.custom_minimum_size.x = 330 if key != "center" else 380
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(label)
		hud_labels[key] = label
	var hint := UIFactory.make_label("P1  A/D · W/S · Q/E        P2  ARROWS · ,/.        ESC  PAUSE & DOF TOOLS", 14, UIFactory.MUTED)
	hint.position = Vector2(265, 680)
	layer.add_child(hint)
	_update_hud()

func _update_hud() -> void:
	if players.size() < 2 or hud_labels.is_empty():
		return
	(hud_labels.p1 as Label).text = "PLAYER 1  //  %d DOF\nHEALTH %03d    SCORE %03d" % [players[0].dof, players[0].health, scores[0]]
	(hud_labels.center as Label).text = "%s  ·  LEVEL %d\nTIME  %02d:%02d" % [GameManager.selected_difficulty.to_upper(), GameManager.selected_level, int(time_remaining) / 60, int(time_remaining) % 60]
	(hud_labels.p2 as Label).text = "PLAYER 2  //  %d DOF\nHEALTH %03d    SCORE %03d" % [players[1].dof, players[1].health, scores[1]]

func _pause() -> void:
	get_tree().paused = true
	pause_menu = PAUSE_SCENE.instantiate() as PauseMenu
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.menu_requested.connect(_return_to_menu)
	pause_menu.cycle_requested.connect(_cycle_player_dof)
	add_child(pause_menu)

func _resume() -> void:
	get_tree().paused = false
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()

func _cycle_player_dof(player_id: int) -> void:
	players[player_id - 1].cycle_dof()
	_update_hud()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _return_to_menu() -> void:
	GameManager.go_to(GameManager.MAIN_MENU)

func _finish_game(reason: String) -> void:
	if game_finished:
		return
	game_finished = true
	for player: DOFPlayer in players:
		player.input_enabled = false
	var total_score := scores[0] + scores[1]
	var is_new := SaveManager.record_result(GameManager.selected_difficulty, GameManager.selected_level, total_score, reason == "TEST WINDOW COMPLETE")
	_show_results(reason, total_score, is_new)

func _show_results(reason: String, total_score: int, is_new: bool) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.03, 0.07, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := UIFactory.make_label(reason, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var result := UIFactory.make_label("TEAM SCORE  %d\nP1 %d  ·  P2 %d\n%s" % [total_score, scores[0], scores[1], "NEW HIGH SCORE" if is_new else "BEST  %d" % SaveManager.get_high_score(GameManager.selected_difficulty, GameManager.selected_level)], 19, UIFactory.GREEN if is_new else UIFactory.TEXT)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result)
	_add_result_button(box, "RESTART", _restart, true)
	_add_result_button(box, "LEVEL SELECT", GameManager.go_to.bind("res://scenes/ui/level_select.tscn"))
	_add_result_button(box, "MAIN MENU", _return_to_menu)

func _add_result_button(parent: VBoxContainer, text_value: String, callback: Callable, primary: bool = false) -> void:
	var button := Button.new()
	button.text = text_value
	UIFactory.setup_button(button, primary)
	button.pressed.connect(callback)
	parent.add_child(button)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), UIFactory.BG)
	var accent: Color = GameManager.LEVELS[GameManager.selected_level - 1].accent
	for x: int in range(60, 1221, 40):
		draw_line(Vector2(x, 150), Vector2(x, 665), Color(accent, 0.07), 1.0)
	for y: int in range(150, 666, 40):
		draw_line(Vector2(60, y), Vector2(1220, y), Color(accent, 0.07), 1.0)
	draw_rect(Rect2(55, 145, 1170, 520), Color(accent, 0.85), false, 3.0)
	draw_rect(Rect2(62, 152, 1156, 506), Color("0a1526"), true)
	for x: int in range(80, 1201, 80):
		draw_line(Vector2(x, 160), Vector2(x, 650), Color(accent, 0.08), 1.0)
	for y: int in range(170, 651, 80):
		draw_line(Vector2(70, y), Vector2(1210, y), Color(accent, 0.08), 1.0)
