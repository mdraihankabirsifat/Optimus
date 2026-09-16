# Six Ways Down

A race through a procedurally generated cave where **gravity is yours alone**.
Made by Team Optimus for the BUET Robotics Society GameJam 2026.

**Theme:** Degree of Freedom

You and up to four bots spawn in the same seeded cave. Nobody knows where the exit is. Each
racer carries **5 Gravity Moves**: rotate your *personal* gravity 90° to walk on a wall, or
180° to make the ceiling your floor. Nobody else's gravity changes. First to the hidden amber
pillar wins.

## Controls

| Input | Action |
|---|---|
| Mouse | Look |
| W A S D | Walk |
| Shift | Sprint |
| Space | Jump |
| **G + W / A / S / D** | Gravity Move: rotate 90° toward that side of your view |
| **G + Space** | Gravity Move: flip 180° (ceiling becomes floor) |
| E | Open a mystery box |
| Esc | Pause (resume, settings, restart, quit) |
| Tab | Next racer while spectating |
| Enter | End the race early once you have finished or been eliminated |

## Rules at a glance

- 5 hearts (half-hearts exist) and 5 Moves. A 90° and a 180° both cost one Move.
- Moves work anywhere, even mid-air. Shifting into empty space is legal: you fall.
- A 180° into a bottomless void costs one heart and returns you to safe ground. It never
  eliminates you outright.
- Fire burns half a heart per second. Walk around it, or shift onto a wall and walk over it.
- Mystery boxes: heart refill, Move refill, speed boost, shield, slow, lose a Move, or a rare
  coarse clue toward the exit.
- The HUD shows **DOF 1/2/3**: how many axes you can travel along at your current cell.
- Bots only know the parts of the cave they have personally seen. Pick Easy, Normal or Hard.

## Running

**Exported builds:** open `builds/windows/SixWaysDown.exe`, `builds/macos/SixWaysDown.zip`, or
serve `builds/web/` over HTTP.

**From source:** install Godot 4.7.2 (standard build, GL Compatibility renderer), then:

```bash
godot                      # play from the splash screen
godot --editor             # open the project
```

Exporting needs the 4.7.2 export templates (Editor → Manage Export Templates), then:

```bash
godot --headless --export-release "Windows Desktop" builds/windows/SixWaysDown.exe
godot --headless --export-release "Web" builds/web/index.html
godot --headless --export-release "macOS" builds/macos/SixWaysDown.zip
```

## Tests

Each exits non-zero on failure. After adding a script with a new `class_name`, run
`godot --headless --editor --quit` once first or headless runs hang silently.

```bash
godot --headless res://tests/test_gravity.tscn   # 150 assertions, all six orientations
godot --headless res://tests/test_cave.tscn      # 200 seeds: connected, solvable in 5 Moves
godot --headless res://tests/test_match.tscn     # countdown, placements, elimination
godot --headless res://tests/test_bot.tscn       # bot knowledge isolation, 60 caves solved
godot --headless res://tests/test_flow.tscn      # every screen, lobby → race → results
godot --headless res://tests/race_diag.tscn -- skill=0   # watch a full bot race
godot res://tests/ui_shot.tscn                   # screenshots into tests/shots/
```

## Project structure

```
autoload/        AppConfig (tunables), GameState, SettingsManager, AudioManager, SceneRouter, NetManager (stub)
scripts/player/  PlayerController, GravityController, PlayerHealth, CameraController, PlayerInteraction
scripts/cave/    CaveGraph (data), CaveGenerator (seeded), CaveBuilder (geometry, hazards, boxes, decor)
scripts/gameplay/ GameWorld, MatchController, FireHazard, MysteryBox
scripts/bots/    BotKnowledge (discovered graph only), BotPlanner, BotController
scripts/ui/      UiKit (shared look), RaceHUD, PauseMenu, one script per menu screen
docs/            CORE_MECHANICS, ARCHITECTURE, MVP_SCOPE, TASK_BOARD
```

All geometry, textures, music and sound effects are generated in code. The build ships no
third-party assets.

## Known issues

- Online multiplayer is not included. It was Tier 3 behind an abort gate; offline Bot Race is
  the complete game.
- Bots only use 180° inversions, never 90° wall-walks. The cave's vertical structure is Y-only,
  so inversion is always the right tool for them.
- The player capsule dips about 0.3 units into the floor mid-rotation. It corrects on completion.
- Bots walk straight through fire rather than routing around it, and can occasionally be
  eliminated by it.
- Decor (stalagmites, crystals) has no collision.

## Team

- Md. Raihan Kabir Sifat
- Estiak Zaman Atul
- Sadman Sakib
- Ashraf Hossain Chowdhury
