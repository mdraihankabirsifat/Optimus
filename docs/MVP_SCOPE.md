# MVP_SCOPE — The 16 September Plan (historical)

> **Superseded on 17 September 2026.** The team decided to build the full master prompt.
> Online Race, Mixed Race, the dedicated server, Docker/Render files, the spider, spectating,
> Second Chance and a gravity-aware state-graph validator were all built and tested that day.
> Still not built from the "cut" list: Jungle, Dark Cave, City Drain, and controller support.
> Current state lives in `AI_CONTEXT.md` and `docs/TASK_BOARD.md`. This file is kept as the
> record of the earlier plan and its reasoning.

**Written 16 September 2026. Deadline 17 September 2026, 11:59 PM.**

This document, not the master implementation prompt, is the authority on scope. The master
prompt is the authority on *rules*. Where they conflict on how much to build, this wins.

---

## The situation, stated honestly

The repository is a bare Godot 4.7 project. There is no player controller, no cave, no UI. The
master prompt specifies seeded procedural cave generation with gravity-aware solvability proofs,
a non-omniscient bot AI with a discovered-graph model and utility planner, an authoritative
WebSocket multiplayer server deployed to Render via Docker, four art themes, and an automated
test suite across hundreds of seeds. That is three to four weeks of work for four people.

There are roughly 40 hours of wall clock left, which is maybe 15–20 focused hours per person.

Cutting is not pessimism here. It is the only path to a submission that runs.

---

## Tier 1 — MVP. If this does not exist, there is no submission.

Everything here is required for a judge to sit down and play.

- Gravity-relative `CharacterBody3D` controller, walk + sprint + 360° look
- `G + WASD` 90° shift and `G + Space` 180° inversion, 5 charges, correct in all six orientations
- 0.35 s non-nauseating transition with no camera roll
- One cave to race through, with vertical sections that require a Gravity Move
- A hidden finish trigger that ends the match and records a time
- 5 hearts, damage, invulnerability window, elimination
- HUD: hearts, remaining Moves, timer, gravity/orientation indicator
- Main menu → play → results → retry, with no editor required
- One exported build that runs

**Target: playable end-to-end by hour 20.**

## Tier 2 — Jam version. This is what we are actually aiming to submit.

- Seeded procedural cave generation with loops, branches, dead ends, vertical shafts
- 1–4 bots that explore without knowing the exit
- Fire hazard and mystery boxes (Heart Refill, Move Refill, speed boost, penalty, rare clue)
- Results screen with placements, finish times, DNF markers, seed display
- Stone Age art pass: materials, lighting, landmarks, fog
- Audio: ambience, footsteps, gravity shift, damage, finish, menu music
- Settings with volume and mouse sensitivity, persisted
- How to Play and About/Theme screens (judges read these)
- Windows + web exports

**Target: complete by hour 34.**

## Tier 3 — Stretch. Only after Tier 2 is stable and committed.

- Online Race over WebSocket with room codes
- Mixed human/bot lobbies
- Render deployment
- Spider enemy
- Spectator mode camera cycling
- Second Chance status

## Explicitly cut

These are in the master prompt and are **not** being built. Recorded so nobody re-adds them.

| Cut | Reason |
|---|---|
| Jungle, Dark Cave, City Drain modes | Stone Age alone is barely affordable. Theme data structures stay pluggable so these are possible later. |
| Full gravity-aware state-graph solvability validator | Replaced by **solvable by construction** — see below. |
| Hundreds-of-seeds automated generation test suite | Replaced by a single dev command that generates ~50 seeds and asserts connectivity. |
| Machine-learning or deeply tuned utility-model bots | Replaced by frontier-based exploration on a discovered graph. Same visible behaviour, a tenth of the work. |
| Remappable input UI | Fixed bindings, documented on the How to Play screen. |
| Discovered-only breadcrumb minimap | Nice idea, zero chance. |
| Controller support | Out of scope. |

---

## Critical design review

Changes made to the original design, with reasoning. Per the planning prompt's format.

### 1. Solvability validation

```
Original idea:  Validate a state graph over (cell, gravity orientation, Moves remaining)
                with transitions for normal traversal, 90° shift, 180° shift and refills,
                repairing deterministically on failure.
Problem:        This is a genuinely hard piece of software. Getting it correct, and correct
                under regeneration-and-repair, is a multi-day task on its own. If it is
                subtly wrong it produces unsolvable caves, which is worse than not having it.
Recommended:    Solvable by construction. Generate a guaranteed "spine" route from spawn to
                finish first, and place every vertical break on that spine such that it is
                crossable with a known, counted number of Moves (budget: 3 of the 5). Braid
                loops and branches on afterwards — adding edges can never make a graph less
                connected. Then validate cheaply: plain BFS for connectivity, plus an assert
                that the spine's Move cost is ≤ 3.
Why:           Gives the same guarantee the player cares about (the exit is always reachable
                with the Moves you start with) for a fraction of the effort, and it cannot
                silently produce an unsolvable map.
```

