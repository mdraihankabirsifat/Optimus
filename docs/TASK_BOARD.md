# TASK_BOARD

Reference the Task ID in every commit message and in every AI prompt. Update the status column
when you start and when you finish — this board, not anyone's memory, is what tells the next
person (or the next AI session) what is actually done.

**Team:** Md. Raihan Kabir Sifat · Estiak Zaman Atul · Sadman Sakib · Ashraf Hossain Chowdhury

Map yourselves to Developer A–D below and fill in the Owner column. The split is designed so
that A, B and C touch almost no common files during the first day.

| Slot | Focus | Primary files |
|---|---|---|
| **Developer A** | Player, gravity, camera — the critical path | `scripts/player/**` |
| **Developer B** | Cave generation and level building | `scripts/cave/**`, `scenes/cave/**` |
| **Developer C** | UI, HUD, menus, audio, settings | `scenes/ui/**`, `scripts/ui/**`, `autoload/settings_manager.gd`, `autoload/audio_manager.gd` |
| **Developer D** | Match rules, hazards, boxes, then bots | `scripts/gameplay/**`, `scripts/bots/**` |

Developer A is on the critical path. If A is blocked, B/C/D should unblock A before doing
anything else — every other system consumes the gravity frame.

---

## Schedule

Wall clock from 16 September, evening. Roughly 40 hours to the 17 September 11:59 PM deadline.

| Block | A | B | C | D |
|---|---|---|---|---|
| **0–6 h** | Player controller + gravity shift | Cave graph generator (pure data) | Project skeleton, autoloads, main menu | Match controller, timer, finish |
| **6–12 h** | Six-orientation testing, transition polish | Modular meshes, graph → geometry | HUD: hearts, moves, timer, DOF | Hearts, damage, elimination |
| **12–20 h** | Camera feel, shift VFX/SFX hooks | Spawn/finish placement, validation | Settings, How to Play, About | Fire hazard, mystery boxes |
| **20–28 h** | **Integration** — everyone merges, first full playable | | | Bot: discovered graph + frontier search |
| **28–34 h** | Stone Age art pass, audio, game feel, results screen — all hands | | | |
| **34–38 h** | Exports (Windows + web), QA, bug fixing, known-bugs list | | | |
| **38–40 h** | Video, screenshots, itch.io page, submission. **Do not write code in this block.** | | | |

Networking (NET-*) is Tier 3 and is not scheduled. It may only begin after hour 34 if
everything above is complete and committed, and it is bound by the abort gate in
`docs/MVP_SCOPE.md`.

---

## MASTER PROMPT 3 (17 September, on top of Prompt 2)

`OPTIMUS_Master_Prompt_3.txt`, thirteen requests. Evidence is in `tests/test_prompt3.gd` unless noted.

| ID | Request | Status | Root cause / evidence |
|---|---|---|---|
| P3-01 | Fire avoidable from the ceiling | DONE | The 2.4-unit flame box reached into a ceiling walker in a 4-unit tunnel. Flames are now at most a third of the cell height; real bodies cross on the ceiling and the clear wall unhurt, floor contact still burns once per tick. |
| P3-02 | Normal and Rush | DONE | Normal: no cave limit (`test_match`: still racing at 15 min). Rush 3/5/8 min, easier generator profile (`test_cave`, `docs/CAVE_GENERATION.md` table), expiry with 0/1/2 qualifiers (`test_duel`), records keyed by rules, synced online (`test_net`). |
| P3-03 | Create Arena / Join by code | DONE | Copy Code, bounded unique codes, double-click and bad-code handling, two arenas at once, synced names and rules over real sockets (`test_net`). Public server wss://six-ways-down-server.onrender.com: create and join by code verified with `tests/public_probe.tscn`. |
| P3-04 | Trade a heart for a Move | DONE | One transaction for player, server and bots; 20 s last-heart deadline; regen switches it off; server debounce (`test_prompt3`, `test_net`). |
| P3-05 | Hints follow remapping | DONE | `MysteryBox.prompt_text()` hard-coded "[E]". All hints now use `UiKit.binding_text`; E->R, swap and reset tested. |
| P3-06 | Remove overtake callouts | DONE | FUN-003 removed on request, not broken. |
| P3-07 | World compass | DONE | N=-Z fixed; same bearing on every surface and through chained shifts; stable looking straight up/down. |
| P3-08 | Racer, spike and crystal collision | DONE | Racers masked only the world (1). Now solid to each other on all six surfaces; finished/eliminated racers stop blocking; spikes solid and damaging, crystals solid, chambers only. |
| P3-09 | Player name | DONE | Play screen field, saved, 1-20 characters, Unicode, markup removed, blank refused; server validates (`test_net_lobby`). |
| P3-10 | Native title bar when windowed | DONE in code | Likely cause: a saved 1920x1080 window on a 1080p monitor put the title bar off-screen. Windowed mode now clears borderless and fits the window to the usable area. **Needs a person on a standalone Windows build.** |
| P3-11 | Remove Window Size | DONE | Selector removed; old saved value ignored (screenshot `tests/shots/menu_settings_720.png`). |
| P3-12 | Bots escape pits with gravity | DONE | Ledge too high to jump: ceiling flip, or wall turn and climb when there is no ceiling; one Move per shift; regen wait; heart trade; last-heart refusal. |
| P3-13 | Bots that stop moving | DONE, keep measuring | Progress watchdog with staged recovery, blocked passages, head-on yielding, damage-learned hazards. Physical runs now end mostly in finishes or explained eliminations; see `docs/TESTING.md`. |

