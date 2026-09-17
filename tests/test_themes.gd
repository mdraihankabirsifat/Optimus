extends Node
## ART-012 -- environments are data and never touch gameplay.
## Run: godot --headless res://tests/test_themes.tscn

const SEED := 4242

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n-- every environment builds the same race")
	var base_hash := -1
	var base_boxes := -1
	var base_hazards := -1
	for id: String in CaveTheme.IDS:
		var world: Node3D = load("res://scenes/game/game_world.tscn").instantiate()
		world.randomise_seed = false
		world.fixed_seed = SEED
		world.bot_count = 1
		world.theme_id = id
		add_child(world)
		await get_tree().process_frame
		var theme: CaveTheme = world.get("theme")
		_check(theme != null and theme.id == id, "%s: the race uses that environment" % id)
		var g: CaveGraph = world.graph
		var boxes := WorldScope.nodes(world, "mystery_boxes").size()
		var hazards := WorldScope.nodes(world, "hazards").size()
		if base_hash == -1:
			base_hash = g.graph_hash()
			base_boxes = boxes
			base_hazards = hazards
		_check(g.graph_hash() == base_hash, "%s: same seed, same cave" % id)
		_check(boxes == base_boxes and hazards == base_hazards, "%s: same boxes and hazards" % id)
		var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
		_check(env.ambient_light_color.is_equal_approx(theme.ambient_colour)
			and is_equal_approx(env.fog_density, theme.fog_density), "%s: lighting and fog applied" % id)
		var props := world.find_child("ThemeProps", true, false)
		if theme.signature_props == "":
			_check(props == null, "%s: no signature props" % id)
		else:
			_check(props != null and props.get_child_count() > 0, "%s: signature props (%s) placed" % [id, theme.signature_props])
		var lamp := (world.get("_player") as Node).get_node_or_null("Lamp")
		_check((lamp != null) == (theme.personal_light_energy > 0.0), "%s: personal lamp only where the theme has one" % id)
		_check(theme.floor_colour.get_luminance() > 0.2 and theme.ambient_energy >= 0.5,
			"%s: never too dark to navigate" % id)
		world.queue_free()
		await get_tree().process_frame

	_test_fog_readability()

	print("-- online rooms carry the environment")
	var room := LobbyState.new("THEM", LobbyState.MODE_MIXED)
	room.add_human(1, "Host")
	room.theme_id = "jungle"
	_check(room.snapshot()["theme"] == "jungle", "lobby snapshot names the environment")
	_check(CaveTheme.by_id("nonsense").id == "stone_age", "an unknown environment falls back to Stone Age")

	print("")
	print("==================================================")
	print("  ART-012 THEMES   passed: %d   failed: %d" % [_passed, _failed])
	print("==================================================")
	get_tree().quit(1 if _failed > 0 else 0)


## ART-008: every environment must read at three distances. A cell is 8 units.
## Near (the cell you are in and the doorway ahead) stays legible; three cells away is
## clearly hazier; far is mostly fog but never a solid wall of it.
func _test_fog_readability() -> void:
	print("-- fog gradient reads at every distance")
	for id: String in ["stone_age", "jungle", "dark_cave", "city_drain"]:
		var t := CaveTheme.by_id(id)
		var near := t.fog_factor(8.0)
		var mid := t.fog_factor(24.0)
		var far := t.fog_factor(56.0)
		_check(near <= 0.25, "%s: the next cell stays clear (%.2f)" % [id, near])
		_check(mid > near and mid >= 0.15 and mid <= 0.75, "%s: three cells away reads as distance (%.2f)" % [id, mid])
		_check(far > mid, "%s: fog keeps deepening with distance (%.2f)" % [id, far])
		_check(t.fog_factor(0.0) == 0.0, "%s: nothing fogs at the camera" % id)
		_check(t.fog_begin >= 4.0 and t.fog_end > t.fog_begin, "%s: sane fog range" % id)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("   FAIL  %s" % label)
