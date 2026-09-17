# AI_CONTEXT — Emergency Context Restoration

Read this file first. It is the compressed truth of the project. If you have no other
context, this plus `docs/CORE_MECHANICS.md` is enough to continue work.

## Identity

- **Project:** Optimus (working title `GAME_TITLE_TBD`, centralised in `autoload/app_config.gd`)
- **Team:** Team Optimus — Md. Raihan Kabir Sifat, Estiak Zaman Atul, Sadman Sakib, Ashraf Hossain Chowdhury
- **Event:** BUET Robotics Society GameJam, Intra BUET Robo Challenge 2026
- **Theme:** Degree of Freedom
- **Engine:** Godot 4.7, GDScript, **GL Compatibility renderer** (do not switch to Forward+; web export and student laptops depend on it)
- **Deadline:** 17 September 2026, 11:59 PM. Showcase 18 September, 10:00 AM.

## The game in four sentences

Two to five racers spawn in the same seeded, block-built 3D cave and do not know where the
exit is. They explore, take damage from hazards, open mystery boxes, and each carries
**5 Move charges** that let them rotate *their own personal gravity* 90° or 180°. Gravity is
private — one racer can be sprinting along a wall while another runs on the floor of the same
corridor, and each sees the other correctly oriented. The first **two** to reach the hidden
finish qualify for the **Freedom Duel**, a short arena fight that decides the Champion (Master
Prompt 2); racers at zero hearts are eliminated into spectator mode.

## Non-negotiable rules

These came from the team's design document. Do not alter them without an explicit human decision.

1. Every racer starts with exactly **5 Move charges** and **5 hearts** (half-hearts exist).
2. A Move costs exactly **1 charge**, whether it is a 90° turn or a 180° inversion.
3. Gravity is **per racer**. A Move never rotates the world and never affects another racer.
4. Gravity directions are the **six grid-aligned cardinals** only: ±X, ±Y, ±Z.
5. Gravity commands are **camera-relative**, not world-axis-relative.
6. A Move may be spent **anywhere, any time** — no marked zones, no surface requirement.
7. Changing gravity into empty space is **legal**. The player falls until they hit something.
8. **Protected case:** a 180° Move into vacuum must **damage 1 heart and recover the player to
   their last safe grounded transform.** It must never instantly eliminate them.
9. Hearts reaching zero eliminates for the match. Heart Refill never resurrects the eliminated.
10. The exit is **never** shown on HUD or map.
11. The cave is generated from a **seed**. Same seed + same generator version = identical cave.
12. Bots are **not omniscient**. They may only use what they have personally discovered.

## Locked technical decisions

| Area | Decision |
|---|---|
| Gravity implementation | **Approach C** — static world, per-player gravity frame. See `docs/CORE_MECHANICS.md`. |
| Player body | `CharacterBody3D`, `up_direction` driven by local gravity, custom gravity integration |
| Orientation maths | Quaternion/basis slerp. **Never Euler angles** for body orientation. |
| Transition time | 0.35 s, movement locked during it |
| Networking | Godot `WebSocketMultiplayerPeer`, server-authoritative, headless Godot, Docker for Render. See `docs/NETWORKING.md`. |
| Offline mode | `GameWorld.net_role == ""`. Never calls `NetManager`. This is the judging fallback. |
| Rooms | Each server race runs in its own `SubViewport` world; group lookups go through `WorldScope`. |
| Solvability | Built solvable by construction **and** checked by `CaveValidator` over (cell, gravity, Moves). |
| Art | `CaveTheme` data: Stone Age, Jungle, Dark Cave, City Drain. Visual only; generation never reads it. |

## Master Prompt 2 (17 Sept, in progress on top of tag `prompt1-complete`)

`OPTIMUS_Master_Prompt_2.txt` is a delta on Prompt 1. Built so far:

- **Movement in the current frame.** WASD always uses the camera projected onto the plane of
  the racer's *current* gravity (`PlayerController.movement_axes()`), on all six surfaces.
- **Cave feels like a cave.** Corridor-first generator (VERSION 4): straight runs, long real
  loops, dead ends, routes that climb and descend; narrow 4-unit tunnels, chambers with sloped
  doorway funnels, rock dressing. See `docs/CAVE_GENERATION.md`.
- **Freedom Duel.** `scripts/duel/`: first finisher is Qualified 1st and waits safely in an arena
  under the cave; the second starts the duel. 3DOF vs 2DOF + one shield, Pulse Blaster, Axis Lock,
  Freedom Core, arena DOF shifts, sudden death, hard limit, fallbacks. Bot duel brain. Server owns
  it online. Results: Champion, runner-up, then cave order. See `docs/CORE_MECHANICS.md`.

Rule changes from Prompt 2: the first finisher is never called "Winner"; the cave's Move charges
play no part in the duel; the duel loser is not a cave elimination.

## Prompt 1 state (17 Sept, commit after 48b93d5)

**Everything in Tiers 1-3 is built and tested.** Splash → Play (Bot Race / Online Race / Mixed
Race) → lobby → race → results → rematch or back to the room, with no editor.

- Offline Bot Race: 0-4 bots at three skills, seeded cave, fire, pistons, spiders, crumbling
  floors, wind, boost pads, boxes, clues, ghost, daily seed, discovered-only map, spectating.
- Online Race and Mixed Race: room codes, 2-5 racers, fill with bots, server-owned Moves,
  hearts, boxes, clues, placements; bot takeover on disconnect. Verified with a real
  three-process WebSocket race and against the Docker image.
- Gravity-aware cave validation; bots use their own clues.
- Settings: volumes, sensitivity, invert Y, fullscreen, window size, quality, key remapping.
- Windows exe verified as game and as dedicated server on the dev machine. Web export builds.

Also built: bots plan over all six gravities (wall-walks when they save a Move) and four
environments picked in the lobby.

Not done: Render deployment (needs an account), the video, itch.io submission, a clean-machine Windows test, a browser test of the web
build after networking.

Check `docs/TASK_BOARD.md` for detail and `docs/TESTING.md` for the latest test results.

## Current priority

Ship: clean-machine Windows test, record the video, screenshots, itch.io page
(`docs/SUBMISSION_CHECKLIST.md`), submit before 11:59 PM. Deploy to Render only if time allows.

## Scope history

The team first cut online play to a gated Tier 3 (`docs/MVP_SCOPE.md`). On 17 September the
team decided to build the full master prompt instead, and online and mixed races were built and
tested that day. The master prompt (`OPTIMUS_GAMEJAM_MASTER_IMPLEMENTATION_PROMPT.txt`) is the
source of truth for rules and scope; MVP_SCOPE is kept as a record of the earlier plan.
