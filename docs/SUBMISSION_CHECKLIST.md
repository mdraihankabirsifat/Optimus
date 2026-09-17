# SUBMISSION CHECKLIST

Deadline: **17 September 2026, 11:59 PM** on the official itch.io jam page.
Showcase: 18 September 2026, 10:00 AM, ECE Building, BUET.
After submitting, the build and the final commit are frozen.

---

## Before submitting

### Build
- [ ] Pull `main` on the machine that will export. Run the headless test suites (docs/TESTING.md).
- [ ] Export Windows: `godot --headless --export-release "Windows Desktop" builds/windows/SixWaysDown.exe`
- [ ] Copy `SixWaysDown.exe` to a Windows machine **without Godot**. Launch, play one Bot Race to results.
- [ ] Export Web: `godot --headless --export-release "Web" builds/web/index.html`
- [ ] If submitting web: upload `builds/web` as a zip on itch.io, "This file will be played in the browser",
      enable SharedArrayBuffer only if the page needs it (the export has threads off, so it does not).
      Play one Bot Race in Chrome from the itch.io page.
- [ ] Zip the Windows exe as `SixWaysDown-Windows.zip` and upload.
- [ ] Check no secrets or private URLs: `git grep -iE "token|secret|password|apikey"` should find only docs.

### Online (optional for judging)
- [ ] Deploy the server to Render (docs/NETWORKING.md). Note its `wss://` address.
- [ ] Two machines: Play, Mixed Race, that address, create and join a room, race to results.
- [ ] If it works, put the address on the itch.io page. If not, say online needs a local server,
      and judge with Bot Race.

### Repository
- [ ] Every commit is inside 10-17 September 2026. Never rewrite history.
- [ ] README, CREDITS.md, AI_DISCLOSURE.md, future_implementation_suggestion.txt up to date.
- [ ] Final commit pushed before the deadline; note its hash on the itch.io page.

### Page and media
- [ ] Title, short description, long description (itch.io copy below)
- [ ] Cover image 630 x 500 and at least 5 screenshots (list below)
- [ ] 60-90 s gameplay video uploaded (YouTube unlisted or itch.io) and linked
- [ ] GitHub link, engine and tools, controls, run instructions, credits, AI disclosure, known bugs,
      team members
- [ ] Submitted to the jam, not only published

### Showcase morning
- [ ] Laptop charged, Windows build on the desktop, mouse plugged in, sound checked
- [ ] Settings: fullscreen on, sensitivity comfortable, bots on Easy for visitors
- [ ] A seed with a short, readable cave noted (Short size, e.g. the daily seed)
- [ ] Visitors restart fast: Esc, Restart (same cave); or results, New Cave

---

## Screenshot list

Capture at 1920 x 1080, HUD visible unless noted. `tests/ui_shot.tscn` and `tests/trailer.gd`
produce some automatically; the rest are quickest by hand.

1. **Three racers on three surfaces** — floor, wall and ceiling of one corridor. The key image.
2. **Mid-shift** — G held, the HUD naming the surface each key would make your floor.
3. **Looking up a shaft** after a 180°, with the DOF 3 readout visible.
4. **Fire you walk over** — standing on a wall above a fire patch.
5. **Mystery box opening** with the reward toast, ideally a rare clue arrow.
6. **The finish** — the amber pillar in its stone ring, a racer arriving.
7. **Qualified 1st** — waiting in the duel arena, the "QUALIFIED 1ST FOR THE FREEDOM DUEL" panel.
8. **Freedom Duel mid-fight** — duel HUD with both finalists' hearts and [X][Y][Z] boxes, a blaster
   tracer, the Freedom Core glowing on a platform.
9. **Axis Lock landing** — violet ring on the target, "Z AXIS LOCKED" callout.
10. **Spectating the duel** — third-person on a finalist, "SPECTATING ... [Tab] switch finalist".
11. **Results** — CHAMPION on top, the runner-up, cave order below, duel stats, the seed.
12. **Online lobby** — room code, 2 humans + 2 bots, colours, ready states.
13. **Main menu** with the logo (cover image source).
14. **Discovered-only map (M)** — only visited cells, no exit.
15. **The four environments** — the same tunnel in each (`godot res://tests/theme_shot.tscn`).

`godot --path . res://tests/duel_shot.tscn` saves waiting, intro, fight and spectator duel frames
to `tests/shots/`.

## 60-90 second video shot list

Target 80 s. Capture 60 fps; no voice-over needed, short on-screen captions instead. The video
must end on the Freedom Duel and the Champion: that is now how every race ends.

