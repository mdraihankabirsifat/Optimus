# Escave

A race through a procedurally generated cave where **gravity is yours alone**.
Made by Team Optimus for the BUET Robotics Society GameJam, Intra BUET Robo Challenge 2026.

**Theme:** Degree of Freedom

Two to five racers spawn in the same seeded, block-built cave. Nobody knows where the exit is.
Each racer carries **5 Gravity Moves**: rotate your *personal* gravity 90° to walk on a wall, or
180° to make the ceiling your floor. Nobody else's gravity changes, and the world never turns.
The first two to reach the hidden amber pillar qualify for the **Freedom Duel**: a short arena
fight where getting out first earned you the third degree of freedom, and the winner is Champion.

**Team Optimus:** Md. Raihan Kabir Sifat · Estiak Zaman Atul · Sadman Sakib · Ashraf Hossain Chowdhury

## How the theme is the game

- **Translational freedom is the map.** A tunnel is DOF 1, a crossroads DOF 2, a junction with a
  shaft DOF 3. The HUD shows this number live, computed from the cave around you.
- **Rotational freedom is the mechanic.** Rotate your own gravity to any of six directions.
- **Freedom costs something.** Five Moves. Vertical routes demand them.
- **Freedom is personal.** Two racers in one corridor can stand on different surfaces.
- **Freedom is the prize.** In the Freedom Duel, Qualified 1st starts with 3DOF (move and jump),
  Qualified 2nd with 2DOF. An Axis Lock takes an axis away; a Freedom Core gives one back.

## Features

- Gravity-relative first-person movement, 90° and 180° Gravity Moves on any surface or mid-air
- Seeded procedural cave that feels like a cave: long narrow tunnels, real loops, dead ends,
  routes that climb and descend, chambers, landmarks, 3 sizes, daily seed
- **Freedom Duel** finale: 3DOF vs 2DOF, Pulse Blaster, Axis Lock, Freedom Core, arena DOF shifts,
  sudden death, spectator view of both finalists, bots that fight
- Four environments: Stone Age, Jungle, Dark Cave (carry a lamp), City Drain. Same seed, same cave in each
- Gravity-aware solvability: every cave is proven reachable within 5 Moves, no loot needed
- Hazards: fire, pistons, spiders, crumbling floors, wind; boost pads
- Mystery boxes: Heart Refill, Move Refill, speed, shield, Second Chance, penalties, and clues that name the exit's compass direction, how many levels up or down it is, and roughly how many rooms away
- 5 hearts with half-hearts, elimination, spectator camera
- Bots that only know what they have seen, use Moves and their own clues, three skill levels
- **Bot Race** offline, **Online Race** 2-5 humans, **Mixed Race** humans + bots, room codes
- Authoritative WebSocket server; runs from the exe, from source, or in Docker for Render
- HUD with DOF readout, gravity preview, racer list, corner mini-map and a full discovered-only map; ghost of your best run
- Synthesised music and sound; no third-party assets

## Game modes

| Mode | Racers | Needs |
|---|---|---|
| Bot Race | you + 0-4 bots (0 is Time Trial) | nothing, fully offline |
| Online Race | 2-5 humans. **Create Arena** gives you a 4-character code (Copy Code); friends choose **Join Arena** and type it | a server |
| Mixed Race | 2-5 racers, at least one human, fill empty slots with bots | a server |
| Battle Mode | 2-5 fighters, timed free-for-all, most kills wins | a server (Online or Mixed) |

Every race has 2-5 racers. The host sets the count, adds or removes bots, picks the cave and starts.

## Controls

| Input | Action |
|---|---|
| Mouse | Look |
| W A S D | Walk |
| Shift | Sprint -- **only while a Sprint Gift is running**, and only for 5 seconds |
| Space | Jump (tap for a hop) |
| **G + W / A / S / D** | Gravity Move: rotate 90° toward that side of your view |
| **G + Space** | Gravity Move: flip 180° (ceiling becomes floor) |
| E | Open a mystery box |
| M | Full map of the level you are on (a small one is always in the corner) |
| 1 2 3 | Emotes |
| Esc | Menu (offline it pauses; online the race keeps running) |
| Tab | Next racer while spectating |
| Enter | End the race early once you are done (offline) |
| **H** | Trade one full heart for one Move (off when Move regen is on) |
| **Left mouse** | Freedom Duel: Pulse Blaster (hold to repeat) |
| **Right mouse / Q** | Freedom Duel: Axis Lock |

