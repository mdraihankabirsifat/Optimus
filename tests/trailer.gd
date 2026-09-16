extends Node
## SHIP-005 / SHIP-006: a scripted gameplay trailer and store screenshots.
##
## Record the video (Godot's movie writer runs on a fixed clock, so this is frame-exact):
##   godot --write-movie builds/trailer/trailer.avi --fixed-fps 30 res://tests/trailer.tscn
## Screenshots are written to builds/trailer/*.png on the way through.

const SEED := 4242
const OUT := "res://builds/trailer"

var world: Node3D
var cam: Camera3D
var caption: Label
var card: ColorRect
var card_title: Label
var card_sub: Label
var logo: Control
var _follow: Node3D
var _follow_offset := Vector3.ZERO


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	SettingsManager.camera_effects = true
	GameState.cave_size = 1
	GameState.bot_skill = 2
	GameState.prepare_match(SEED, 4)
	world = load("res://scenes/game/game_world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = world
	_build_overlay()
	cam = Camera3D.new()
	cam.fov = 70.0
	world.add_child(cam)
	world.hud.visible = false

	# --- 0: title card while the countdown runs underneath
	_card(true, AppConfig.GAME_TITLE, "a race where gravity is yours alone")
	await _wait(4.2)
	_card(false)

	# --- 1: chase a bot through the cave
	var bots: Array = world.bots
	_chase(bots[0])
	_caption("Race bots through a cave none of you has seen.")
	await _wait(6.0)
	_shot("store_1_chase")
	_chase(bots[2])
	_caption("They only know what they have explored. So do you.")
	await _wait(5.0)

	# --- 2: three racers, three floors, one corridor
	_follow = null
	var stage := _three_surfaces(bots)
	_caption("Gravity is personal. Floor, wall, ceiling -- same corridor, each one upright.")
	var t := 0.0
	while t < 7.0:
		var a := t / 7.0
		# From the far end of the corridor, drifting in: floor, wall and ceiling all in frame.
		cam.global_position = stage["centre"] - stage["axis"] * (7.5 - 2.0 * a) - stage["side"] * 1.2 + Vector3(0, -0.4, 0)
		cam.look_at(stage["centre"] + stage["side"] * 0.6, Vector3.UP)
		if absf(t - 3.5) < 0.02:
			_shot("store_2_three_surfaces")
		t += await _step()
	for b in bots:
		(b as PlayerController).get_node("BotController").set_physics_process(true)

	# --- 3: first person, the flip
	var player: PlayerController = get_tree().get_first_node_in_group("local_player")
	player.camera.make_current()
	world.hud.visible = true
	_caption("Hold G. The HUD shows where each key will send you.")
	player.head.rotation.x = -0.1
	Input.action_press("gravity_mod")
	await _wait(2.4)
	_shot("store_3_gravity_preview")
	Input.action_release("gravity_mod")
	world.hud.visible = false
	# The flip, seen from outside: a bot on the floor turns the ceiling into its floor.
	var flipper := bots[3] as PlayerController
	flipper.get_node("BotController").set_physics_process(false)
	flipper.move_input = Vector2.ZERO
	flipper.global_position = stage["centre"] + Vector3(0, -2.6, 0)
	flipper.velocity = Vector3.ZERO
	flipper.gravity.charges = 5
	cam.make_current()
	cam.global_position = stage["centre"] - stage["axis"] * 5.5 + stage["side"] * 2.0
	cam.look_at(stage["centre"], Vector3.UP)
	_caption("G + Space: the ceiling becomes your floor. Five Moves. Spend them anywhere.")
	await _wait(1.0)
	flipper.gravity.request_inversion()
	await _wait(0.3)
	_shot("store_4_the_flip")
	await _wait(2.4)
	flipper.get_node("BotController").set_physics_process(true)

	# --- 4: hazards montage
	for kind in ["fire", "piston", "spider"]:
		var target := _find_hazard(kind)
		if target == null:
			continue
		cam.make_current()
		_follow = null
		var text: String = {"fire": "Fire burns the floor -- walk the wall past it.",
			"piston": "Pistons slam on a beat.",
			"spider": "Spiders own the floor. Not the ceiling."}[kind]
		_caption(text)
		var base: Vector3 = target.global_position
		var d := 0.0
		while d < 3.2:
			var ang := 0.6 + d * 0.25
			cam.global_position = base + Vector3(cos(ang) * 4.5, 1.0 if kind != "piston" else -1.5, sin(ang) * 4.5)
			cam.look_at(base + Vector3(0, -1.5 if kind == "piston" else 0.3, 0), Vector3.UP)
			d += await _step()
		_shot("store_5_%s" % kind)

	# --- 5: DOF
	player.camera.make_current()
	world.hud.visible = true
	# Stage an explored neighbourhood so the map has something to show.
	var near: Dictionary = world.graph.distances_from(world.graph.spawn_cell)
	for c: Vector3i in near:
		if int(near[c]) <= 5 and c.y == world.graph.spawn_cell.y:
			world.visited_cells[c] = true
	player.global_position = CaveBuilder.floor_position(world.graph.spawn_cell) + Vector3(0, 0.3, 0)
	_caption("DOF: the degrees of freedom around you, counted live from the real cave.")
	await _wait(4.0)
	world.hud.toggle_map()
	_caption("Your map only knows where you have been. The exit is never on it.")
	await _wait(3.0)
	_shot("store_6_hud_map")
	world.hud.toggle_map()
	world.hud.visible = false

	# --- 6: the finish
	cam.make_current()
	var finish := CaveBuilder.cell_to_world(world.graph.finish_cell)
	_caption("First to the amber pillar wins.")
	var f := 0.0
	while f < 5.0:
		cam.global_position = finish + Vector3(cos(f * 0.4) * 3.4, -1.4 + f * 0.12, sin(f * 0.4) * 3.4)
		cam.look_at(finish + Vector3(0, -2.0, 0), Vector3.UP)
		f += await _step()
	_shot("store_7_finish")

	# --- 7: end card
	_caption("")
	_card(true, AppConfig.GAME_TITLE, "%s  ·  BUET Robotics Society GameJam 2026  ·  Theme: Degree of Freedom" % AppConfig.TEAM_NAME)
	await _wait(4.0)
	get_tree().quit()


## Freeze three bots in one straight corridor: one on the floor, one on a wall, one on the
## ceiling. Returns the corridor centre and axes for the camera move.
func _three_surfaces(bots: Array) -> Dictionary:
	var g: CaveGraph = world.graph
	var cell := g.spine[3]
	var axis_index := -1
	for c: Vector3i in g.sorted_cells():
		var ax := g.straight_axis(c)
		if ax != -1 and not g.features_at(c).any(func(fe: Dictionary) -> bool: return fe["kind"] in ["piston", "spider", "wind"]):
			var fire := false
			for h: Dictionary in g.hazards:
				fire = fire or h["cell"] == c
			if not fire:
				cell = c
				axis_index = ax
				break
	var centre := CaveBuilder.cell_to_world(cell)
	var axis := Vector3(CaveGraph.DIRS[maxi(axis_index, 0)])
	var side := Vector3.UP.cross(axis).normalized()
	var dirs := [Vector3.DOWN, side, Vector3.UP]
	for i in 3:
		var b := bots[i] as PlayerController
		b.get_node("BotController").set_physics_process(false)
		b.move_input = Vector2.ZERO
		b.global_position = centre + dirs[i] * 2.8 + axis * (float(i) - 1.0) * 1.6
		b.velocity = Vector3.ZERO
		b.gravity.charges = 5
		if i == 1:
			b.gravity.request_shift(side)
		elif i == 2:
			b.gravity.request_inversion()
	return {"centre": centre, "axis": axis, "side": side}


func _find_hazard(kind: String) -> Node3D:
	for n in get_tree().get_nodes_in_group("hazards"):
		if kind == "fire" and n is FireHazard:
			return n
		if kind == "piston" and n is PistonHazard:
			return n
		if kind == "spider" and n is SpiderEnemy:
			return n
	return null


func _chase(target: Node3D) -> void:
	_follow = target
	cam.make_current()


func _process(delta: float) -> void:
	if _follow == null or cam == null:
		return
	var racer := _follow as PlayerController
	var up := racer.gravity.local_up()
	var v := racer.velocity - up * racer.velocity.dot(up)
	var fwd := v.normalized() if v.length() > 1.0 else -racer.global_basis.z
	var want := racer.global_position + up * 2.0 - fwd * 4.2
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-5.0 * delta))
	cam.look_at(racer.global_position + up * 0.5 + fwd * 1.5, up)


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
	logo = UiKit.logo(180.0)
	col.add_child(logo)
	card_title = UiKit.title("", 104)
	col.add_child(card_title)
	card_sub = UiKit.title("", 26, UiKit.TEXT_DIM)
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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _shot(shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
