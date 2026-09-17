extends Node
## SHIP-005 / SHIP-006: the submission trailer and store screenshots, scripted to the shot
## list in docs/SUBMISSION_CHECKLIST.md. It ends where every race now ends: the Freedom
## Duel and the Champion.
##
## Record (the movie writer runs on a fixed clock, so this is frame-exact):
##   godot --write-movie builds/trailer/trailer.avi --fixed-fps 30 res://tests/trailer.tscn
## Screenshots land in builds/trailer/ on the way through.

const SEED := 4242
const OUT := "res://builds/trailer"

var world: Node3D
var player: PlayerController
var mc: MatchController
var cam: Camera3D
var caption: Label
var card: ColorRect
var card_title: Label
var card_sub: Label
var _follow: Node3D
var _drive := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	GameState.cave_size = 1
	GameState.bot_skill = 2
	GameState.theme_id = "stone_age"
	GameState.prepare_match(SEED, 3)
	world = load("res://scenes/game/game_world.tscn").instantiate()
	# The root is still setting up its children during _ready, so this has to be deferred.
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = world
	await get_tree().process_frame
	player = world.local_player()
	mc = world.match_controller
	cam = Camera3D.new()
	cam.fov = 72.0
	world.add_child(cam)
	_build_overlay()

	# 0-4  title card, countdown running underneath
	_card(true, AppConfig.GAME_TITLE, "a race where gravity is yours alone")
	await _beat(4.0)
	_card(false)

	# 4-9  the spawn chamber and GO
	_hud(false)
	var spawn := CaveBuilder.cell_to_world(world.graph.spawn_cell)
	cam.global_position = spawn + Vector3(0, 1.0, 6.5)
	cam.look_at(spawn, Vector3.UP)
	cam.make_current()
	_caption("Race four rivals to an exit none of you has seen.")
	await _beat(5.0)
	_shot("store_01_spawn")

	# 9-17  first person: hold G, read the preview, turn onto the wall
	player.camera.make_current()
	_hud(true)
	_drive = true
	_caption("Five Gravity Moves. Yours alone.")
	await _beat(3.0)
	_drive = false
	Input.action_press("gravity_mod")
	await _beat(1.6)
	_shot("store_02_gravity_preview")
	Input.action_release("gravity_mod")
	var axes: Dictionary = player.movement_axes()
	player.gravity.request_shift(axes["right"])
	await _beat(3.4)
	_shot("store_03_on_the_wall")

	# 17-23  walking the wall
	_caption("Walls become floors. You walk where you look.")
	_drive = true
	await _beat(6.0)
	_drive = false

	# 23-30  flip at a shaft and fall upward
	var shaft := _find_shaft()
	if shaft != Vector3i.MAX:
		player.global_position = CaveBuilder.floor_position(shaft)
		player.velocity = Vector3.ZERO
	_caption("Ceilings become roads. A shaft only climbs if you flip.")
	await _beat(1.6)
	player.gravity.request_inversion()
	await _beat(5.4)
	_shot("store_04_ceiling")

	# 30-36  three racers, three surfaces, from outside
	_hud(false)
	var stage := _three_surfaces()
	# Keep the local racer out of a shot that is about the other three.
	player.global_position = CaveBuilder.floor_position(world.graph.spawn_cell)
	player.velocity = Vector3.ZERO
	cam.make_current()
	_caption("Freedom is personal: same chamber, three floors.")
	# A chamber is 7 units across, so the camera has to sit inside it, in a corner, wide.
	cam.fov = 100.0
	var t := 0.0
	while t < 6.0:
		var a := t / 6.0
		var swing := lerpf(-0.5, 0.5, a)
		cam.global_position = stage["centre"] - stage["axis"] * 2.2 \
			- stage["side"] * (2.2 - swing) + Vector3(0, 0.3 * swing, 0)
		cam.look_at(stage["centre"], Vector3.UP)
		if absf(t - 3.0) < 0.05:
			_shot("store_05_three_surfaces")
		t += await _step()
	cam.fov = 72.0
	_release_bots()

	# 36-41  the theme, measured live
	player.camera.make_current()
	_hud(true)
	var junction := _find_junction()
	if junction != Vector3i.MAX:
		player.global_position = CaveBuilder.floor_position(junction)
		player.velocity = Vector3.ZERO
	_caption("DOF: the degrees of freedom around you, counted from the real cave.")
	await _beat(3.0)
	_shot("store_06_dof")
	world.hud.toggle_map()
	await _beat(2.0)
	_shot("store_07_map")
	world.hud.toggle_map()

	# 41-46  qualify first
	player.global_position = CaveBuilder.floor_position(world.graph.finish_cell)
	await _beat(1.2)
	_caption("First to the pillar qualifies.")
	mc._on_finish_body_entered(player)
	await _beat(4.0)
	_shot("store_08_qualified")

	# 46-50  the challenger arrives, the duel begins
	_caption("The second racer out is the challenger.")
	mc._on_finish_body_entered(world.bots[0])
	await _beat(4.0)
	_shot("store_09_duel_intro")

	# 50-60  the fight
	var foe: PlayerController = world.bots[0]
	_caption("Pulse Blaster. Qualified 1st keeps three degrees of freedom.")
	for i in 7:
		_aim_and_fire(foe, "pulse")
		# A trailer should end on a win: keep the demo racer standing through the exchange.
		if _duel_running():
			player.health.hearts = AppConfig.DUEL_HEARTS
		await _beat(1.3)
		if i == 3:
			_shot("store_10_duel_fight")

	# 60-66  Axis Lock and the Freedom Core
	_caption("Take a freedom away. Win one back.")
	_aim_and_fire(foe, "lock")
	await _beat(2.2)
	_shot("store_11_axis_lock")
	if _duel_running():
		world.duel._core_timer = 0.2
		player.health.hearts = AppConfig.DUEL_HEARTS
	await _beat(3.8)

	# 66-71  sudden death
	if _duel_running() and not world.duel.sudden_death:
		world.duel.duel_time = AppConfig.SUDDEN_DEATH_AT - 0.2
	_caption("Sudden death: every hit counts double." if _duel_running() else "The duel decides the Champion.")
	if _duel_running():
		player.health.hearts = AppConfig.DUEL_HEARTS
	await _beat(4.6)
	_shot("store_12_sudden_death")

	# 71-76  the last hit, the Champion, then the real results screen
	if _duel_running() and foe.health.hearts > 1.0:
		foe.health.hearts = 0.5
	_caption("")
	for i in 4:
		if not _duel_running():
			break
		player.health.hearts = AppConfig.DUEL_HEARTS
		_aim_and_fire(foe, "pulse")
		await _beat(0.9)
	# In-world CHAMPION callout first; the results screen replaces it a moment later.
	await _beat(1.2)
	_shot("store_13_champion")
	# GameWorld routes to the results screen once the match ends, which frees the world.
	var waited := 0.0
	while waited < 8.0 and not _on_results():
		waited += await _step()
	await _beat(1.2)
	_shot("store_14_results")

	# 76-80  end card
	_caption("")
	_card(true, AppConfig.GAME_TITLE,
		"%s  ·  Bot Race offline, Online and Mixed  ·  BUET Robotics Society GameJam 2026" % AppConfig.TEAM_NAME)
	await _beat(4.0)
	get_tree().quit()


