extends Control
## The theme stated plainly for judges.

func _ready() -> void:
	UiKit.text_page(self, "Degree of Freedom", "\n".join([
		"[font_size=24][color=#ff9e3d]The theme is a rule, not a backdrop.[/color][/font_size]",
		"",
		"[b]Translational freedom is the map.[/b] Every cell of the cave knows which axes it opens. "
			+ "A tunnel lets you move along one axis: [b]DOF 1[/b]. A crossroads opens two: [b]DOF 2[/b]. "
			+ "A junction with a shaft opens all three: [b]DOF 3[/b]. The HUD shows this number live, "
			+ "computed from the real cave geometry around you.",
		"",
		"[b]Rotational freedom is the mechanic.[/b] You may rotate your own gravity to any of the six "
			+ "grid directions -- plus and minus X, Y and Z -- at any moment. Walls become floors, "
			+ "ceilings become roads, and a shaft you could never climb becomes a drop.",
		"",
		"[b]Freedom has a price.[/b] You get five Moves. Vertical routes demand them. "
			+ "Every junction asks the same question: is more freedom worth spending some of it?",
		"",
		"[b]Freedom is the prize.[/b] The first two out of the cave meet in the [b]Freedom Duel[/b]. "
			+ "Getting out first earns the third degree of freedom -- the jump -- and the fight itself trades "
			+ "freedom: an Axis Lock takes an axis away, a Freedom Core gives one back.",
		"",
		"[b]Freedom is personal.[/b] Gravity belongs to each racer. Two racers in the same corridor "
			+ "can each be standing on a different surface, each correctly upright in their own frame. "
			+ "Nothing about the world changes when you turn it -- only your relationship to it.",
		"",
		"[b]Fair search.[/b] The cave is generated from a seed and is always solvable within your "
			+ "starting Moves. The bots you race only know the parts of the cave they have "
			+ "personally seen -- they explore, backtrack and gamble on Moves exactly as you do.",
		"",
		"[font_size=24][color=#ff9e3d]%s[/color][/font_size]" % AppConfig.TEAM_NAME,
		"Md. Raihan Kabir Sifat    Estiak Zaman Atul    Sadman Sakib    Ashraf Hossain Chowdhury",
		"",
		"[color=#9b928a]%s  --  %s[/color]" % [AppConfig.GAME_TITLE, AppConfig.TEAM_NAME],
		"[color=#9b928a]BUET Robotics Society GameJam, Intra BUET Robo Challenge 2026[/color]",
	]))
