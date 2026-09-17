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
7. **Results** — placements, times, a DNF or ELIMINATED, the seed.
8. **Online lobby** — room code, 2 humans + 2 bots, colours, ready states.
9. **Main menu** with the logo (cover image source).
10. **Discovered-only map (M)** — only visited cells, no exit.

## 60-90 second video shot list

Target 75 s. Capture 60 fps; no voice-over needed, short on-screen captions instead.

| Time | Shot | Caption |
|---|---|---|
| 0-4 s | Logo and title card | SIX WAYS DOWN — Team Optimus |
| 4-10 s | Spawn chamber, countdown 3-2-1-GO, racers burst out | Race to a hidden exit |
| 10-20 s | First-person corridor run, G held, preview labels, G+D: turn onto the wall | 5 Gravity Moves. Your gravity only. |
| 20-28 s | Walk along the wall past a fire patch below | Walls become floors |
| 28-36 s | G+Space at a shaft, fall upward, land on the ceiling | Ceilings become roads |
| 36-44 s | Spectator/third-person: one racer on the floor, one on the wall, one on the ceiling | Freedom is personal |
| 44-50 s | HUD close-up: DOF 1 in a tunnel, DOF 3 at a shaft junction | Degree of Freedom, measured live |
| 50-56 s | Mystery box: Move Refill; then a rare clue arrow | Boxes, hazards, rare clues |
| 56-62 s | Spider lunges, piston slams, a heart lost | 5 hearts |
| 62-68 s | Online lobby with room code, then two humans racing | Bot Race offline · Online and Mixed Race |
| 68-73 s | Arriving at the amber pillar, FINISHED 1st, results table | First to the exit wins |
| 73-75 s | Title and team names | BUET Robotics Society GameJam 2026 |

Must show: title, real gameplay from the submitted build, the core loop (explore, shift, find the
exit), the major mechanics, and the theme connection.

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
> Dodge fire, pistons and spiders, crack open mystery boxes for refills, shields, a Second Chance or a
> rare clue, and be first to the hidden amber pillar.
>
> - **Bot Race** — offline, you against up to four bots that only know what they have seen
> - **Online Race** — 2-5 humans with a room code
> - **Mixed Race** — humans and bots together; fill empty slots with bots
> - Every cave is seeded and proven solvable within your five Moves
> - Ghost of your best run, daily cave, three cave sizes, three bot skills
>
> **Controls:** Mouse look · WASD walk · Shift sprint · Space jump · G+WASD turn 90° · G+Space flip 180° ·
> E open box · M map · Esc menu
>
> **Team Optimus:** Md. Raihan Kabir Sifat, Estiak Zaman Atul, Sadman Sakib, Ashraf Hossain Chowdhury
>
> Made in Godot 4.7.2 for the BUET Robotics Society GameJam, Intra BUET Robo Challenge 2026.
> All geometry, textures, music and sound are generated by code. Substantial AI assistance was used
> in development; see AI_DISCLOSURE.md.
>
> **Online play** needs a server: run `SixWaysDown.exe --headless -- --server` on one machine and connect
> to `ws://<its-ip>:8910`, or use the public server address if listed below.
>
> **Source:** https://github.com/mdraihankabirsifat/Optimus

**Genre:** Racing · **Tags:** 3D, first-person, gravity, procedural-generation, multiplayer,
local-multiplayer, godot, game-jam · **Engine:** Godot · **Platforms:** Windows, HTML5

## Known bugs (for the page)

- Bots only use 180° gravity flips, not 90° wall-walks.
- The capsule dips slightly into the floor during a gravity turn; it corrects when the turn ends.
- Stalagmites and crystals have no collision.
- Online: a free Render server can take up to a minute to wake; a dropped player cannot rejoin a race
  already running.
- Jungle, Dark Cave and City Drain environments are planned, not built.