## True while the duel is still being fought and nothing has been freed under us.
func _duel_running() -> bool:
	return is_instance_valid(world) and world.duel != null \
		and world.duel.phase == FreedomDuel.Phase.FIGHT and is_instance_valid(player)


func _on_results() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path.ends_with("results.tscn")


func _aim_and_fire(target: PlayerController, kind: String) -> void:
	if not _duel_running() or not is_instance_valid(target):
		return
	var eye := player.head.global_position
	var dir := (target.global_position + Vector3(0, 0.6, 0) - eye).normalized()
	player.head.look_at(target.global_position + Vector3(0, 0.6, 0), Vector3.UP)
	world.duel.fighters[player]["pulse_cd" if kind == "pulse" else "lock_cd"] = 0.0
	world.duel.fire(player, kind, eye, dir)


## Three bots on three surfaces of one chamber: floor, wall and ceiling. It has to be a
## chamber -- in a 4-unit tunnel a racer on the floor and one on the ceiling nearly touch --
## and the camera stands inside it, in a corner, with a wide lens.
func _three_surfaces() -> Dictionary:
	var g: CaveGraph = world.graph
	var cell := g.spawn_cell
	for f: Dictionary in g.features:
		if f["kind"] == "landmark" and not _has_fire(f["cell"]):
			cell = f["cell"]
			break
	var centre := CaveBuilder.cell_to_world(cell)
	var axis := Vector3(CaveGraph.DIRS[CaveGraph.DIR_PLUS_X])
	for d: int in CaveGraph.FLAT_DIRS:
		if g.is_linked(cell, d):
			axis = Vector3(CaveGraph.DIRS[d])
			break
	var side := Vector3.UP.cross(axis).normalized()
	var reach := CaveBuilder.CHAMBER_HALF - 1.0
	var dirs := [Vector3.DOWN, side, Vector3.UP]
	for i in mini(3, world.bots.size()):
		var b := world.bots[i] as PlayerController
		b.get_node("BotController").set_physics_process(false)
		b.move_input = Vector2.ZERO
		b.global_position = centre + dirs[i] * reach + axis * (float(i) - 1.0) * 2.0
		b.velocity = Vector3.ZERO
		b.gravity.charges = 5
		if i == 1:
			b.gravity.request_shift(side)
		elif i == 2:
			b.gravity.request_inversion()
	return {"centre": centre, "axis": axis, "side": side}


