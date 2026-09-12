# Project DOF

Project DOF is Team Optimus's Phase 1 prototype for the **Degrees of Freedom** game-jam theme. It is a local two-player sci-fi sandbox proving that each robot can have mechanically enforced movement constraints while the surrounding game shell remains ready for extension.

## Phase 1 features

- Polished keyboard-navigable menu flow: Play, Settings, About, mode selection, and level selection
- Three data-driven difficulties: Easy, Difficult, and Hard
- Three arenas with progressive unlocks and per-difficulty/per-level high scores
- One reusable player scene supporting 1, 2, or 3 degrees of freedom
- Two-player local collection test with health, hazards, timer, scoring, pause, restart, and results
- Persistent audio, mute, fullscreen, selection, unlock, and score data
- Explicit networking boundary for a future authoritative hosted game
- Procedural visuals with no third-party asset dependency

## Controls

| Action | Player 1 | Player 2 |
|---|---|---|
| Move X | A / D | Left / Right |
| Move Y (2+ DOF) | W / S | Up / Down |
| Rotate (3 DOF) | Q / E | Comma / Period |
| Pause / Back | Escape | Escape |

The local prototype starts Player 1 at 1 DOF and Player 2 at 2 DOF. Pause the arena to cycle either player through all three values for testing. Movement that a DOF value does not permit is ignored inside the player controller itself.

## Open and run

1. Install Godot 4.7.2 Standard.
2. Import `project.godot` from the repository root.
3. Keep the renderer set to Compatibility.
4. Press **F6** on an individual scene or **F5** for the full menu flow.
5. Choose **Play → Local Prototype → difficulty → level**.

For command-line validation on the configured development machine:

```powershell
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --quit
```

## Save data

Godot stores both files in the platform-specific `user://` directory:

- `settings.cfg`: volume, mute, and fullscreen preferences
- `save_data.cfg`: high scores, unlock progress, and last selections

Both use human-readable `ConfigFile` syntax. Missing or malformed values fall back to safe defaults.

## Export notes

- Windows target: x86_64, Compatibility renderer. A desktop build shows the Quit and fullscreen controls.
- Web target: Single-Threaded, Compatibility renderer. Quit is hidden and desktop fullscreen settings are omitted.
- No export presets or generated builds are committed yet. Create local presets in Godot's Export dialog when needed.

## Current limitations

This is deliberately a neutral prototype, not a final combat or objective mode. Energy nodes and hazards are replaceable tests. Hosted multiplayer, matchmaking, real rooms, server deployment, reconnects, and authoritative validation are planned for Phase 2 and are not presented as working features.

See [NETWORKING_PLAN.md](NETWORKING_PLAN.md) for the proposed online architecture.

## Separate 3D greybox (2.5D gameplay)

The original 2D prototype remains the default local mode. The additional 3D
experiment uses primitive robot meshes, a fixed elevated orthographic camera,
a flat X/Z arena, colliding floor/walls, basic lighting, and two local players.
This restricted 2.5D approach keeps camera and elevation mechanics out of scope
for the Thursday deadline. No plugins, external art, or paid assets are needed.

### Launch

1. Open `project.godot` with Godot 4.7.2 Standard, Compatibility renderer.
2. Press **F5**, choose **Play**, then **3D PROTOTYPE**.
3. Or open `scenes/game/prototype_arena_3d.tscn` and press **F6**.
4. Original mode: **F5 > Play > Local Prototype > difficulty > level**.

The 3D menu entry uses your last saved difficulty and level. To change these,
use the existing Local Prototype selection screens first. Direct F6 uses the
session defaults (Easy / Level 1 on a fresh run). Existing difficulty data controls
round time, speed, and hazard damage; level controls hazard count in one chamber.
The existing menu, settings, save format, and 2D high scores/unlocks remain intact.
**3D scores are session-only** and do not modify 2D records or unlock progress.

### Controls and temporary role experiment

| Action | Player 1 | Player 2 |
|---|---|---|
| World X | A / D | Left / Right |
| World Z (2+ DOF) | W / S | Up / Down |
| Yaw around vertical Y (3 DOF) | Q / E | Comma / Period |
| Pause/resume; role tools | Escape | Escape |

Pause offers Resume, cycle either player's DOF, Restart Arena, and Return to Menu.
The HUD and labels above each robot show current DOF. The orange nose shows facing.
1 DOF starts on the cyan X-axis lane; changing to 1 DOF locks the current Z lane.
Movement uses world axes even after turning. The controller rejects forbidden
commands and collision-induced elevation/Z movement. Robots collide with walls;
they intentionally pass through each other to avoid blocking a restricted role.

Hold within 1.5 units of a green station to earn points. Stations recharge for
1.5 seconds after collection. Red tiles deal damage with a 0.7-second cooldown.
Time expiry or either player's health reaching zero ends the round.

- **1 DOF:** earns 10 points in 0.45 seconds; two stations are reachable on its starting lane.
- **2 DOF:** earns 10 points in 0.9 seconds from any facing and can reach off-lane stations.
- **3 DOF:** earns 20 points in 1.2 seconds but must aim its orange nose toward the station.

These are implemented balancing experiments, not final role balance or a final
win condition. More DOF adds access and aiming responsibility rather than a pure
upgrade. The greybox has no animation, sound assets, jumping, camera controls,
final combat, or separate authored levels. **Hosted multiplayer is not implemented.**
NetworkManager remains a placeholder. Windows/Web exports and browser performance
still need actual device testing; this change does not add export presets.

### Automated validation

Run from the repository root in PowerShell:

```powershell
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --quit
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --scene res://tests/phase1_smoke.tscn
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --scene res://tests/prototype_3d_smoke.tscn
```

Expected markers: `PHASE1_SMOKE_OK` and `PROTOTYPE_3D_SMOKE_OK`, with no script or
engine errors. The original test backs up/restores user files; the 3D test does not
write scores/settings. It checks DOF restrictions, walls, harvesting/facing,
damage cooldown, pause/resume, timer and health end conditions.

## Credits

- Team: Optimus
- Team members: To be added
- Third-party assets: None in Phase 1
- Substantial AI-assisted material: To be documented by the team