| Time | Shot | Caption |
|---|---|---|
| 0-4 s | Logo and title card | SIX WAYS DOWN — Team Optimus |
| 4-9 s | Spawn chamber, countdown 3-2-1-GO, racers burst into a narrow tunnel | Race to a hidden exit |
| 9-17 s | First-person tunnel run, G held, preview labels, G+D: turn onto the wall | 5 Gravity Moves. Your gravity only. |
| 17-23 s | W on the wall walks where you look; past a fire patch below | Walls become floors |
| 23-30 s | G+Space at a shaft, fall upward, land on the ceiling, run a loop back to a known chamber | Ceilings become roads |
| 30-36 s | Spectator: one racer on the floor, one on the wall, one on the ceiling | Freedom is personal |
| 36-41 s | HUD close-up: DOF 1 in a tunnel, DOF 3 at a shaft junction; a mystery box | Degree of Freedom, measured live |
| 41-46 s | Arriving at the amber pillar: QUALIFIED 1ST, the arena, waiting | The first two out qualify |
| 46-50 s | Second racer arrives: QUALIFIED 2ND, FREEDOM DUEL, 3-2-1 | Qualified 1st earned 3DOF |
| 50-60 s | Duel: jump to the platform, blaster tracers, the 2DOF finalist's shield breaking | Pulse Blaster |
| 60-66 s | Axis Lock lands: violet ring, "Y AXIS LOCKED"; the victim grabs the Freedom Core | Take a freedom away. Win one back. |
| 66-71 s | DOF shift banner, then SUDDEN DEATH | Total freedom |
| 71-76 s | Final hit, CHAMPION callout, results table with CHAMPION on top | The duel decides the Champion |
| 76-80 s | Online lobby flash, then title and team names | Bot Race offline · Online and Mixed · BUET Robotics Society GameJam 2026 |

Must show: title, real gameplay from the submitted build, the core loop (explore, shift, qualify,
duel), the major mechanics, and the theme connection.

## itch.io copy

**Title:** Six Ways Down

**Short description (tagline):** Race through a hidden-exit cave where gravity is yours alone.

**Long description:**

> Two to five racers drop into the same procedurally generated block cave. Nobody knows where the
> exit is — not even the bots.
>
> You carry **five Gravity Moves**. Hold **G** and tap a direction: your personal gravity turns 90°
> and a wall becomes your floor. **G + Space** flips you 180° and the ceiling becomes your road.
> Nobody else's gravity changes. The racer beside you can be sprinting along the floor while you run
> the wall above their head.
>
> **Degree of Freedom, as a rule.** A tunnel lets you move along one axis: DOF 1. A crossroads: DOF 2.
> A junction with a shaft: DOF 3, shown live on your HUD. More freedom means more routes, but vertical
> routes cost Moves, and you only have five.
>
> Dodge fire, pistons and spiders in long narrow tunnels, crack open mystery boxes for refills,
> shields, a Second Chance or a rare clue, and find the hidden amber pillar.
>
> **The first two out qualify for the Freedom Duel.** Getting out first earns the third degree of
> freedom: Qualified 1st fights in 3DOF and can jump to the high ground, Qualified 2nd starts in 2DOF
> with a one-hit shield. Blast with the **Pulse Blaster**, strip an axis from your opponent with an
> **Axis Lock**, grab the **Freedom Core** for an extra degree of freedom, survive the arena's DOF
> shifts and sudden death. The winner is Champion. Everyone else watches the final.
>
> - **Bot Race** — offline, you against up to four bots that only know what they have seen
> - **Online Race** — 2-5 humans with a room code
> - **Mixed Race** — humans and bots together; fill empty slots with bots
> - Every cave is seeded and proven solvable within your five Moves
> - Four environments: Stone Age, Jungle, Dark Cave and City Drain
> - Ghost of your best run, daily cave, three cave sizes, three bot skills
>
> **Controls (default, all remappable):** Mouse look · WASD walk · Shift sprint · Space jump · G+WASD turn 90° ·
> G+Space flip 180° · E open box · H trade a heart for a Move · M map · Esc menu · Duel: left mouse Pulse Blaster,
> right mouse or Q Axis Lock
>
> **Normal or Rush:** race the full cave with no clock, or pick Rush for 3, 5 or 8 minutes on an easier cave.
> Create an arena and share its code, or join a friend's.
>
> **Team Optimus:** Md. Raihan Kabir Sifat, Estiak Zaman Atul, Sadman Sakib, Ashraf Hossain Chowdhury
>
> Made in Godot 4.7.2 for the BUET Robotics Society GameJam, Intra BUET Robo Challenge 2026.
> All geometry, textures, music and sound are generated by code. Substantial AI assistance was used
> in development; see AI_DISCLOSURE.md.
>
> **Online play** works in the browser and the Windows build through our public server: choose Online or
> Mixed Race, then Create Arena and share the code, or Join Arena with a friend's code. The first
> connection can take up to a minute while the free server wakes.
>
> **Source:** https://github.com/mdraihankabirsifat/Optimus

**Genre:** Racing · **Tags:** 3D, first-person, gravity, procedural-generation, multiplayer,
local-multiplayer, godot, game-jam · **Engine:** Godot · **Platforms:** Windows, HTML5

## Known bugs (for the page)

- Bots use a 90° wall-walk only when it saves a Move, so they mostly flip 180°.
- The capsule dips slightly into the floor during a gravity turn; it corrects when the turn ends.
- Stalagmites and crystals have no collision.
- Online: a free Render server can take up to a minute to wake; a dropped player cannot rejoin a race
  already running.
- Jungle, Dark Cave and City Drain reuse Stone Age decor with their own materials, light and one signature prop.
- In the narrow tunnels bots finish about three races in four (four Hard bots, 10 test caves); a bot
  that is stuck or eliminated simply does not qualify, and the 90 s qualification limit keeps the
  race moving.
- Racers still in the cave when the Freedom Duel starts stop where they are; they are ranked by how
  close they were to the exit, not by finishing.
- The duel arena is one fixed layout, the same in every environment.
- The free Render server sleeps when idle; the first connection after a quiet spell can take up to a
  minute. Offline Bot Race always works without it.
- The windowed title bar fix (fullscreen off) is verified in code, not yet by a person on a standalone
  Windows build.
- Rival overtake callouts were removed on purpose (team request), not lost.