These are the default keys. Every key can be remapped in Settings, and every hint in the game
(box prompt, gravity preview, spectator and duel lines, map, tips, How to Play) shows the key you
actually bound, the moment you change it. Settings also has invert Y, sensitivity, volumes,
fullscreen and graphics quality. There is no window-size option: turn fullscreen off for a normal
window with a title bar, and resize or maximise it like any other. Running from source, F3 shows the
developer overlay; exported builds do not have it.

The HUD has a **compass** fixed to the world (N is -Z, E is +X). Changing your gravity never renames
north, so a racer on the ceiling facing the same way as one on the floor reads the same bearing. It
shows only your own facing, never the exit.

## Rules at a glance

- **Enter your name** on the Play screen before any race (1-20 characters, any language). It is saved
  and shown everywhere, offline and online.
- **Normal, Rush or Battle.** Offline Bot Race is Normal or Rush; Battle is an online or mixed
  room (bots may fill the empty slots). Normal: the full cave, no time limit, the clock counts up.
  Rush: 3, 5 or 8 minutes on an easier cave (about 40% shorter route, a third to half the dead ends).
  If time runs out with one qualifier they are Champion by default; with none, nobody is.
- **Battle Mode**: 3, 5 or 8 minutes in a cave with no exit. Kill a rival with the Pulse Blaster for
  one point. Losing your hearts is not elimination: you respawn 3 seconds later, far from whoever
  killed you, with 2 seconds of spawn protection, full hearts and full Moves. Dying to the cave costs
  you a death and gives nobody a point. Most kills when the clock stops wins; ties go to fewer deaths,
  then to whoever reached the score first, and a full tie is a draw. No qualification, no Freedom Duel,
  no Champion, and no heart trading.
- **Sprint Gifts**: Shift on its own does nothing. Walk into a green Sprint Gift and Shift sprints for
  exactly 5 seconds -- the HUD counts it down. A second gift refreshes the 5 seconds, it never stacks,
  and the window runs out even while you hold Shift. Gifts grow back 15 seconds after they are taken.
- **Trade a heart for a Move** (H): one full heart for one Move. Trading your last heart still gives
  the Move, then 20 seconds before elimination -- press twice, it cannot be cancelled, reaching the exit
  in time qualifies you as normal. Switched off when Move regen is on.
- Racers are **solid**: you cannot walk through another racer. Finished and eliminated racers stop
  blocking. Stalagmites and stalactites (only in landmark chambers) are solid and sting; crystals are solid.
- Floor fire is low enough to pass over on the ceiling or along the clear wall.

- 5 hearts (half-hearts exist) and 5 Moves. A 90° and a 180° both cost one Move.
- Moves work anywhere, even mid-air. Shifting into empty space is legal: you fall.
- A 180° into a void costs one heart and returns you to safe ground. It never eliminates you outright.
- Fire burns half a heart per tick. Walk the clear edge, or shift onto a wall and walk over it.
- Heart Refill never brings back an eliminated racer.
- The exit is never shown until you find it. The map draws only rooms you have walked and the
  openings you saw from them; it marks the exit only once you have stood in it or looked into it
  from next door, and it marks passages you have not taken yet so you can see where there is
  still something to find. A clue from a mystery box gives a compass direction, how many levels
  up or down, and a rough number of rooms -- never the cell and never a path.
- The first finisher is **Qualified 1st**, not the winner: they wait safely in the duel arena. The
  second finisher starts the **Freedom Duel**; everyone else stops and watches.
- Duel: 5 fresh hearts each, no Gravity Moves. Qualified 1st 3DOF, Qualified 2nd 2DOF plus a one-hit
  shield. Axis Lock removes a DOF for 3 s, with immunity after. Freedom Core: +1 DOF for 8 s.
  Sudden death at 60 s, decided on hearts at 90 s.
- Results: Champion, duel runner-up, then cave order. If nobody else can reach the exit,
  Qualified 1st is Champion by default.

## Run it

**Exported builds:** `builds/windows/Escave.exe` (single file), or serve `builds/web/` over HTTP.