func _has_fire(cell: Vector3i) -> bool:
	for h: Dictionary in world.graph.hazards:
		if h["cell"] == cell:
			return true
	return false


func _release_bots() -> void:
	for b: Node3D in world.bots:
		var c := b.get_node_or_null("BotController")
		if c != null:
			c.set_physics_process(true)


func _find_shaft() -> Vector3i:
	for c: Vector3i in world.graph.sorted_cells():
		if world.graph.is_linked(c, CaveGraph.DIR_UP):
			return c
	return Vector3i.MAX


func _find_junction() -> Vector3i:
	for c: Vector3i in world.graph.sorted_cells():
		if world.graph.degrees_of_freedom(c) >= 3:
			return c
	return Vector3i.MAX


func _process(_delta: float) -> void:
	if _drive and is_instance_valid(player) and is_instance_valid(world):
		player.move_input = Vector2(0, -1)
		player.sprint_input = true
	if _follow != null and cam != null and cam.current:
		var racer := _follow as PlayerController
		var up := racer.gravity.local_up()
		cam.global_position = racer.global_position + up * 2.0 + racer.global_basis.z * 4.2
		cam.look_at(racer.global_position + up * 0.5, up)


func _hud(on: bool) -> void:
	if not is_instance_valid(world):
		return
	if world.hud != null:
		world.hud.visible = on
	if world.duel_hud != null:
		world.duel_hud.visible = on


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	caption = UiKit.label("", 30)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 10)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -120
	caption.offset_bottom = -60
	root.add_child(caption)
	card = ColorRect.new()
	card.color = UiKit.BG
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(card)
	var col := UiKit.centre_column(card, 16)
	col.add_child(UiKit.logo(180.0))
	card_title = UiKit.title("", 104)
	col.add_child(card_title)
	card_sub = UiKit.title("", 24, UiKit.TEXT_DIM)
	col.add_child(card_sub)


func _card(on: bool, title: String = "", sub: String = "") -> void:
	card.visible = on
	card_title.text = title
	card_sub.text = sub


func _caption(text: String) -> void:
	caption.text = text


func _step() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _beat(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		left -= await _step()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shot(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
