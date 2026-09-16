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
			+ "Find the [b]glowing amber pillar[/b] inside its ring of standing stones. It is never shown on the HUD or the map.",
		"",
		"[font_size=24]%sMove[/color][/font_size]" % E,
		"[b]Mouse[/b] look    [b]W A S D[/b] walk    [b]Shift[/b] sprint    [b]Space[/b] jump (tap for a hop)    "
			+ "[b]E[/b] open a mystery box",
		"[b]M[/b] map    [b]1 2 3[/b] emotes    [b]Esc[/b] pause    [b]Tab[/b] / [b]Enter[/b] after you finish: next racer / end the race",
		"",
		"[font_size=24]%sThe Gravity Move[/color][/font_size]" % S,
		"Hold [b]G[/b] and tap a direction. Your gravity rotates and that surface becomes your floor.",
		"    [b]G + W / A / S / D[/b]   rotate 90 degrees toward that side of your view -- walk on walls",
		"    [b]G + Space[/b]   flip 180 degrees -- the ceiling becomes your floor",
		"While G is held the HUD names the surface each key would send you to.",
		"",
		"You have [b]5 Moves[/b]. A 90 and a 180 each cost one. Spend them anywhere -- even in mid-air, "
			+ "so you can chain a wall into a ceiling. Falling into empty space is allowed: you fall until you hit something.",
		"Shafts go [b]up[/b]. The only way to climb one is to flip your gravity and fall upward. "
			+ "A green [b]SHORTCUT[/b] ring under a shaft means that Move saves a long walk.",
		"",
		"[font_size=24]%sYour gravity is private[/color][/font_size]" % S,
		"A Move rotates [b]only you[/b]. A bot can be running on the ceiling above you while you walk the floor. "
			+ "The world never turns. Each racer leaves a faint trail flat on the surface they are running on.",
		"",
		"[font_size=24]%sHearts and hazards[/color][/font_size]" % E,
		"5 hearts. At zero you are out and can spectate. A 180 into a bottomless void costs one heart and returns you to safe ground.",
		"    [b]Fire[/b] burns half a heart a second. Walk the clear edge, or rotate onto a wall and walk over it.",
		"    [b]Pistons[/b] glow and shudder, then slam down the middle of a corridor. Time it, or run the wall.",
		"    [b]Spiders[/b] patrol the world floor and lunge. They cannot reach you on a wall or the ceiling.",
		"    [b]Cracked glowing floors[/b] over holes crumble a moment after you touch them.",
		"    [b]Wind[/b] pushes along a corridor: free speed one way, a fight the other.",
		"    [b]Blue chevron pads[/b] give a short speed boost.",
		"",
		"[font_size=24]%sMystery boxes[/color][/font_size]" % E,
		"Heart refill, Move refill, speed boost, shield, or a rare [b]Second Chance[/b] that survives one fatal hit -- "
			+ "or a slow, or a drained Move. Very rarely, a [b]clue[/b] points roughly toward the exit.",
		"Dead ends hide boxes more often than corridors do.",
		"",
		"[font_size=24]%sDOF -- degrees of freedom[/color][/font_size]" % S,
		"The HUD shows [b]DOF 1, 2 or 3[/b]: how many axes you can travel along right here. "
			+ "A tunnel is DOF 1. A junction with a shaft is DOF 3. More freedom means more routes -- "
			+ "but the vertical ones cost Moves.",
		"",
		"[font_size=24]%sModes[/color][/font_size]" % E,
		"Set bots to zero for a [b]Time Trial[/b]. Finish a cave faster than before and your [b]ghost[/b] races you next time. "
			+ "[b]Daily[/b] gives everyone the same cave today. Share a seed and size to race a friend's cave.",
	]))