## MASTER PROMPT 2 (17 September, on top of `prompt1-complete`)

`OPTIMUS_Master_Prompt_2.txt`. Status as of this commit.

| ID | Task | Status | Evidence |
|---|---|---|---|
| P2-MOVE-001 | WASD uses the camera projected onto the current gravity plane, all six surfaces, chained shifts | DONE | `PlayerController.movement_axes()`; `tests/test_gravity.gd` (338 checks incl. real walking on six faces) |
| P2-MOVE-002 | Remote racers drawn in their own orientation | DONE | `tests/test_net_sim.gd` wall-pose check |
| P2-CAVE-001 | Corridor-first spine: straight runs, turns at run ends, planned climbs **and** descents | DONE | `CaveGenerator` VERSION 4; `tests/cave_metrics.tscn` |
| P2-CAVE-002 | Long real loops (detour >= 4 hops), dead ends, upper and lower routes | DONE | `tests/test_cave.gd` `_test_cave_shape`, `_test_loops_are_long` |
| P2-CAVE-003 | Narrow tunnels (4 units), chambers at spawn/finish/landmarks, flush floors | DONE | `CaveBuilder` `TUNNEL_HALF`, `FLOOR_Y`; hazards resized to fit |
| P2-CAVE-004 | Doorway funnels so every chamber face walks into its tunnels | DONE | bots 17/40 -> 30/40 finishing (`bot_physical`, 10 caves) |
| P2-CAVE-005 | Believable dressing: rock lumps, wall bulges, rubble, per-cell stone shade | DONE (first pass) | `_add_rock_dressing`; visual only |
| DUEL-001 | Qualification: Qualified 1st waits safely in the arena, Qualified 2nd starts the duel, others stop | DONE | `tests/test_duel.gd` |
| DUEL-002 | Fallbacks: no challenger left, 90 s qualify limit, race limit, force end, finalist leaves, 90 s duel limit | DONE | `tests/test_duel.gd`, `tests/test_net_sim.gd` |
| DUEL-003 | Arena with X/Y/Z markings, platforms, ramps, cover, core pedestals | DONE | `scripts/duel/duel_arena.gd`; `tests/duel_shot.tscn` |
| DUEL-004 | 3DOF / 2DOF / temporary 1DOF movement, no Gravity Moves in the duel | DONE | `PlayerController.duel_dof`; `tests/test_duel.gd` |
| DUEL-005 | Fresh duel hearts, one-hit shield for Qualified 2nd, duel loss is not a cave elimination | DONE | `PlayerHealth.duel_mode` |
| DUEL-006 | Pulse Blaster | DONE | hitscan, 0.5 hearts, 0.45 s |
| DUEL-007 | Axis Lock with immunity (no chain-locking) | DONE | 3 s lock, 3 s immunity |
| DUEL-008 | Freedom Core (+1 DOF, shield at 3DOF) | DONE | |
| DUEL-009 | Arena DOF shifts and sudden death | DONE | FULL FREEDOM, Y AXIS LOCKED, FREEDOM SURGE; SD at 60 s |
| DUEL-010 | Spectator view and duel HUD | DONE | `scripts/ui/duel_hud.gd` |
| DUEL-011 | Results: Champion, runner-up, cave order, duel stats; "Qualified", never "Winner" | DONE | `scripts/ui/results.gd`, `MatchController.build_results` |
| DUEL-012 | Bot finalists fight | DONE | bot-vs-bot duel resolves in `tests/test_duel.gd` |
| DUEL-013 | Server-authoritative duel online (`c_duel_fire`, `s_duel_state`, `s_duel_event`) | DONE | `tests/test_net_sim.gd`; real WebSocket duel in `tests/test_net.gd` |
| DUEL-014 | Duel audio (qualified, intro, blaster, lock, core, shift, sudden death, hits, champion) and duel music | DONE | `AudioManager`, all synthesised |
| DUEL-015 | Docs, How to Play, About, itch copy, shot list | DONE | this commit |
| SHIP-P2-1 | Human online duel playtest, Windows and Web re-export, clean-machine and browser checks | TODO | |
| SHIP-P2-2 | Final screenshots and the 60-90 s video ending on the Champion | TODO | shot list in `docs/SUBMISSION_CHECKLIST.md` |

