extends Control
## Placements, times, DNF/eliminated markers, per-racer stats, the seed, and three ways on.
##
## Prompt 2: the Freedom Duel decides the top two. The Champion leads, the duel runner-up is
## 2nd, and everyone else follows in cave order. The first racer out of the cave is
## "Qualified 1st", never "Winner" -- only the duel makes a Champion.

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
	var duel: Dictionary = GameState.last_duel
	if not you.is_empty():
		if int(you.get("duel_place", 0)) == 1:
			headline = "CHAMPION!" if duel.get("fought", false) else "Champion by default"
			headline_colour = UiKit.EMBER
		elif int(you.get("duel_place", 0)) == 2:
			headline = "Finalist  -  2nd"
			headline_colour = UiKit.SKY
		elif you["finished"]:
			headline = "You finished %s" % _ordinal(results.find(you) + 1)
			if int(you["place"]) == 1 and duel.is_empty():
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

	var champion := _entry_with(results, 1)
	var runner := _entry_with(results, 2)
	if not champion.is_empty():
		var line := "Freedom Duel:  %s is Champion" % champion["name"]
		if not runner.is_empty():
			line = "Freedom Duel:  %s beat %s in %s" % [champion["name"], runner["name"],
				MatchController.format_time(float(duel.get("duration", 0.0)))]
			if String(duel.get("reason", "")) == "time":
				line += "  (on hearts at the time limit)"
		elif duel.has("reason"):
			line += "  (by default: %s)" % duel["reason"]
		col.add_child(UiKit.title(line, 24, UiKit.EMBER))

	var panel := PanelContainer.new()
	col.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	for h: String in ["", "Racer", "Cave", "Freedom Duel", "Moves used", "Boxes", "Damage"]:
		grid.add_child(UiKit.label(h, 17, UiKit.TEXT_DIM))

	var has_duel := not champion.is_empty()
	for i in results.size():
		var entry: Dictionary = results[i]
		var racer_name: String = entry["name"]
		var stats: Dictionary = GameState.stats.get(racer_name, {})
		var colour: Color = stats.get("colour", UiKit.TEXT)
		var place_text := _ordinal(int(entry["place"])) if entry["finished"] else "--"
		var place_size := 22
		if has_duel:
			place_text = _ordinal(i + 1) if entry["finished"] or entry.get("stopped_by_duel", false) else "--"
			if int(entry.get("duel_place", 0)) == 1:
				place_text = "CHAMPION"
				place_size = 26
		grid.add_child(UiKit.label(place_text, place_size, UiKit.EMBER if place_text in ["1st", "CHAMPION"] else UiKit.TEXT_DIM))
		grid.add_child(UiKit.label(racer_name, place_size, colour))
		var result_text := "DNF"
		var result_colour := UiKit.TEXT_DIM
		if entry.get("stopped_by_duel", false):
			result_text = "DNF  (%d from the exit)" % int(entry.get("progress", 0)) if int(entry.get("progress", 999)) < 999 else "DNF"
		if entry["finished"]:
			result_text = MatchController.format_time(float(entry["finish_time"]))
			if int(entry.get("qualified", 0)) > 0:
				result_text = "Q%d  %s" % [int(entry["qualified"]), result_text]
			result_colour = UiKit.TEXT
		elif entry.get("disconnected", false):
			result_text = "DISCONNECTED"
		elif entry["eliminated"]:
			result_text = "ELIMINATED"
			result_colour = UiKit.DANGER
		grid.add_child(UiKit.label(result_text, 22, result_colour))
		grid.add_child(UiKit.label(_duel_text(entry), 20, UiKit.EMBER if int(entry.get("duel_place", 0)) == 1 else UiKit.TEXT))
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


func _entry_with(results: Array, duel_place: int) -> Dictionary:
	for entry: Dictionary in results:
		if int(entry.get("duel_place", 0)) == duel_place:
			return entry
	return {}


## "won  4.5 dmg  2 locks  1 core" for the finalists; a dash for everyone else.
func _duel_text(entry: Dictionary) -> String:
	var place := int(entry.get("duel_place", 0))
	if place == 0:
		return "-"
	var st: Dictionary = entry.get("duel_stats", {})
	if not GameState.last_duel.get("fought", false):
		return "won by default"
	return "%s  %.1f dmg  %d lock%s  %d core%s" % ["won" if place == 1 else "lost",
		float(st.get("damage_dealt", 0.0)), int(st.get("locks_landed", 0)), "" if int(st.get("locks_landed", 0)) == 1 else "s",
		int(st.get("cores", 0)), "" if int(st.get("cores", 0)) == 1 else "s"]


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
