extends Control
## Written so a judge can play correctly after reading it once.

const E := "[color=#ff9e3d]"
const S := "[color=#5cc7ff]"


func _ready() -> void:
	SettingsManager.seen_tutorial = true
	SettingsManager.save_settings()
	UiKit.text_page(self, "How to Play", "\n".join([
		"[font_size=24]%sThe race[/color][/font_size]" % E,
		"You and the bots spawn in the same cave. Nobody knows where the exit is -- not even the bots. "
			+ "Find the [b]glowing amber pillar[/b] first. It is never shown on the HUD.",
		"",
		"[font_size=24]%sMove[/color][/font_size]" % E,
		"[b]Mouse[/b] look    [b]W A S D[/b] walk    [b]Shift[/b] sprint    [b]Space[/b] jump    "
			+ "[b]E[/b] open a mystery box    [b]Esc[/b] pause",
		"",
		"[font_size=24]%sThe Gravity Move[/color][/font_size]" % S,
		"Hold [b]G[/b] and tap a direction. Your gravity rotates and that surface becomes your floor.",
		"    [b]G + W / A / S / D[/b]   rotate 90 degrees toward that side of your view -- walk on walls",
		"    [b]G + Space[/b]   flip 180 degrees -- the ceiling becomes your floor",
		"While G is held the HUD shows exactly where each key would send you.",
		"",
		"You have [b]5 Moves[/b]. A 90 and a 180 each cost one. Spend them anywhere -- "
			+ "even in mid-air. Falling into empty space is allowed: you fall until you hit something.",
		"Shafts in the cave go [b]up[/b]. The only way to climb one is to flip your gravity and fall upward.",
		"",
		"[font_size=24]%sYour gravity is private[/color][/font_size]" % S,
		"A Move rotates [b]only you[/b]. A bot can be running on the ceiling above you while you walk the floor. "
			+ "The world never turns.",
		"",
		"[font_size=24]%sHearts and hazards[/color][/font_size]" % E,
		"5 hearts. [b]Fire[/b] burns half a heart per second -- walk around it, or rotate onto a wall and "
			+ "walk right over it. At zero hearts you are out and can spectate ([b]Tab[/b] to switch racer).",
		"A 180 into a bottomless void costs a heart and puts you back where you last stood safely. It never kills you outright.",
		"",
		"[font_size=24]%sMystery boxes[/color][/font_size]" % E,
		"Heart refill, Move refill, speed boost or shield -- or a slow, or a drained Move. "
			+ "Very rarely, a [b]clue[/b] points roughly toward the exit.",
		"Dead ends hide boxes more often than corridors do.",
		"",
		"[font_size=24]%sDOF -- degrees of freedom[/color][/font_size]" % S,
		"The HUD shows [b]DOF 1, 2 or 3[/b]: how many axes you can travel along right here. "
			+ "A tunnel is DOF 1. A junction with a shaft is DOF 3. More freedom means more routes -- "
			+ "but the vertical ones cost Moves.",
	]))