---

## TODO

### Core — Developer A

| ID | Task | Pri | Deps | Definition of Done |
|---|---|---|---|---|
| CORE-001 | Project skeleton: folders, 6 autoloads, `AppConfig` tunables | P0 | — | Project runs, autoloads resolve, no errors |
| MOVE-001 | `CharacterBody3D` gravity-relative walk + sprint | P0 | CORE-001 | Player walks in a test box, no `Vector3.UP` in file |
| MOVE-002 | FPS camera: yaw on body, pitch on head, clamped ±89° | P0 | MOVE-001 | Full 360° look, no roll, sensitivity exported |
| AXIS-001 | `gravity_controller.gd`: gravity_dir, local basis, custom gravity integration | P0 | MOVE-001 | Player falls along an arbitrary cardinal, floor check correct |
| AXIS-002 | `G` chord input handling with movement suppression | P0 | AXIS-001 | Holding G stops walking, releases cleanly |
| AXIS-003 | 90° shift: cardinal snap + basis slerp, 0.35 s | P0 | AXIS-002 | All four directions correct, no camera roll |
| AXIS-004 | 180° inversion via `G+Space` | P0 | AXIS-003 | Ceiling becomes floor, forward preserved |
| AXIS-005 | 5 Move charges, deduct once, deny at zero with feedback | P0 | AXIS-003 | Cannot shift at zero, distinct denied SFX/flash |
| AXIS-006 | Safe-transform ring buffer + protected vacuum-180 recovery | P0 | AXIS-004 | 180° into vacuum costs 1 heart and recovers, never eliminates |
| AXIS-007 | Test chamber: all six orientations, chained rotations, drift check | P0 | AXIS-004 | 20+ chained shifts, basis stays orthonormal |
| AXIS-008 | Gravity direction preview arrow while G is held | P1 | AXIS-002 | Player can see the direction before committing |

### Cave — Developer B

| ID | Task | Pri | Deps | Definition of Done |
|---|---|---|---|---|
| LEVEL-001 | `cave_graph.gd` data structure + connection masks | P0 | CORE-001 | Cells add/query/serialise, unit-testable without scene |
| LEVEL-002 | Seeded spine generation spawn → finish | P0 | LEVEL-001 | Deterministic; same seed = same spine |
| LEVEL-003 | Braiding: loops, branches, dead ends, vertical shafts | P0 | LEVEL-002 | At least one cycle, at least two vertical sections |
| LEVEL-004 | Modular meshes per connection mask | P0 | LEVEL-001 | Corridor, turn, T, cross, shaft, chamber, cap |
| LEVEL-005 | `cave_builder.gd` graph → instantiated geometry + collision | P0 | LEVEL-004 | Walkable cave, no gaps, no overlaps |
| LEVEL-006 | Spawn chamber (hazard-free) and hidden finish area | P0 | LEVEL-005 | Min graph distance enforced, finish not visible from spawn |
| LEVEL-007 | Spine Move-cost assert ≤ 3 of 5 charges | P0 | LEVEL-003 | Generation retries deterministically on failure |
| LEVEL-008 | 50-seed dev validation command | P1 | LEVEL-007 | All 50 connected and within Move budget |
| LEVEL-009 | Landmarks and lighting variation so corridors differ | P1 | LEVEL-005 | No two chambers read identically |
| LEVEL-010 | Outer bounds / kill volumes | P0 | LEVEL-005 | Falling out is caught, not infinite |

