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
		"The exit does not crown a winner. The [b]first two[/b] racers to reach it [b]qualify for the Freedom Duel[/b], "
			+ "and the duel decides the [b]Champion[/b].",
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
		"[b]Bot Race[/b] works offline: you against 0-4 bots. Zero bots is a [b]Time Trial[/b], and beating your best "
			+ "on a cave saves a [b]ghost[/b] that races you next time. [b]Daily[/b] gives everyone the same cave today.",
		"[b]Online Race[/b]: 2-5 humans. One player creates a room and shares its four-letter code; the others join with it. "
			+ "[b]Mixed Race[/b] adds bots -- the host can [b]fill empty slots with bots[/b]. "
			+ "Online, Esc opens the menu but the race keeps running.",
		"Pick an [b]environment[/b] in the lobby: Stone Age, Jungle, Dark Cave (you carry a lamp) or City Drain. "
			+ "It changes the look, never the cave: the same seed is the same race in all four.",
		"",
		"[font_size=24]%sThe Freedom Duel[/color][/font_size]" % E,
		"[b]Qualified 1st[/b] waits safely in the duel arena under the cave. When [b]Qualified 2nd[/b] arrives, "
			+ "both get [b]5 fresh hearts[/b] and fight. Everyone else watches. Gravity Moves play no part here.",
		"    [b]Qualified 1st starts with 3DOF[/b]: walk and [b]jump[/b] onto the high platforms.",
		"    [b]Qualified 2nd starts with 2DOF[/b]: walk, no jump (the ramps still reach the high ground) -- "
			+ "plus a [b]one-hit shield[/b].",
		"    [b]Left mouse[/b] Pulse Blaster: steady damage on a short cooldown.",
		"    [b]Right mouse / Q[/b] Axis Lock: takes one degree of freedom from your opponent for 3 seconds "
			+ "(3DOF loses the jump; 2DOF is pinned to one axis). They are immune to another lock for a moment after.",
		"    The gold [b]Freedom Core[/b] appears every few seconds: grab it for [b]+1 DOF[/b] for a while "
			+ "(already at 3DOF, you get a shield).",
		"    Every so often the arena shifts: [b]FULL FREEDOM[/b], [b]Y AXIS LOCKED[/b] or [b]FREEDOM SURGE[/b].",
		"    After a minute, [b]SUDDEN DEATH[/b]: both 3DOF, no shields, hits hurt more. "
			+ "If nobody falls, most hearts wins at the time limit.",
		"Results: the duel winner is [b]Champion[/b], the loser 2nd, then everyone else in cave order. "
			+ "If nobody else can reach the exit, Qualified 1st is Champion by default.",
		"",
		"[font_size=24]%sSpectating[/color][/font_size]" % S,
		"Finished or out of hearts? The camera follows another racer in their own gravity. [b]Tab[/b] switches racer. "
			+ "During the Freedom Duel it follows the two finalists.",
	]))
