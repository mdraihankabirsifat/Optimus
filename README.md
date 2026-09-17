# Six Ways Down

A race through a procedurally generated cave where **gravity is yours alone**.
Made by Team Optimus for the BUET Robotics Society GameJam, Intra BUET Robo Challenge 2026.

**Theme:** Degree of Freedom

Two to five racers spawn in the same seeded, block-built cave. Nobody knows where the exit is.
Each racer carries **5 Gravity Moves**: rotate your *personal* gravity 90° to walk on a wall, or
180° to make the ceiling your floor. Nobody else's gravity changes, and the world never turns.
First to the hidden amber pillar wins.

**Team Optimus:** Md. Raihan Kabir Sifat · Estiak Zaman Atul · Sadman Sakib · Ashraf Hossain Chowdhury

## How the theme is the game

- **Translational freedom is the map.** A tunnel is DOF 1, a crossroads DOF 2, a junction with a
  shaft DOF 3. The HUD shows this number live, computed from the cave around you.
- **Rotational freedom is the mechanic.** Rotate your own gravity to any of six directions.
- **Freedom costs something.** Five Moves. Vertical routes demand them.
- **Freedom is personal.** Two racers in one corridor can stand on different surfaces.

## Features

- Gravity-relative first-person movement, 90° and 180° Gravity Moves on any surface or mid-air
- Seeded procedural cave: loops, branches, dead ends, shafts, landmarks, 3 sizes, daily seed
- Four environments: Stone Age, Jungle, Dark Cave (carry a lamp), City Drain. Same seed, same cave in each
- Gravity-aware solvability: every cave is proven reachable within 5 Moves, no loot needed
- Hazards: fire, pistons, spiders, crumbling floors, wind; boost pads
- Mystery boxes: Heart Refill, Move Refill, speed, shield, Second Chance, penalties, rare clues
- 5 hearts with half-hearts, elimination, spectator camera
- Bots that only know what they have seen, use Moves and their own clues, three skill levels
- **Bot Race** offline, **Online Race** 2-5 humans, **Mixed Race** humans + bots, room codes
- Authoritative WebSocket server; runs from the exe, from source, or in Docker for Render
- HUD with DOF readout, gravity preview, racer list, discovered-only map; ghost of your best run
- Synthesised music and sound; no third-party assets

## Game modes

| Mode | Racers | Needs |
|---|---|---|
| Bot Race | you + 0-4 bots (0 is Time Trial) | nothing, fully offline |
| Online Race | 2-5 humans | a server |
| Mixed Race | 2-5 racers, at least one human, fill empty slots with bots | a server |

Every race has 2-5 racers. The host sets the count, adds or removes bots, picks the cave and starts.

## Controls

| Input | Action |
|---|---|
| Mouse | Look |
| W A S D | Walk |
| Shift | Sprint |
| Space | Jump (tap for a hop) |
| **G + W / A / S / D** | Gravity Move: rotate 90° toward that side of your view |
| **G + Space** | Gravity Move: flip 180° (ceiling becomes floor) |
| E | Open a mystery box |
| M | Discovered-only map |
| 1 2 3 | Emotes |
| Esc | Menu (offline it pauses; online the race keeps running) |
| Tab | Next racer while spectating |
| Enter | End the race early once you are done (offline) |

Keys can be remapped in Settings. Invert Y, sensitivity, volumes, window size and quality too.

## Rules at a glance

- 5 hearts (half-hearts exist) and 5 Moves. A 90° and a 180° both cost one Move.
- Moves work anywhere, even mid-air. Shifting into empty space is legal: you fall.
- A 180° into a void costs one heart and returns you to safe ground. It never eliminates you outright.
- Fire burns half a heart per tick. Walk the clear edge, or shift onto a wall and walk over it.
- Heart Refill never brings back an eliminated racer.
- The exit is never shown on the HUD or the map. Clues are rare and coarse.

## Run it

**Exported builds:** `builds/windows/SixWaysDown.exe` (single file), or serve `builds/web/` over HTTP.

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
`SixWaysDown.exe --headless -- --server --port=8910`.

### Docker and Render

```bash
docker build -t six-ways-down-server .
docker run --rm -p 8910:8910 six-ways-down-server
```

Render: New, Blueprint, pick this repository (`render.yaml`), or a Docker web service from the
root `Dockerfile`. Players connect to `wss://<service>.onrender.com`. Full steps and free-tier
caveats: [docs/NETWORKING.md](docs/NETWORKING.md). No secrets are needed or stored.

### Export

Needs the 4.7.2 export templates (Editor, Manage Export Templates):

```bash
godot --headless --export-release "Windows Desktop" builds/windows/SixWaysDown.exe
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