### Gameplay — Developer D

| ID | Task | Pri | Deps | Definition of Done |
|---|---|---|---|---|
| MATCH-001 | `match_controller.gd`: countdown 3-2-1-GO, match timer | P0 | CORE-001 | Countdown blocks input, timer starts on GO |
| MATCH-002 | Finish trigger, placement order, finish times | P0 | MATCH-001, LEVEL-006 | 1st–5th assigned in arrival order |
| MATCH-003 | Results screen data: placements, times, DNF, stats, seed | P0 | MATCH-002 | Seed shown for rematch |
| MATCH-004 | Rematch same seed / new cave / main menu | P1 | MATCH-003 | All three paths work without restart |
| HEALTH-001 | 5 hearts with half-heart support | P0 | CORE-001 | Damage of 0.5 and 1.0 both display correctly |
| HEALTH-002 | Damage cooldown + 1.5 s invulnerability, per-source | P0 | HEALTH-001 | Standing in fire drains at a fair rate, not per-frame |
| HEALTH-003 | Elimination at zero hearts, input lockout | P0 | HEALTH-001 | Eliminated racer stops, is marked in HUD |
| HEALTH-004 | Spawn and countdown damage immunity | P0 | HEALTH-002 | No damage possible before GO |
| HAZ-001 | Fire hazard: visible, animated, damage 0.5/tick with cooldown | P0 | HEALTH-002 | Readable from a distance, never instantly lethal |
| BOX-001 | Mystery box: interact, one-time, authoritative outcome | P1 | HEALTH-001, AXIS-005 | Cannot be opened twice |
| BOX-002 | Loot table: Heart Refill, Move Refill, speed, penalty, rare clue (~5%) | P1 | BOX-001 | Data-driven weights; Heart Refill clamps at 5 |
| BOX-003 | Clue effect: coarse direction pulse, never full reveal | P2 | BOX-002 | Helps without trivialising the search |
| BOT-001 | `bot_knowledge.gd` discovered graph, isolated from real graph | P1 | LEVEL-001 | No reference to the true graph exists in the file |
| BOT-002 | `bot_planner.gd` frontier search + backtracking | P1 | BOT-001 | Bot explores, backtracks from dead ends |
| BOT-003 | `bot_controller.gd` drives body with same rules as humans | P1 | BOT-002, MOVE-001 | Same speed, same 5 charges, no teleporting |
| BOT-004 | Bot spends a Move when a frontier requires it | P1 | BOT-003, AXIS-005 | Visibly shifts gravity, cannot shift at zero |
| BOT-005 | Scale to 1–4 bots | P1 | BOT-003 | 2–5 total racers all function |

### UI & Presentation — Developer C