### 2. Bot AI

```
Original idea:  Non-omniscient bots with a discovered-graph model and a weighted utility
                function over exploration value, clue alignment, expected box value,
                progress, travel cost, hazard risk, Move cost and revisit penalty.
Problem:        The information-boundary architecture is right and worth keeping. The
                eight-term utility model is not — it needs tuning time nobody has, and an
                untuned weighted sum behaves worse than a simple rule.
Recommended:    Keep the discovered-graph separation exactly as specified. Replace the
                utility model with frontier-based best-first search: walk to the nearest
                unexplored frontier cell by Dijkstra over the discovered graph, prefer
                frontiers in the direction of any clue held, backtrack when a branch is
                exhausted, spend a Move when the only unexplored frontier requires it.
Why:           Bots will look intelligent to a judge watching for 90 seconds, which is the
                actual requirement. The anti-cheating property — the thing that makes the
                race feel fair — lives entirely in the discovered-graph separation, and that
                is preserved.
```

### 3. Spider enemy

```
Original idea:  Spider with idle/patrol/chase/attack states using NavigationRegion3D.
Problem:        Navigation meshes assume a world up vector. In a cave where players walk on
                walls and ceilings, a nav-mesh enemy either breaks or needs its own frame
                handling. This is a trap that can eat half a day.
Recommended:    Demote to Tier 3. If built, the spider patrols a fixed corridor rail with no
                nav mesh and lunges when a racer comes within range.
Why:           Fire alone satisfies "hazards exist". The spider adds risk out of all
                proportion to the fun it adds.
```

### 4. Online multiplayer

```
Original idea:  Authoritative headless Godot server on Render over WebSocket, room codes,
                2-5 humans, mixed human/bot lobbies.
Problem:        This is the largest single risk in the project. Dockerised headless Godot,
                Render free-tier cold starts, wss:// endpoint configuration, and authoritative
                state sync are each capable of consuming the remaining time alone. The failure
                mode is catastrophic: hours spent, nothing playable, and the offline mode
                unfinished because it was deprioritised.
Recommended:    Kept in scope by team decision, as Tier 3, behind a HARD ABORT GATE.
Why:           The team wants it and it scores under Technical Achievement (10%). But it is
                worth 10% against Gameplay and Fun at 30%, so it must never be worked on at
                the expense of Tier 1 or Tier 2.
```

> ### HARD ABORT GATE — ONLINE MULTIPLAYER
>
> **Precondition:** no work begins on networking until Tier 2 is complete and committed.
>
> **Gate:** if two clients are not connected, moving, and seeing each other's gravity
> correctly **within 4 hours of starting networking work**, stop. Revert the networking
> branch, ship offline Bot Race, and record online play as a known limitation in the README.
>
> **This gate is not advisory.** Losing the offline build to a half-finished server is how
> jam teams submit nothing.

### 5. Cave size

```
Original idea:  Configurable dimensions, branch factor, loop count, verticality.
Problem:        None — but defaults matter enormously and the prompt does not fix them.
Recommended:    Target a 6x4x6 logical cell lattice, 8x8 unit corridor cross-section, and a
                90-180 second average match. Judges play once, briefly.
Why:           A big cave with an exit nobody finds reads as a broken game. Short and
                replayable beats large every time in a jam.
```

### 6. Theme legibility

```
Original idea:  Optional contextual DOF 1 / DOF 2 / DOF 3 indicator at junctions.
Problem:        Marked optional, which means it will be cut, and it is the single clearest
                signal to a judge that the theme is mechanical rather than decorative.
Recommended:    Promote to Tier 2. Show a small "DOF n" readout that counts traversable axes
                at the player's current cell. It costs almost nothing once the cave graph
                exists, because the graph already stores the connection mask.
Why:           Theme Integration is 20% of the score. This one readout converts an implicit
                design idea into something a judge can point at.
```

---

## Priority order when two things conflict

```
1. The core mechanic works
2. The game is fun
3. The theme is obvious
4. The game can actually be finished and exported
5. The level is enjoyable
6. Feedback and game feel
7. Visual polish
8. Online multiplayer
9. Everything else
```

Note that online multiplayer sits at 8, below visual polish. That is deliberate and follows
directly from the judging weights.
