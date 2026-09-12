class_name PrototypeArena3D
extends Node3D

const PLAYER: PackedScene = preload("res://scenes/player/player_3d.tscn")
const STATIONS: Array[Vector3] = [Vector3(-6, 0, 0), Vector3(6, 0, 0), Vector3(0, 0, -4)]
const HARVEST_SECONDS: Array[float] = [0.45, 0.9, 1.2]
const HARVEST_POINTS: Array[int] = [10, 10, 20]
var players: Array[DOFPlayer3D] = []
var scores: Array[int] = [0, 0]
var charge: Array[float] = [0.0, 0.0]
var station_cooldowns: Array[float] = [0.0, 0.0, 0.0]
var hazards: Array[Vector3] = []
var time_remaining: float
var finished: bool = false
var hud: Prototype3DHUD

func _ready() -> void:
	time_remaining = float(GameManager.difficulty_data().duration)
	_build_world()
	for index: int in 2:
		var player := PLAYER.instantiate() as DOFPlayer3D
		player.player_id = index + 1
		player.dof = index + 1
		player.position = Vector3(-8 if index == 0 else 8, 0.05, 0)
		player.player_color = UIFactory.CYAN if index == 0 else UIFactory.ORANGE
		player.move_speed *= float(GameManager.difficulty_data().speed_scale)
		player.health_changed.connect(_health_changed)
		add_child(player)
		players.append(player)
	hud = Prototype3DHUD.new()
	add_child(hud)
	hud.pause_requested.connect(toggle_pause)
	hud.restart_requested.connect(restart)
	hud.menu_requested.connect(GameManager.go_to.bind(GameManager.MAIN_MENU))
	hud.cycle_requested.connect(_cycle)
	_update_hud()

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("07101f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 22, 16)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22.0
	camera.current = true
	GreyboxGeometry.box(self, Vector3(0, -0.3, 0), Vector3(22, 0.6, 14), Color("344253"), true)
	for x: float in [-11.0, 11.0]:
		GreyboxGeometry.box(self, Vector3(x, 0.5, 0), Vector3(0.5, 1, 14), Color("708090"), true)
	for z: float in [-7.0, 7.0]:
		GreyboxGeometry.box(self, Vector3(0, 0.5, z), Vector3(22, 1, 0.5), Color("708090"), true)
	GreyboxGeometry.box(self, Vector3(0, 0.015, 0), Vector3(21, 0.02, 0.08), UIFactory.CYAN)
	for at: Vector3 in STATIONS:
		GreyboxGeometry.box(self, at + Vector3(0, 0.15, 0), Vector3(0.7, 0.3, 0.7), UIFactory.GREEN)
	var locations: Array[Vector3] = [Vector3.ZERO, Vector3(-3, 0, -3), Vector3(3, 0, 3)]
	var level := clampi(GameManager.selected_level, 1, 3)
	for index: int in int(GameManager.LEVELS[level - 1].hazard_count):
		hazards.append(locations[index])
		GreyboxGeometry.box(self, locations[index] + Vector3(0, 0.025, 0), Vector3(2, 0.05, 2), UIFactory.RED)

func _physics_process(delta: float) -> void:
	if finished:
		return
	time_remaining = maxf(0, time_remaining - delta)
	for index: int in station_cooldowns.size():
		station_cooldowns[index] = maxf(0, station_cooldowns[index] - delta)
	for index: int in players.size():
		var player := players[index]
		_harvest(index, delta)
		for at: Vector3 in hazards:
			if Vector2(player.position.x - at.x, player.position.z - at.z).length() < 1.3:
				player.take_damage(int(GameManager.difficulty_data().hazard_damage))
	_update_hud()
	if time_remaining <= 0:
		finish("TEST WINDOW COMPLETE")

func _harvest(index: int, delta: float) -> void:
	var player := players[index]
	for station: int in STATIONS.size():
		var offset := STATIONS[station] - player.position
		offset.y = 0
		if offset.length() > 1.5 or station_cooldowns[station] > 0:
			continue
		if player.dof == 3 and offset.length() > 0.2 and (-player.global_basis.z).dot(offset.normalized()) < 0.75:
			continue
		charge[index] += delta
		if charge[index] >= HARVEST_SECONDS[player.dof - 1]:
			scores[index] += HARVEST_POINTS[player.dof - 1]
			charge[index] = 0
			station_cooldowns[station] = 1.5
		return
	charge[index] = 0

func _update_hud() -> void:
	hud.status.text = "3D GREYBOX | %s | LEVEL %d | TIME %ds\nP1: %d DOF | HP %d | SCORE %d     P2: %d DOF | HP %d | SCORE %d" % [GameManager.selected_difficulty, GameManager.selected_level, ceili(time_remaining), players[0].dof, players[0].health, scores[0], players[1].dof, players[1].health, scores[1]]

func _health_changed(_id: int, health: int) -> void:
	if health <= 0:
		finish("ROBOT DISABLED")

func _cycle(id: int) -> void:
	players[id - 1].cycle_dof()
	charge[id - 1] = 0
	_update_hud()

func toggle_pause() -> void:
	if finished:
		GameManager.go_to(GameManager.MAIN_MENU)
		return
	get_tree().paused = not get_tree().paused
	if get_tree().paused:
		hud.show_pause()
	else:
		hud.close_overlay()

func restart() -> void:
	GameManager.go_to("res://scenes/game/prototype_arena_3d.tscn")

func finish(reason: String) -> void:
	if finished:
		return
	finished = true
	for player: DOFPlayer3D in players:
		player.input_enabled = false
	hud.show_result(reason, scores[0] + scores[1])