| ID | Task | Pri | Deps | Definition of Done |
|---|---|---|---|---|
| UI-001 | Splash + main menu, `GAME_TITLE_TBD` from `AppConfig` | P0 | CORE-001 | Title changeable in exactly one place |
| UI-002 | Mode select + bot lobby (racer count, seed, start) | P0 | UI-001 | 2–5 racers selectable, seed randomisable |
| UI-003 | HUD: hearts, Move charges, timer, orientation indicator | P0 | AXIS-005, HEALTH-001 | All four update live and are readable at a glance |
| UI-004 | Gravity shift HUD feedback + denied state | P0 | UI-003 | Charge animates on spend, denial is unmistakable |
| UI-005 | Results screen | P0 | MATCH-003 | Placements, times, DNF, seed |
| UI-006 | Pause menu | P1 | UI-001 | Resume, settings, quit to menu |
| UI-007 | Settings: master/music/SFX volume, sensitivity, fullscreen, persisted | P1 | CORE-001 | Survives a restart |
| UI-008 | How to Play — explains Moves, G chords, hearts, private gravity | P0 | UI-001 | A judge can play correctly after reading it once |
| UI-009 | About / Theme screen for judges | P0 | UI-001 | States the DOF interpretation plainly, credits the team |
| UI-010 | DOF 1/2/3 contextual readout at junctions | P1 | LEVEL-001, UI-003 | Counts real traversable axes at the current cell |
| ART-001 | Stone Age materials, lighting, fog | P1 | LEVEL-005 | Reads as intentional, not greybox |
| ART-002 | Racer colours, silhouettes, name labels | P1 | MOVE-001 | Racers distinguishable at distance and on walls |
| AUDIO-001 | Buses + `AudioManager` | P1 | CORE-001 | Volume settings route correctly |
| AUDIO-002 | Ambience, footsteps, gravity shift, damage, box, finish, menu music | P1 | AUDIO-001 | Gravity shift sound is the most satisfying one |

### Ship — All hands

| ID | Task | Pri | Deps | Definition of Done |
|---|---|---|---|---|
| SHIP-001 | Windows export | P0 | Tier 2 | Runs on a Windows machine without Godot |
| SHIP-002 | Web export | P0 | Tier 2 | Loads and plays in a current browser |
| SHIP-003 | README: controls, run instructions, structure, known bugs | P0 | — | A stranger can run the game from it |
| SHIP-004 | `CREDITS.md` + `AI_DISCLOSURE.md` | P0 | — | Every external asset and AI use recorded |
| SHIP-005 | Screenshots | P0 | Tier 2 | Include one shot of two racers on different surfaces |
| SHIP-006 | 60–90 s gameplay video | P0 | Tier 2 | Title, core loop, gravity mechanic, theme connection |
| SHIP-007 | itch.io submission | P0 | all SHIP | Submitted before 11:59 PM, 17 Sept |

### Online — built 17 September (was Tier 3)

| ID | Task | Pri | Deps | Definition of Done |
|---|---|---|---|---|
| NET-001 | `WebSocketMultiplayerPeer` client/server connection | P1 | — | Two local clients connect |
| NET-002 | Headless authoritative server + lobby/room codes | P1 | NET-001 | Room code joins a live lobby |
| NET-003 | Sync transforms, gravity, health, charges, boxes, finish, results | P1 | NET-002 | Two clients see each other's gravity correctly |
| NET-004 | Dockerfile + Render deployment | P1 | NET-003 | Image runs the server; public endpoint reachable |
| NET-005 | Mixed human/bot lobbies, fill-with-bots, bot takeover | P1 | NET-003, BOT-005 | 2 humans + 2 bots races correctly |
| NET-006 | Play screen + online lobby UI with connection states | P1 | NET-002 | Connecting / Connected / Reconnecting / Failed shown |
| NET-007 | Deploy to Render | P2 | NET-004 | `wss://` address works from two machines |
| ENEMY-001 | Spider on a fixed corridor rail, no nav mesh | P3 | HAZ-001 | Patrols and lunges, cannot stun-lock |
| SPEC-001 | Spectator camera cycling after elimination | P3 | HEALTH-003 | Cycles active racers, affects nothing |

### Still open

| ID | Task | Pri | Definition of Done |
|---|---|---|---|
| NET-007 | Deploy the server to Render | P2 | Needs the team's Render account. Steps in docs/NETWORKING.md |
| SHIP-001 | Windows exe on a machine without Godot | P0 | Plays a race to results |
| SHIP-007 | itch.io submission | P0 | Before 11:59 PM, 17 Sept |
| SHIP-008 | Performance on a modest machine | P1 | Measured on an M4 only: 60 fps capped, 104 draw calls, 65 MB |
| FEEL-005/006 | Turn time and acceleration | P0/P1 | Sliders are in Settings; a human has to play and pick the values |
| SHIP-P2-2 | Human playtest of the duel | P0 | Weapon timing, bot difficulty, arena readability |
| P3-10 | Title bar on the Windows exe | P1 | Built; confirm on a standalone exe |

