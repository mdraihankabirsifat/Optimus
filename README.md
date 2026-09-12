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

## Credits

- Team: Optimus
- Team members: To be added
- Third-party assets: None in Phase 1
- Substantial AI-assisted material: To be documented by the team
