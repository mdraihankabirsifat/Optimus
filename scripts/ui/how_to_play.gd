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
		"[b]Mouse[/b] look    [b]%s %s %s %s[/b] walk    [b]%s[/b] sprint    [b]%s[/b] jump (tap for a hop)    " % [k("move_forward"), k("move_left"), k("move_back"), k("move_right"), k("sprint"), k("jump")]
			+ "[b]%s[/b] open a mystery box    [b]%s[/b] trade a heart for a Move" % [k("interact"), k("exchange_heart")],
		"[b]%s[/b] map    [b]%s %s %s[/b] emotes    [b]%s[/b] pause    [b]%s[/b] / [b]%s[/b] after you finish: next racer / end the race" % [k("toggle_map"), k("emote_1"), k("emote_2"), k("emote_3"), k("pause"), k("spectate_next"), k("skip_wait")],
		"",
		"[font_size=24]%sThe Gravity Move[/color][/font_size]" % S,
		"Hold [b]%s[/b] and tap a direction. Your gravity rotates and that surface becomes your floor." % k("gravity_mod"),
		"    [b]%s + %s / %s / %s / %s[/b]   rotate 90 degrees toward that side of your view -- walk on walls" % [k("gravity_mod"), k("move_forward"), k("move_left"), k("move_back"), k("move_right")],
		"    [b]%s[/b]   flip 180 degrees -- the ceiling becomes your floor" % UiKit.chord_text("gravity_mod", "jump"),
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
		"[font_size=24]%sTrading a heart for a Move[/color][/font_size]" % E,
		"Out of Moves? Press [b]%s[/b] to trade [b]one full heart[/b] for [b]one Move[/b]. " % k("exchange_heart")
			+ "You need a whole heart (half a heart is not enough) and room for another Move.",
		"Trading your [b]last heart[/b] still gives you the Move, then [b]20 seconds[/b] before you are eliminated. "
			+ "You must press twice to do it, and [b]the countdown cannot be cancelled[/b] -- not even by a Heart Refill. "
			+ "Reach the exit in time and you qualify as normal.",
		"When the lobby turns on [b]Move regen[/b] (+1 Move every 25 s) trading hearts is switched off.",
		"",
		"[font_size=24]%sNormal and Rush[/color][/font_size]" % S,
		"[b]Normal[/b]: the full cave -- winding tunnels, loops, dead ends -- and [b]no time limit[/b]. The clock counts up.",
		"[b]Rush[/b]: pick [b]3, 5 or 8 minutes[/b]. The cave is easier to read (shorter route, fewer dead ends) and the clock counts down. "
			+ "If two racers qualify in time, the Freedom Duel runs as usual. If time runs out with one qualifier, "
			+ "they are Champion by default; with none, nobody is.",
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
			+ "Online, %s opens the menu but the race keeps running." % k("pause"),
		"Pick an [b]environment[/b] in the lobby: Stone Age, Jungle, Dark Cave (you carry a lamp) or City Drain. "
			+ "It changes the look, never the cave: the same seed is the same race in all four.",
		"",
		"[font_size=24]%sThe Freedom Duel[/color][/font_size]" % E,
		"[b]Qualified 1st[/b] waits safely in the duel arena under the cave. When [b]Qualified 2nd[/b] arrives, "
			+ "both get [b]5 fresh hearts[/b] and fight. Everyone else watches. Gravity Moves play no part here.",
		"    [b]Qualified 1st starts with 3DOF[/b]: walk and [b]jump[/b] onto the high platforms.",
		"    [b]Qualified 2nd starts with 2DOF[/b]: walk, no jump (the ramps still reach the high ground) -- "
			+ "plus a [b]one-hit shield[/b].",
		"    [b]%s[/b] Pulse Blaster: steady damage on a short cooldown." % k("duel_fire"),
		"    [b]%s[/b] Axis Lock: takes one degree of freedom from your opponent for 3 seconds " % k("duel_lock")
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
		"Finished or out of hearts? The camera follows another racer in their own gravity. [b]%s[/b] switches racer. " % k("spectate_next")
			+ "During the Freedom Duel it follows the two finalists.",
	]))


## The player's current binding for an action, so this page follows remapping.
static func k(action: String) -> String:
	return UiKit.binding_text(action)