### Done 17 September (audit, fog, Mac pacing, assets)

| ID | Note |
|---|---|
| — | The ten bugs in `GAME_ANALYSIS_BUGS_AND_FEATURES.md`, all fixed and covered by tests |
| — | Real leak found by `tests/leak_probe`: unplaced decor nodes. Six races leaked 347 Node3Ds; object count is now flat |
| ART-008 | Fog is a depth gradient per environment. `test_themes` checks near/mid/far readability for all four |
| — | macOS frame pacing: the frame rate now follows the display refresh. 95% of frames 15.9-17.5 ms (was 6.5-18.7), late frames 9.8% -> 0.5% |
| SHIP-002 | Web build driven in headless Chrome: menu, name, lobby, a real race. Fixed a web-only error storm from the key-label lookup |
| SHIP-005 | 14 store screenshots in `builds/trailer/`, including the duel and the Champion |
| SHIP-006 | 80 s trailer recorded to the Prompt-3 shot list, ending on the Champion (`tests/trailer.gd`) |
| — | Renamed the game to **Escave** (`AppConfig.GAME_TITLE`, window title, exe, bundle id, docs, Docker and Render) |

---

## IN PROGRESS

_(nothing yet)_

## BLOCKED

_(nothing yet)_

## TESTING

| ID | Note |
|---|---|
| AXIS-003/004 | Verified headless and visually. Still needs a human at a keyboard to judge whether 0.35 s *feels* right. Machine tests cannot answer that. |

## DONE

Completed 16 September 2026.

| ID | Note |
|---|---|
| CORE-001 | Folders, `AppConfig` autoload, input map for all nine actions, GL Compatibility preserved. Global gravity set to 0 — nothing may rely on it. |
| MOVE-001 | Gravity-relative walk + sprint, planar/vertical velocity decomposition, no `Vector3.UP` in the file |
| MOVE-002 | Yaw on body about `local_up`, pitch on head clamped ±89°, basis re-orthonormalised each look |
| AXIS-001 | `gravity_controller.gd` — gravity frame, custom integration, `up_direction` synced |
| AXIS-002 | G chord suppresses WASD movement while held |
| AXIS-003 | 90° shift, cardinal snap, eased basis slerp over 0.35 s |
| AXIS-004 | 180° inversion, forward preserved |
| AXIS-005 | 5 charges, deducts exactly once, denies at zero and on same-direction with signal feedback |
| AXIS-006 | Safe-transform ring buffer + protected vacuum-180 recovery path |
| AXIS-007 | `tests/test_gravity.gd` — **150 assertions, 0 failures** |

