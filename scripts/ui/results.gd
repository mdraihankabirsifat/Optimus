extends Control
## Placements, times, DNF/eliminated markers, per-racer stats, the seed, and three ways on.

func _ready() -> void:
	UiKit.setup_screen(self)
	var results: Array = GameState.last_results
	var col := UiKit.centre_column(self, 16)

	var you: Dictionary = {}
	for entry: Dictionary in results:
		if not entry.get("is_bot", false):
			you = entry
	var headline := "Race Over"
	var headline_colour := UiKit.EMBER
	if not you.is_empty():
		if you["finished"]:
			headline = "You finished %s" % _ordinal(int(you["place"]))
			if int(you["place"]) == 1:
				headline = "Victory!"
		elif you["eliminated"]:
			headline = "Eliminated"
			headline_colour = UiKit.DANGER
		else:
			headline = "Did not finish"
			headline_colour = UiKit.TEXT_DIM
	col.add_child(UiKit.title(headline, 64, headline_colour))

	var new_record := false
	if not you.is_empty() and you["finished"]:
		new_record = SettingsManager.submit_time(float(you["finish_time"]), GameState.last_match_seed)
		if new_record:
			AudioManager.play_sfx("record")
			col.add_child(UiKit.title("New personal best!", 24, UiKit.SKY))

	var panel := PanelContainer.new()
	col.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	for h: String in ["", "Racer", "Result", "Moves used", "Boxes", "Damage"]:
		grid.add_child(UiKit.label(h, 17, UiKit.TEXT_DIM))

	for entry: Dictionary in results:
		var racer_name: String = entry["name"]
		var stats: Dictionary = GameState.stats.get(racer_name, {})
		var colour: Color = stats.get("colour", UiKit.TEXT)
		var place_text := _ordinal(int(entry["place"])) if entry["finished"] else "--"
		grid.add_child(UiKit.label(place_text, 22, UiKit.EMBER if place_text == "1st" else UiKit.TEXT_DIM))
		grid.add_child(UiKit.label(racer_name, 22, colour))
		var result_text := "DNF"
		var result_colour := UiKit.TEXT_DIM
		if entry["finished"]:
			result_text = MatchController.format_time(float(entry["finish_time"]))
			result_colour = UiKit.TEXT
		elif entry["eliminated"]:
			result_text = "ELIMINATED"
			result_colour = UiKit.DANGER
		grid.add_child(UiKit.label(result_text, 22, result_colour))
		grid.add_child(UiKit.label(str(stats.get("moves_used", 0)), 22))
		grid.add_child(UiKit.label(str(stats.get("boxes", 0)), 22))
		grid.add_child(UiKit.label("%.1f" % float(stats.get("damage_taken", 0.0)), 22))

	col.add_child(UiKit.title("Cave seed  %d" % GameState.last_match_seed, 20, UiKit.TEXT_DIM))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var rematch := UiKit.button("Rematch  (same cave)", func() -> void:
		GameState.prepare_match(GameState.last_match_seed, GameState.bot_count)
		SceneRouter.start_match(), 280)
	row.add_child(rematch)
	row.add_child(UiKit.button("New Cave", func() -> void:
		GameState.prepare_match(GameState.randomise_seed(), GameState.bot_count)
		SceneRouter.start_match(), 220))
	row.add_child(UiKit.button("Main Menu", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU), 220))
	rematch.grab_focus.call_deferred()


static func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n
