# SIX WAYS DOWN — Comprehensive Bug Audit & Feature Roadmap

**Date:** 17 September 2026  
**Target:** Team Optimus  
**Engine:** Godot 4.7.2 (GL Compatibility)  
**Status:** Audit complete, game verified running on Apple M4 Metal / GL Compatibility.

---

## 1. Executive Summary & Verification Report

We conducted a complete inspection of the entire codebase and architecture across all subsystems:
- **Player & Physics:** `PlayerController`, `GravityController`, `CameraController`, `PlayerHealth`, `PlayerInteraction`, `RacerRig`.
- **Procedural Generation & World Construction:** `CaveGenerator` (v4), `CaveGraph`, `CaveBuilder`, `CaveValidator`, `CaveTheme`.
- **AI & Autonomous Agents:** `BotController`, `BotPlanner`, `BotKnowledge`.
- **Gameplay & Hazards:** `MatchController`, `GameWorld`, `MysteryBox`, `FireHazard`, `SpiderEnemy`, `PistonHazard`, `SpikeHazard`, `CrumbleTile`, `BoostPad`, `WindZone`.
- **Freedom Duel:** `FreedomDuel`, `DuelArena`, `PulseBlaster`, `FreedomCore`.
- **Networking & Server:** `NetManager`, `NetMatch`, `ServerMain`, `LobbyState`, `WorldScope`.
- **UI & Audio:** `RaceHUD`, `DuelHUD`, `MainMenu`, `ModeSelect`, `Lobby`, `OnlineLobby`, `Results`, `Settings`, `UiKit`, `AudioManager`, `SettingsManager`.

### Test Suite Results
All core automated verification suites were executed against the headless engine:
- `test_prompt3.tscn`: **71 / 71 passed** (Fire bypass, racer collision, spikes/crystals, heart trades, remapped hints, compass, bot ledge escapes).
- `test_gravity.tscn`: **338 / 338 passed** (Basis orthonormalization, drift stability, 90°/180° shifts, camera roll prevention, current-frame axes).
- `test_cave.tscn`: **134 / 134 passed** (200 seeds generated & validated, Rush profiles, loops, solvability within Move budget).
- `test_match.tscn`: **45 / 45 passed** (Countdown, placements, eliminations, Rush timer expiry).
- `test_bot.tscn`: **30 / 30 passed** (Knowledge isolation, frontier exploration across 60 caves).
- `test_duel.tscn`: **92 / 92 passed** (Qualification, DOF stages, weapons, shield, core, sudden death, bot duel).
- `test_themes.tscn`: **30 / 30 passed** (Stone Age, Jungle, Dark Cave, City Drain deterministic hash invariance).
- `test_wallwalk.tscn`: **3 / 3 passed** (Physics agreement with validator).
- `test_net_lobby.tscn`: **41 / 41 passed** (Name validation, slot management, sanitization).
- `test_net_sim.tscn`: **80 / 80 passed** (Server authority, dual room isolation, duel ownership).
- `bot_physical.tscn`: **6 / 8 finished (75%)** in multi-bot 3D physical simulation with collisions and gravity shifts.
- **Interactive Game Launch:** Successfully executed directly on macOS Apple M4 Metal / GL Compatibility renderer at 60+ FPS.

---

## 2. Identified Bugs & Edge-Case Vulnerabilities

### Bug 1: HUD UI Overlap — Exchange Hint Collides with Racer List
- **Location:** `scripts/ui/hud.gd:76`, `scripts/ui/hud.gd:140`
- **Severity:** Medium (Visual/UI)
- **Detail:**  
  `_exchange_hint` is anchored at `Vector2(30, 175)`.  
  `_racer_list` is positioned at `Vector2(20, 176)`.  
  When a player reaches 0 Move charges and can trade health for Moves, `_exchange_hint.text` is displayed (`"[H] trade a heart for a Move"`). It prints directly on top of the first racer in the HUD racer list, making both texts illegible.
- **Recommended Fix:** Anchor `_exchange_hint` below `_racer_list` (e.g. `Vector2(20, 310)`) or dynamically stack it inside a unified left-hand HUD container.

---

### Bug 2: Ghost Recording / Disk Reload Failure on `user://`
- **Location:** `scripts/gameplay/ghost_racer.gd:38-43`, `tests/test_flow.gd:106`
- **Severity:** Medium (Data Persistence)
- **Detail:**  
  In `GhostRacer.save`:
  ```gdscript
  const DIR := "user://ghosts"
  static func save(p_seed: int, size: int, frames: Array, tag: String = "") -> void:
      DirAccess.make_dir_recursive_absolute(DIR)
      var f := FileAccess.open(path_for(p_seed, size, tag), FileAccess.WRITE)
  ```
  `test_flow.gd` asserts `ghost != null` after calling `GhostRacer.save` and `load_for`. `make_dir_recursive_absolute("user://ghosts")` fails in environments where `user://` has not been initialized or sandboxed file paths require globalized paths via `ProjectSettings.globalize_path("user://ghosts")` or `DirAccess.open("user://").make_dir_recursive("ghosts")`. If folder creation fails, `FileAccess.open` returns `null`, and ghost runs fail to persist.