| LEVEL-001 | `cave_graph.gd` — cells, connection masks, BFS, cycle count, DOF, graph hash |
| LEVEL-002 | Seeded spine carved spawn→finish in legs, climbs chosen up front to bound Move cost |
| LEVEL-003 | Branches, dead ends and braided loops. Avg 8.8 cycles per cave. |
| LEVEL-004/005 | `cave_builder.gd` — boundary-deduped slabs, 3 MultiMesh batches, procedural stone |
| LEVEL-006 | Spawn chamber and glowing finish pillar, min 8 hops apart |
| LEVEL-007 | Spine climb cost asserted ≤ 3 of 5 charges |
| LEVEL-008 | `tests/test_cave.gd` — **200 seeds, 0 failures** |
| MATCH-001 | Countdown 3-2-1-GO, movement and damage frozen until GO, match timer |
| MATCH-002 | Finish trigger, placements 1st-5th in arrival order, finish times |
| MATCH-003 | Results: placements, times, eliminated, DNF, seed shown |
| HEALTH-001 | 5 hearts with half-heart support |
| HEALTH-002 | Per-source damage cooldowns + 1.5 s invulnerability |
| HEALTH-003 | Elimination at zero hearts, input lockout, Heart Refill cannot resurrect |
| HEALTH-004 | No damage possible before GO |
| — | `tests/test_match.gd` — **29 assertions, 0 failures** |
| BOT-001 | `bot_knowledge.gd` — discovered graph, fed only primitive observations |
| BOT-002 | `bot_planner.gd` — Dijkstra over (cell, gravity) states, frontier search, backtracking |
| BOT-003 | `bot_controller.gd` — fills the same `move_input` a human fills, so identical movement code |
| BOT-004 | Bots invert gravity to climb, and cannot when out of charges |
| BOT-005 | 1-4 bots, distinct colours, per-bot route personalities |
| — | `tests/test_bot.gd` — **15 assertions, 60/60 caves solved** |
| AXIS-008 | G-held preview: HUD labels what each key would make your floor |
| LEVEL-009 | Stalagmites, stalactites, crystals, moss, wall torches; ember stones within 2 hops of the exit |
| HAZ-001 | Fire patches, one edge always clear, 0.5 heart/tick with per-source cooldown |
| BOX-001..003 | Seeded one-time boxes; heart, move, speed, shield, slow, lose-move, rare coarse clue. Bots open boxes they pass |
| MATCH-004 | Rematch same seed / new cave / main menu from results; restart from pause |
| UI-001..010 | Splash, menu, lobby (bots, skill, seed), HUD, results, pause with in-place settings, settings, How to Play, About, Credits, DOF readout |
| ART-002 | Racer colours, visors and name labels |
| AUDIO-001/002 | Music/SFX buses; all sound synthesised at startup, wired to every event, positional for bots |
| SPEC-001 | Chase-camera spectating after finish or elimination, Tab cycles, Enter ends race |
| — | Bot skill levels. Seed 4242 with 4 bots: Easy 1:21–1:39, Normal 0:50–1:01, Hard 0:36–0:44 |
| — | `tests/test_flow.gd` — **30 assertions**: every screen, lobby → race → box → pause → results |
| SHIP-003/004 | README, CREDITS.md, AI_DISCLOSURE.md |

Completed 17 September 2026.

| ID | Note |
|---|---|
| NET-001..005 | WebSocket server and client, rooms with codes, 2-5 racers, Online (humans only) and Mixed (fill with bots), server-owned Moves/hearts/boxes/clues/placements/results, plausibility checks and corrections, bot takeover or DISCONNECTED on drop, several rooms at once in separate physics worlds. `test_net` 26/26 (real three-process race), `test_net_sim` 56/56, `test_net_lobby` 37/37 |
| NET-004 | Dockerfile builds and runs the server; two Windows clients raced through the container. Linux server and Windows clients agree on the cave hash. `render.yaml` written, not deployed |
| NET-006 | Play screen (Bot / Online / Mixed), online lobby with slots, colours by name, ready state, host controls, connection state and latency |
| LEVEL-014 | `CaveValidator`: gravity-aware solvability over (cell, gravity, Moves), structural checks, wired into generation. Every one of 200 seeds solvable within 5 Moves |
| AXIS-011 | `test_wallwalk`: the real controller walks up a wall into a shaft and drops through open floors, as the validator assumes |
| BOT-010 | Bots use clues from boxes they open themselves |
| UI-018 | Online lobby fits at 1280x720: compact host dropdowns, Start and Leave beside the room code. Checked by screenshot at 720p and 1080p |
| LEVEL-015 | Developer overlay (F3, debug builds only): cells, edges, spine, shafts, spawn/exit, boxes, hazards, a bot's knowledge and plan. Screenshot reviewed |
| ART-012 | `CaveTheme` data: Stone Age, Jungle (roots), Dark Cave (glow-worms, personal lamp), City Drain (pipes). Picked in both lobbies, sent in the online config. `test_themes` 30/30; screenshots reviewed |
| BOT-011 | Planner searches all six gravities; bots turn onto a wall when it saves a Move (arch test). `tests/bot_physical.gd`: 77/80 physical bot races finish. Preferring walls outright dropped that to 70%, so it is not preferred |
| UI-016 | Pause menu Controls page; online pause never pauses the race |
| UI-017 | Settings: invert Y, window size, graphics quality, key remapping with swap |
| SHIP-001a | Windows exe launches as the game and as a dedicated server (dev machine) |
| SHIP-009 | NETWORKING, CAVE_GENERATION, TESTING, SUBMISSION_CHECKLIST docs, future_implementation_suggestion.txt |

### How to run what exists

