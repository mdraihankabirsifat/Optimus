extends Control
## Placements, times, DNF/eliminated markers, per-racer stats, the seed, and three ways on.

func _ready() -> void:
	UiKit.setup_screen(self)
	var results: Array = GameState.last_results
	var col := UiKit.centre_column(self, 16)

	var online := GameState.last_results_online
	var you: Dictionary = {}
	for entry: Dictionary in results:
		if online:
			if String(entry["name"]) == GameState.net_local_name:
				you = entry
		elif not entry.get("is_bot", false):
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

	# The race itself records the time (it also saves the ghost); results only report it.
	if not you.is_empty() and you["finished"] and GameState.new_record:
		AudioManager.play_sfx("record")
		col.add_child(UiKit.title("New best on this cave!  Your ghost will race you next time.", 22, UiKit.SKY))

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
		elif entry.get("disconnected", false):
			result_text = "DISCONNECTED"
		elif entry["eliminated"]:
			result_text = "ELIMINATED"
			result_colour = UiKit.DANGER
		grid.add_child(UiKit.label(result_text, 22, result_colour))
		grid.add_child(UiKit.label(str(stats.get("moves_used", 0)), 22))
		grid.add_child(UiKit.label(str(stats.get("boxes", 0)), 22))
		grid.add_child(UiKit.label("%.1f" % float(stats.get("damage_taken", 0.0)), 22))

	var highlights := _highlights(results)
	if highlights != "":
		col.add_child(UiKit.title(highlights, 18, UiKit.EMBER))
	var board := [] if online else SettingsManager.leaderboard(GameState.last_match_seed, GameState.last_cave_size)
	if not board.is_empty():
		var times: Array[String] = []
		for t in board:
			times.append(MatchController.format_time(float(t)))
		col.add_child(UiKit.title("Your top times here:  " + "   ".join(times), 18, UiKit.SKY))
	var size_name: String = CaveGenerator.SIZE_PRESETS[GameState.last_cave_size]["name"]
	col.add_child(UiKit.title("%s cave  ·  seed %d" % [size_name, GameState.last_match_seed], 20, UiKit.TEXT_DIM))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	if online:
		# Rematches are the host's call from the room; the room is still open.
		var still_in_room := NetManager.is_online() and NetManager.in_room()
		var lobby_button := UiKit.button("Back to Room" if still_in_room else "Online Lobby", func() -> void:
			SceneRouter.go_to(SceneRouter.ONLINE_LOBBY), 280)
		row.add_child(lobby_button)
		row.add_child(UiKit.button("Main Menu", func() -> void:
			NetManager.leave_room()
			SceneRouter.go_to(SceneRouter.MAIN_MENU), 220))
		lobby_button.grab_focus.call_deferred()
		return
	var rematch := UiKit.button("Rematch  (same cave)", func() -> void:
		GameState.cave_size = GameState.last_cave_size
		GameState.prepare_match(GameState.last_match_seed, GameState.bot_count)
		SceneRouter.start_match(), 280)
	row.add_child(rematch)
	row.add_child(UiKit.button("New Cave", func() -> void:
		GameState.prepare_match(GameState.randomise_seed(), GameState.bot_count)
		SceneRouter.start_match(), 220))
	row.add_child(UiKit.button("Main Menu", func() -> void: SceneRouter.go_to(SceneRouter.MAIN_MENU), 220))
	rematch.grab_focus.call_deferred()


## FUN-008: one line of the race's most notable moments, from stats the race recorded.
func _highlights(results: Array) -> String:
	var parts: Array[String] = []
	var most_moves := ""
	var moves := 0
	var most_boxes := ""
	var boxes := 0
	var toughest := ""
	var damage := 0.0
	for entry: Dictionary in results:
		var st: Dictionary = GameState.stats.get(entry["name"], {})
		if int(st.get("moves_used", 0)) > moves:
			moves = int(st["moves_used"])
			most_moves = entry["name"]
		if int(st.get("boxes", 0)) > boxes:
			boxes = int(st["boxes"])
			most_boxes = entry["name"]
		if entry["finished"] and float(st.get("damage_taken", 0.0)) > damage:
			damage = float(st["damage_taken"])
			toughest = entry["name"]
	var finish_times: Array[float] = []
	for entry: Dictionary in results:
		if entry["finished"]:
			finish_times.append(float(entry["finish_time"]))
	var closest := INF
	for i in range(1, finish_times.size()):
		closest = minf(closest, finish_times[i] - finish_times[i - 1])
	if most_moves != "":
		parts.append("Most Moves: %s (%d)" % [most_moves, moves])
	if most_boxes != "":
		parts.append("Box hunter: %s (%d)" % [most_boxes, boxes])
	if toughest != "":
		parts.append("Toughest finish: %s (took %.1f)" % [toughest, damage])
	if closest < INF:
		parts.append("Closest finish: %.2fs" % closest)
	return "   ·   ".join(parts)


static func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n