- **Recommended Fix:** Use `DirAccess.open("user://")` and check `dir.make_dir_recursive("ghosts")` rather than raw `make_dir_recursive_absolute`.

---

### Bug 3: Freedom Duel Controls Cannot Be Remapped in Settings
- **Location:** `autoload/settings_manager.gd:45-46`, `scripts/ui/ui_kit.gd:331-335`
- **Severity:** Medium (Accessibility / Usability)
- **Detail:**  
  `SettingsManager.REMAPPABLE` only exposes 10 actions (`move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `gravity_mod`, `interact`, `toggle_map`, `exchange_heart`).  
  `duel_fire` (Pulse Blaster) and `duel_lock` (Axis Lock) are essential competitive controls during the Freedom Duel, yet they are completely omitted from `REMAPPABLE` and `ACTION_LABELS`. Players with custom keybindings, alternative mice, or accessibility needs cannot rebind duel actions.
- **Recommended Fix:** Add `"duel_fire"` and `"duel_lock"` into `SettingsManager.REMAPPABLE` and define labels in `ACTION_LABELS`.

---

### Bug 4: Memory Leak / ObjectDB Leaks on Scene Teardown & Test Exits
- **Location:** Multiple test scripts and dynamic procedural builders (`test_duel.gd`, `test_prompt3.gd`, `cave_builder.gd`, `audio_manager.gd`)
- **Severity:** Low-Medium (Resource Hygiene / Long Session Stability)
- **Detail:**  
  During headless test runs and game session shutdowns, Godot reports leaks:
  `WARNING: 544 ObjectDB instances were leaked at exit.`
  `ERROR: 33 RID allocations of type DummyTexture were leaked at exit.`
  Dynamically allocated `StandardMaterial3D.new()`, procedural `BoxMesh.new()`, `PrismMesh.new()`, and untracked `Tween` instances created in `_stage_finish`, `SpikeHazard`, and `AudioManager` are not explicitly queued for freeing when parent scenes are wiped.
- **Recommended Fix:** Ensure custom materials and dynamically created sub-resources are stored as static shared flyweights or cached in a material pool instead of generating individual duplicate instances per cell/spike/crystal.

---

### Bug 5: `_restart()` in `game_world.gd` Desynchronizes Match Settings
- **Location:** `scripts/gameplay/game_world.gd:899-909`
- **Severity:** Low-Medium (State Integrity)
- **Detail:**  
  When restarting from the pause menu:
  ```gdscript
  func _restart() -> void:
      GameState.cave_size = cave_size
      GameState.theme_id = theme_id
      GameState.ruleset = ruleset
      GameState.rush_seconds = rush_seconds
      GameState.prepare_match(seed_value, bot_count)
      AudioManager.stop_ambience()
      SceneRouter.start_match()
  ```
  `GameState.move_regen` is not updated with `_move_regen`, and `GameState.bot_skill` is not updated with `bot_skill`. If a match was launched with non-default regeneration or bot difficulty and restarted, these settings fall back to stale `GameState` values.
- **Recommended Fix:** Explicitly assign `GameState.move_regen = _move_regen` and `GameState.bot_skill = bot_skill` inside `_restart()`.

---

### Bug 6: Potential Null Dereference in `_prewarm_effects()` on Immediate Exit
- **Location:** `scripts/gameplay/game_world.gd:295-300`
- **Severity:** Low (Crash Guard)
- **Detail:**  
  `_prewarm_effects()` yields with `await get_tree().process_frame`. If a user rapidly presses Esc or quits before that frame completes, `_player` can be disposed, causing `_player.gravity.local_up()` to raise a script error on a null instance.
- **Recommended Fix:** Add `if not is_instance_valid(_player): return` immediately following the `await` statement.

---

### Bug 7: Mystery Box Online Clue Signal Omission
- **Location:** `scripts/gameplay/mystery_box.gd:141-153`
- **Severity:** Low-Medium (Online Feature Discrepancy)
- **Detail:**  
  When a mystery box is opened offline, `_apply_reward` emits `clue_granted`.  
  In online play, `net_apply_open` is called on clients when the server opens a box. However, `net_apply_open` only handles `"speed"` and `"slow"` locally; it never emits `clue_granted` or notifies the local HUD directly. While `NetMatch.client_on_clue` handles the server's RPC, `MysteryBox.clue_granted` remains silent on the client, breaking any local listeners or visual cues connected directly to the box node.
- **Recommended Fix:** Ensure `net_apply_open` emits `clue_granted` if `reward == "clue"` when `racer.is_local_player`.

---

### Bug 8: Compass vs. Discovered Map Visual Clipping at Non-Standard Resolutions
- **Location:** `scripts/ui/hud.gd:427-428`, `scripts/ui/hud.gd:541`
- **Severity:** Low (UI Visual Glitch)
- **Detail:**  
  The world compass is drawn on the right screen edge at `Vector2(c.size.x - 70, 300)`.  
  The discovered minimap panel is rendered at `Rect2(c.size.x - 320, c.size.y - 330, 300, 310)`.  
  On viewports with height below 720p or non-standard aspect ratios, the top boundary of the map panel overlaps the bottom of the compass circle and its caption.
- **Recommended Fix:** Dynamically calculate the map's Y position or offset the compass higher when the map is toggled open.

---

### Bug 9: Spider Look-At Collinear Singularity
- **Location:** `scripts/gameplay/spider_enemy.gd:153`
- **Severity:** Low (Engine Warning / Edge Case)
- **Detail:**  
  `var face := Basis.looking_at(move.normalized(), Vector3.UP)`  
  If `move.normalized()` ever coincides with `Vector3.UP` or `Vector3.DOWN`, `looking_at` produces engine error spam. While `to.y = 0.0` is enforced during lunges, patrol direction transitions could trigger zero-length normalization.
- **Recommended Fix:** Add a guard: `if move.length_squared() > 0.01 and absf(move.normalized().dot(Vector3.UP)) < 0.99:` before invoking `Basis.looking_at`.

---

### Bug 10: Multi-Bot Cluster Deadlock in Narrow Tunnels
- **Location:** `scripts/bots/bot_controller.gd:277`
- **Severity:** Low (AI Behavior in Edge Cases)
- **Detail:**  
  `_yield_to_racers` uses `_body.get_instance_id() > o.get_instance_id()` to decide which bot yields. When 3 or 4 bots converge in a narrow 4-unit corridor or junction, cyclic relationships (Bot A yields to B, B yields to C, C yields to A) can cause jittery avoidance stalls before the progress watchdog triggers a stage-3 gravity escape.
- **Recommended Fix:** Implement a prioritized corridor right-of-way based on distance to destination or movement momentum rather than raw instance IDs.

---

## 3. Professional Feature Roadmap to Elevate Gameplay

To transform *Six Ways Down* into a standout commercial-grade indie competitive platformer/racer, here are high-impact feature additions organized by discipline.

---

### A. Advanced Movement & Game Feel ("Easy to Learn, Deep to Master")

1. **Momentum-Carrying Gravity Slingshot ("Gravity Vaulting")**
   - *Current State:* During a 90° gravity shift, planar momentum is zeroed out or arrested to keep the transition readable.
   - *Enhancement:* If the racer times a jump or slide precisely at the moment of impact with the new floor, preserve 50–75% of their falling velocity and redirect it into horizontal forward momentum!
   - *Why it's fun:* Creates incredible skill expression for speedrunners. Dropping down a 3-cell vertical shaft and shifting 90° into an explosive sprint forward feels exhilarating.

2. **Ledge Mantling & Edge Snapping**
   - *Current State:* In narrow 4-unit tunnels, jumping towards a doorway lip can occasionally cause the player capsule to bump the edge and lose speed.
   - *Enhancement:* A contextual ledge-grab/mantle (using a low-cost downward raycast when airborne) that smoothly pulls the racer onto the surface.
   - *Why it's fun:* Keeps parkour buttery smooth on all six surfaces without frustrating snags.

3. **Slide / Crouch Mechanic**
   - *Enhancement:* Pressing Crouch while sprinting triggers a friction-slide that lowers the player's profile (from 1.8 to 0.9 units).
   - *Why it's fun:* Allows racers to slide under low-hanging stalactites, duck beneath piston slam areas, or slip through narrow gaps without spending a Move charge.

---

### B. Dynamic Environment & Hazard Interactions

4. **Surface-Specific Terrain Properties**
   - **Ice / Slick Stone (Dark Cave):** Low friction, high top-speed sliding.
   - **Bioluminescent Roots (Jungle):** Bouncy surfaces that cushion falls and launch racers across chambers.
   - **Pipes / Steam Vents (City Drain):** Periodic steam bursts that push racers upward or sideways like localized directional wind hazards.

5. **Zero-Gravity Pockets ("The Null Chamber")**
   - In rare landmark chambers (e.g., 1 per long cave), personal gravity is temporarily disabled.
   - Racers float in true 3D space and must jump off surfaces or shoot their blaster (in the duel) to propel themselves via recoil.
   - Directly celebrates the GameJam theme: "Degree of Freedom".

---

### C. Freedom Duel Expansion

6. **Deflection / Kinetic Parry**
   - Pressing Axis Lock right before an incoming Pulse Blaster bolt hits deflects the shot back towards the attacker.
   - Adds high-stakes tactical counterplay to duel standoffs instead of pure hitscan DPS trades.

7. **Slam Attack from Above**
   - In 3DOF, jumping high above an opponent and looking down activates a downward ground-pound slam that creates an area-of-effect shockwave.
   - Rewards using vertical platforms and vertical mobility.

8. **Multi-Arena Selection**
   - Add 3 distinct arena architectures:
     - **The Monolith:** Tall central tower with spiraling ramps and jump pads.
     - **The Cube:** Hollow box with zero-G center and rotating cover blocks.
     - **The Gauntlet:** Symmetrical dual-lane arena with elevated sniper perches.

---

### D. Audio, Visuals & Presentation Polish

9. **Dynamic Interactive Soundtrack (Stem-Based System)**
   - Maintain the procedural synthesis or introduce lightweight multi-track synth stems:
     - *Layer 1 (Sub-bass & Ambience):* Plays during standard exploration.
     - *Layer 2 (Hi-hats & Arpeggios):* Activates when moving at sprint speed or near other racers.
     - *Layer 3 (Heartbeat & Distorted Bass):* Fades in when health is ≤ 1.5 hearts.
     - *Layer 4 (Full Combat Drums & Lead Synth):* Drops when the Freedom Duel begins.

10. **Screen-Space Gravity Warp Shaders**
    - During the 0.35s gravity shift, apply a brief screen-space radial blur and subtle chromatic aberration vignette that warps towards the new gravity vector.
    - Communicates physical force and G-shock without causing disorientation.

11. **Glowing Surface Footprint Trails**
    - When walking on walls or ceilings, leave glowing bootprints in the racer's signature color that fade after 6–8 seconds.
    - Gives players immediate visual confirmation of rivals who passed through recently.

12. **Canyon/Cavern Audio Reverb & Spatial Occlusion**
    - Apply an AudioEffectReverb to the SFX bus modulated by cell size (tunnel vs chamber).
    - Muffle rival footsteps and shifts when separated by solid rock boundaries using raycasts to the camera.

---

### E. Competitive, Spectator & Social Features

13. **3D Post-Match Hologram Replay**
    - At the Results screen, display an interactive 3D mini-hologram of the cave graph showing animated colored lines tracing the paths of all racers from spawn to finish.
    - Shows where racers got lost, where they traded hearts, and where the winning overtake happened.

14. **Ghost Sharing via Compact Seed Codes**
    - Allow exporting a best run as a short 16-character string containing seed, time, and downsampled keyframe splines.
    - Players can paste a friend's ghost code to race against their phantom offline!

15. **Broadcast Spectator Mode for Tournaments**
    - Free-flight spectator drone camera with smooth damping.
    - Picture-in-picture (PiP) window showing both finalists simultaneously during the Freedom Duel.
    - Racer health/Move HUD bars permanently docked at the top screen like fighting game health bars.

16. **Gamepad & Controller Support with Radial Gravity Wheel**
    - Full XInput/DualShock analog stick navigation.
    - Holding Left Bumper / Left Trigger brings up an intuitive 3D radial direction wheel to snap gravity effortlessly with the right thumbstick.

---

## 4. Summary Table of Priority Recommendations

| Category | Item | Impact | Complexity |
|---|---|---|---|
| **Bug Fix** | Fix HUD Exchange Hint overlapping Racer List | High (Visual) | Very Low |
| **Bug Fix** | Fix `GhostRacer` directory creation on `user://` | High (Records) | Low |
| **Bug Fix** | Add `duel_fire` & `duel_lock` to remappable settings | High (QoL) | Low |
| **Bug Fix** | Clean up ObjectDB leaks & material duplication | Medium (Perf) | Low-Medium |
| **Bug Fix** | Preserve `move_regen` and `bot_skill` on `_restart()` | Medium (State) | Very Low |
| **Feature** | Momentum-preserving gravity vaulting / slingshot | Critical (Fun) | Medium |
| **Feature** | Full Gamepad support with radial gravity wheel | High (Polish) | Medium |
| **Feature** | 3D Holographic post-match path playback | High (Juice) | Medium |
| **Feature** | Kinetic Parry / Deflection in Freedom Duel | High (Combat) | Medium |
| **Feature** | Dynamic adaptive music layers & cavern reverb | High (Immersion)| Low-Medium |

---
*Report compiled autonomously via inspection of project sources, automated test verification, and live engine execution.*

