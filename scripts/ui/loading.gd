extends Control
## UI-014: a beat between the lobby and the race. States the cave you are about to enter and
## teaches one thing. The cave itself is generated behind the next fade.

const TIPS := [
	"Hold G and look before you press anything: the HUD names the surface each key makes your floor.",
	"Shafts only go up if you flip. G + Space turns the ceiling into the floor -- and the shaft into a drop.",
	"Fire covers a floor, never a wall. Rotate onto the wall and walk straight past it.",
	"Spiders live on the world floor. Walk the ceiling and they cannot reach you.",
	"Dead ends hide mystery boxes more often than corridors do.",
	"DOF 3 means a junction with a shaft: more routes, but the vertical ones cost a Move.",
	"A cracked, glowing floor over a hole will not hold for long.",
	"A green SHORTCUT ring under a shaft means spending a Move there saves a long walk.",
	"Tap Space for a hop, hold it for a full jump.",
	"Press M for your map. It only shows where you have been.",
	"Bots know only what they have seen. They get lost too.",
	"Out of Moves? Mystery boxes can refill one. So can Move regen, if the lobby turned it on.",
]

var _leaving := false


func _ready() -> void:
	UiKit.setup_screen(self)
	AudioManager.stop_music()
	var col := UiKit.centre_column(self, 14)
	col.add_child(UiKit.logo(90.0))
	var preset: Dictionary = CaveGenerator.SIZE_PRESETS[GameState.cave_size]
	var mode := "Time Trial" if GameState.bot_count == 0 else "Bot Race  ·  %d bots" % GameState.bot_count
	var online := GameState.net_role == "client"
	if online:
		var cfg := GameState.net_config
		var humans := 0
		for entry: Dictionary in cfg.get("roster", []):
			if not entry["is_bot"]:
				humans += 1
		var total: int = cfg.get("roster", []).size()
		mode = "%s  ·  %d humans, %d bots" % ["Mixed Race" if cfg.get("mode", "") == "mixed" else "Online Race",
			humans, total - humans]
	col.add_child(UiKit.title(mode, 44))
	col.add_child(UiKit.title("%s cave  ·  seed %d%s" % [preset["name"], GameState.seed_value,
		("  ·  room %s" % GameState.net_config.get("room", "")) if online else ""], 22, UiKit.TEXT_DIM))
	var best := 0.0 if online else SettingsManager.best_for(GameState.seed_value, GameState.cave_size)
	if best > 0.0:
		col.add_child(UiKit.title("Your best here  %s  --  your ghost races with you" % MatchController.format_time(best),
			18, UiKit.SKY))
	col.add_child(UiKit.label(""))
	var tip := UiKit.label(TIPS[randi() % TIPS.size()], 22, UiKit.TEXT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(720, 0)
	col.add_child(tip)
	col.add_child(UiKit.title("press any key", 16, UiKit.TEXT_DIM))
	GameState.launched_from_menu = true
	await get_tree().create_timer(2.4).timeout
	_leave()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	while SceneRouter.is_busy():
		await get_tree().process_frame
	GameState.launched_from_menu = true
	SceneRouter.go_to(SceneRouter.GAME)