**From source:** install Godot 4.7.2 (standard build, GL Compatibility renderer).

```bash
godot                      # play: splash, menu, Play
godot --editor             # open the project 
```

### Local Bot Race

Play, Bot Race, choose bots, skill, cave size and seed, Start Race. No network involved.

### Local online race (server + two clients)

```bash
godot --headless --path . -- --server --port=8910          # the server
godot --path .                                             # client 1
godot --path .                                             # client 2
```

In each client: Play, Mixed Race or Online Race, server `ws://127.0.0.1:8910`, Connect. One
creates a room; the other types its code. With the exported exe:
`Escave.exe --headless -- --server --port=8910`.

### Docker and Render

```bash
docker build -t escave-server .
docker run --rm -p 8910:8910 escave-server
```

Render: New, Blueprint, pick this repository (`render.yaml`), or a Docker web service from the
root `Dockerfile`. Players connect to `wss://<service>.onrender.com`. Full steps and free-tier
caveats: [docs/NETWORKING.md](docs/NETWORKING.md). No secrets are needed or stored.

### Export

Needs the 4.7.2 export templates (Editor, Manage Export Templates):

```bash
godot --headless --export-release "Windows Desktop" builds/windows/Escave.exe
godot --headless --export-release "Web" builds/web/index.html
```

## Tests

```bash
godot --headless --editor --quit                  # once, after adding a class_name script
godot --headless res://tests/test_gravity.tscn
godot --headless res://tests/test_cave.tscn
godot --headless res://tests/test_match.tscn
godot --headless res://tests/test_bot.tscn
godot --headless res://tests/test_flow.tscn
godot --headless res://tests/test_wallwalk.tscn
godot --headless res://tests/test_themes.tscn
godot --headless res://tests/test_net_lobby.tscn
godot --headless res://tests/test_net_sim.tscn
godot --headless res://tests/test_net.tscn         # real server + two clients over WebSocket
```

Latest results and coverage: [docs/TESTING.md](docs/TESTING.md).

## Project structure

```
autoload/        AppConfig, GameState, SettingsManager, AudioManager, SceneRouter, NetManager
scenes/          ui/ screens, game/game_world.tscn, player/, bots/, net/server.tscn
scripts/player/  PlayerController, GravityController, PlayerHealth, CameraController, rig
scripts/cave/    CaveGraph, CaveGenerator, CaveValidator, CaveBuilder
scripts/gameplay/ GameWorld (offline/client/server roles), MatchController, hazards, boxes, WorldScope
scripts/bots/    BotKnowledge (discovered graph only), BotPlanner, BotController
scripts/net/     LobbyState, NetMatch, server entry point
scripts/ui/      UiKit, HUD, pause menu, one script per screen
tests/           headless test suites and screenshot harnesses
docs/            CORE_MECHANICS, ARCHITECTURE, NETWORKING, CAVE_GENERATION, TESTING,
                 SUBMISSION_CHECKLIST, MVP_SCOPE, TASK_BOARD
```

## Known limitations

- The online server has not been deployed to Render by the team; it runs locally, from the exe and in Docker.
- A free Render server sleeps when idle; the first connection can take up to a minute.
- Online play cannot be joined mid-race, and a dropped client cannot rejoin its race.
- Bots turn onto walls only when it saves a Move, which is rare, so most bot Moves are 180° flips.
- The player capsule dips about 0.3 units into the floor mid-rotation; it corrects on completion.
- Decor (stalagmites, crystals) has no collision.
- Environments change the look only. Stone Age is the most polished; Jungle, Dark Cave and City Drain reuse its decor with new materials, lighting and one signature prop each.
- The Windows build has been run on a development machine, not yet on a clean one.

## Credits and AI

[CREDITS.md](CREDITS.md) · [AI_DISCLOSURE.md](AI_DISCLOSURE.md) ·
[future_implementation_suggestion.txt](future_implementation_suggestion.txt)

## Submission

Checklist, screenshot list, video shot list and itch.io copy:
[docs/SUBMISSION_CHECKLIST.md](docs/SUBMISSION_CHECKLIST.md)

- itch.io page: _to be added_
- GitHub: https://github.com/mdraihankabirsifat/Optimus