```bash
# Play the procedural cave (this is the main scene)
godot

# Gravity verification (exits non-zero on failure)
godot --headless res://tests/test_gravity.tscn

# Cave generation over 200 seeds
godot --headless res://tests/test_cave.tscn

# Match rules, health, elimination, results ordering
godot --headless res://tests/test_match.tscn

# Bot knowledge isolation and exploration over 60 caves
godot --headless res://tests/test_bot.tscn

# Every screen, and lobby -> race -> results
godot --headless res://tests/test_flow.tscn

# Watch a full 4-bot race and print finishing order (skill 0 Easy, 1 Normal, 2 Hard)
godot --headless res://tests/race_diag.tscn -- skill=0

# Regenerate screenshots
godot res://tests/screenshot.tscn      # gravity prototype chamber
godot res://tests/cave_shot.tscn       # generated cave
godot res://tests/match_shot.tscn      # countdown and racing HUD
godot res://tests/bot_shot.tscn        # bots racing
godot res://tests/ui_shot.tscn         # menus, HUD, fire, boxes, spectating, results
```

> **After adding any script with a new `class_name`, run this once before any
> headless test, or the test will hang with no output:**
> ```bash
> godot --headless --editor --quit
> ```
> Headless scene runs use the editor's global class cache. If the cache is stale the
> script fails to resolve, `_ready` never runs, and the process idles forever. This cost
> an hour once already.

### Measured cave statistics (200 seeds)

| Metric | Value |
|---|---|
| Cells per cave | avg 65.9 |
| Spawn → exit | avg 11.8 hops, min 8 |
| Moves required | avg 2.58, **worst 3** against a budget of 5 |
| Loops | avg 8.8 |
| Generation attempts | avg 1.36 (no thrashing) |

### Known issues

| Issue | Severity | Note |
|---|---|---|
| Capsule dips ~0.34 units into the floor mid-rotation | Low | The capsule sweeps through horizontal during a 180°, briefly reducing its vertical extent. Self-corrects on completion and reads as weight rather than a glitch. Revisit only if it causes clipping in tight corridors. |
| `is_local_player` captures the mouse in `_ready()` | Low | Fine for one local player. Needs a guard once bots and remote players instantiate the same scene. |
| Child `_ready` runs before the racer's own | Fixed | `CameraController` and `PlayerInteraction` read `gravity`/`is_local_player` before they existed, so bots also listened for E. Both now `await _player.ready`. |
| Bots walk through fire | Low | They never route around hazards and can occasionally be eliminated by one. |
| Never count `process_frame` to measure time | Low | The dev Mac has a 120 Hz display, so frame counts are half the wall time you expect. Use `get_tree().create_timer()`. Cost two wrong screenshot runs. |
| Bots use only 180-degree inversions, never 90-degree shifts | By design | The cave's vertical structure is Y-axis only, so inversion is always the right tool. 90-degree wall-walk pathing costs far more than it buys. |

### Balance findings from bot simulation

These came out of running bots across many caves and are worth knowing before tuning anything.

| Finding | Detail |
|---|---|
| **A branch that climbs can softlock a racer** | It creates a dead end whose only exit is vertical. A racer arriving with zero charges cannot move at all. Branches are now always horizontal; loops may still go vertical because they only connect cells that already exist. |
| **Scattered vertical links break the Move economy** | Crossing one costs a charge, so vertical noise fragments each floor into pieces nobody can explore without paying. Bot completion went 38/60 → 60/60 by biasing braiding horizontal (`horizontal_bias = 0.85`). |
| **`horizontal_bias = 1.0` scores best and is still wrong** | It gives 60/60 at an average of exactly 1.00 Moves used, which removes the scarcity the mechanic depends on. 0.85 keeps 97% completion while averaging 1.91 with a worst case of 5. |
| **One inversion currently buys unlimited climbing** | With gravity inverted you keep falling upward through aligned shafts for free, so Moves are less scarce than the design intends. Worth watching in playtests; hazards and non-aligned shafts would restore the pressure. |
| **Identical planners make identical bots** | Four bots first finished within 0.4 s of each other, which reads as a bug. Each bot now has a stable per-cell route preference and its own reaction delay; the same race now spreads over ~10 s. |
