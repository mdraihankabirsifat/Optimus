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
corridor, and each sees the other correctly oriented. First to the hidden finish wins; racers
at zero hearts are eliminated into spectator mode.

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
| Networking | Godot `WebSocketMultiplayerPeer`, server-authoritative, headless Godot on Render |
| Offline mode | Must run with zero network code paths active. This is the judging fallback. |
| Art | Stone Age only. Jungle / Dark Cave / City Drain are out of scope for the jam. |

## Current state

**Tier 1 and Tier 2 are playable end to end** (17 Sept). Splash → menu → lobby → race →
results → rematch, with no editor. Seeded cave with fire, mystery boxes and decor; 1-4
non-omniscient bots at three skill levels; full HUD with DOF readout and gravity preview;
pause menu; settings persisted; synthesised audio; How to Play, About and Credits screens.
Title is **Six Ways Down** (`AppConfig.GAME_TITLE`).

Not done: exported builds verified on Windows/web, video, screenshots for itch.io, submission.
Online multiplayer (Tier 3) was never started and is out.

Check `docs/TASK_BOARD.md` for detail. That board is the authority on progress.

## Current priority

Ship: export Windows + web, play-test by a human, record the video, submit.

## Time reality — read before planning anything

The original master prompt (`OPTIMUS_GAMEJAM_MASTER_IMPLEMENTATION_PROMPT.txt`) describes
roughly three to four weeks of work for four people. There are under two days left. That
document is the **design source of truth**, but its scope is not achievable. `docs/MVP_SCOPE.md`
holds the version the team is actually shipping. When the two conflict, MVP_SCOPE wins on
scope and the master prompt wins on rules.
