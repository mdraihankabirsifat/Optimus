# CAVE GENERATION

## Model

A cave is a `CaveGraph`: a dictionary of `Vector3i` lattice cells, each an 8 x 8 x 8 pocket of
air with a 6-bit mask of open faces (+X, -X, +Y, -Y, +Z, -Z). Pure data, no nodes, no randomness.
`CaveBuilder` turns it into geometry. `CaveGenerator` makes it from one integer seed.

## Steps (`scripts/cave/cave_generator.gd`, VERSION 5)

Prompt 2 made the cave corridor-first: long passages, real loops, dead ends, and routes that
go both up and down. Numbers below are the Standard preset; Short and Long scale them
(`SIZE_PRESETS`).

1. **Spine.** Start on a middle level. Plan the vertical steps up front (3-4, both up **and**
   down, never more Moves than the budget), then lay straight runs of 3-6 cells between them,
   turning only where a run ends. The last cell is the hidden finish, at least 14 hops out.
2. **Branches.** 8 horizontal side passages of 2-5 cells, sometimes with one turn, grown from
   cells that are not already junctions. Most end in a dead end. Always horizontal: a branch
   that climbed would make a dead end whose only exit is vertical.
3. **Loops.** 3 passages carved through empty rock until they meet the existing cave at a cell
   at least 6 hops away along the cave, so every loop is a real detour back to a known place,
   never a one-cell hop. A quarter may step up or down on the way, making upper and lower routes.
4. **Hazards and boxes.** Fire (never within 3 hops of spawn, never in a shaft cell, one edge always
   clear), boxes (favouring dead ends). No two in one cell, none in spawn or finish.
5. **Decor.** Stalagmites, crystals, moss, torches; ember stones within two hops of the exit.
6. **Features.** Boost pads, wind, pistons, spiders, crumbling shaft covers (never on the spine),
   shortcut markers, landmark chambers.
7. **Validate** (below). On failure, retry with seed `seed * 7919 + attempt`, up to 40 times, so a
   repaired cave is still reproducible. `last_failure` says why an attempt failed.

All randomness comes from the one seeded `RandomNumberGenerator`. `CaveGenerator.VERSION` is
checked in the online handshake.

## Geometry (`scripts/cave/cave_builder.gd`)

The lattice pitch stays 8 units, but an ordinary cell is now a **tunnel**: 4 units clear
(`AppConfig.CAVE_TUNNEL_WIDTH`), with solid rock around it. Spawn, finish and landmark cells are
**chambers**, 7 units wide and taller. Every cell shares one floor height, so walking between
tunnel and chamber on the floor is flush.

A chamber is still bigger than its tunnels on its walls and ceiling, and a racer can walk any of
the six faces. Where a face met a doorway that difference was a 1.5 unit ledge: a wall to someone
walking the ceiling toward it (bots stuck there in testing). Every chamber doorway now has a
**funnel** of sloped sides (about 31 degrees) from the chamber's cross-section down to the tunnel
mouth. A funnel side facing another doorway is left out so it never blocks that tunnel.

Visual only, no collision: rock lumps along wall edges, bulges on flat walls and rubble on the
floor, placed from the cell coordinates (identical on every machine), and one stone shade per cell
instead of per slab.

## Shape, measured

`godot --headless res://tests/cave_metrics.tscn -- seeds=100 size=1` prints these. 100 seeds each:

| | Before (VERSION 3) | Short | Standard | Long |
|---|---|---|---|---|
| Cells | 54.1 | | 83.3 | 129.6 |
| Junction share | 33% | 14% | 14% | 15% |
| Average straight run (cells) | 1.10 | 1.91 | 2.01 | 2.15 |
| Route cells between junctions | 1.22 | 4.20 | 4.48 | 4.41 |
| Dead ends | 14.0 | 4.2 | 6.5 | 9.8 |
| Loops (cycles) | 6.1 | 2.0 | 3.0 | 5.0 |
| Levels used | 3.49 | 2.43 | 2.98 | 3.46 |
| Route climbs **and** descends | 0 of 100 | 100 | 100 | 100 |

The old generator's "loops" were mostly one-cell links between neighbours; the new ones are
checked to detour at least 4 hops (`tests/test_cave.gd`, `_test_loops_are_long`). Before, the
route only ever went up.

Physical bots in the new caves (`tests/bot_physical.tscn -- seeds=10`, four Hard bots, 150 s cap):
30 of 40 finish, and every cave had at least two finishers, so every race reaches the Freedom Duel.
Before the doorway funnels it was 17 of 40.

## Rulesets: Normal and Rush profiles (Prompt 3)

`CaveGenerator.configure(size, ruleset, rush_seconds)` is the only way a race configures the
generator, on the server, on every client and in tests. Normal is exactly the size preset (its
output is unchanged, checked seed by seed in `test_cave`). Rush applies `apply_rush_profile()` on
top: fewer and shorter side branches, one or two loops, two planned vertical steps (three for
8 minutes), shorter legs and runs, a shorter minimum route, fewer boxes and fires. The 3-minute
profile is the gentlest. The exit is still hidden; Rush is easier to read, not solved.

`CaveGenerator.profile` ("normal", "rush180", "rush300", "rush480") is part of the race's record key
together with the generator version and Move regen (`GameState.make_record_tag`), so records and
ghosts from different rules never mix. Old "seed:size" records stay in the file untouched.

Measured, 60 seeds per row (`tests/cave_metrics.tscn -- seeds=60 size=N [rush=S]`):

| Size | Rules | Cells | Route hops avg (min-median-max) | Dead ends | Loops | Off-route cells | Moves needed |
|---|---|---|---|---|---|---|---|
| Short | Normal | 53.8 | 22.2 (10-24-38) | 4.2 | 2.0 | 54% | 1.17 |
| Short | Rush 3 min | 25.1 | 14.4 (7-14-23) | 2.0 | 1.0 | 33% | 1.02 |
| Short | Rush 8 min | 28.1 | 16.0 (7-16-27) | 2.0 | 1.0 | 35% | 1.10 |
| Standard | Normal | 82.9 | 27.6 (14-26-56) | 6.6 | 3.0 | 64% | 0.98 |
| Standard | Rush 3 min | 33.0 | 15.4 (9-15-27) | 2.0 | 2.0 | 42% | 1.10 |
| Standard | Rush 5 min | 36.4 | 15.7 (8-15-26) | 2.5 | 2.0 | 49% | 1.03 |
| Standard | Rush 8 min | 39.9 | 18.9 (11-19-33) | 2.7 | 2.0 | 44% | 1.00 |
| Long | Normal | 129.4 | 33.3 (20-32-56) | 9.9 | 5.0 | 72% | 1.13 |
| Long | Rush 3 min | 39.5 | 18.9 (11-18-31) | 2.5 | 2.0 | 44% | 1.02 |
| Long | Rush 8 min | 51.3 | 23.0 (14-22-42) | 4.3 | 2.0 | 49% | 1.13 |

`tests/test_cave.gd` asserts, per size and Rush length over 30 seeds: every seed generates and is
solvable, the same configuration gives the same cave, the route is under 80% of Normal's, fewer
dead ends and a smaller off-route share, and every Rush cave still has a loop and climbs and descends.

Prompt 3 decor rule: stalagmites, stalactites and crystal clusters are solid now, so they are placed
only in chambers (spikes only in landmark chambers). Doorway funnels were already there.

## Length, dead ends and long cuts (Prompt 4)

Prompt 4 asks for caves that take longer to get out of, with more dead ends and with "long cuts":
detours that leave the route and rejoin it further along, so taking one costs time but is not a
trap. Three generator knobs do it, all per size preset:

| Preset | Size | Branches (dead ends) | Long cuts | Route floor |
|---|---|---|---|---|
| Short ("easy") | 9x3x9 | 10 | 2 | 45 s of walking |
| Standard | 11x4x11 | 14 | 2 | 60 s |
| Long | 13x5x13 | 18 | 3 | 75 s |

`_add_long_cuts()` runs between the branches and the loops. It picks a cell on the route, walks a
corridor away from it (up to `long_cut_len_max` cells) and rejoins the route at least
`long_cut_extra` hops further along, so the detour is always longer than the straight line it
replaces. `CaveGenerator.last_long_cuts` reports how many a cave actually got.

The floor is a *lower bound on the fastest possible run*, not an average. `route_seconds(graph,
moves)` values the shortest gravity-aware route at `hops x CELL_SIZE / WALK_SPEED` plus 2.5 s per
Gravity Move, which is what a racer who already knows the way would need. A cave under its floor is
thrown away and the seed is regenerated (up to `max_attempts`, now 140). Since the exit is hidden,
ordinary play explores roughly twice the shortest route, so the 45 / 60 / 75 s floors are the
documented reading of "an easy cave takes at least 90 seconds": 45 s of pure walking, about 90 s
played. Harder sizes scale with it.

Rush keeps its promise to be easier than Normal: `apply_rush_profile()` scales the floor to
0.5-0.7 of Normal's and allows at most one long cut, so every Rush assertion in `test_cave`
(shorter route, fewer dead ends, smaller off-route share) still holds.

Battle Mode uses `apply_battle_profile()`: a third of the branches, short stubs, three extra loops,
no long cuts, no route floor and fewer fires -- an arena to circle in, not a maze to solve. There is
no exit to reach, so route length means nothing there.

Measured (`tests/cave_metrics.tscn -- seeds=30 size=N`, walking seconds of the shortest route):

| Size | Fastest | Median | Slowest | Long cuts per cave | Failed seeds |
|---|---|---|---|---|---|
| Short | 45 s | 56 s | 78 s | 1.0 | 0 |
| Standard | 61 s | 72 s | 104 s | 1.7 | 0 |
| Long | 77 s | 93 s | 126 s | 2.5 | 0 |

## Validation

| Invariant | Check |
|---|---|
| Spine within budget | `spine_move_cost()` within the preset's budget |
| Dead ends | at least 2 |
| Real loops | at least `min(loop_count, 2)` cycles |
| Connected | every cell reachable from spawn |
| Spawn and finish far apart | at least 8 hops (Standard), 6 Short, 11 Long |
| At least one loop | `edges - cells + 1 >= 1` |
| Verticality | at least 2 vertical links |
| Theme present | at least one DOF 3 cell |
| Structure | `CaveValidator.structural_problem`: symmetric links, in bounds, valid masks, no overlapping placements |
| **Gravity-aware solvability** | `CaveValidator.min_moves_to_finish(graph, 5)` is reachable |

### Gravity-aware solvability (`scripts/cave/cave_validator.gd`)

A 0-1 breadth-first search over states `(cell, gravity direction, Moves spent)` from spawn with
gravity down and 5 Moves, no loot. Transitions match what the player controller physically does:

- **fall**: cell open in the gravity direction, the racer drops into the next cell. Free, forced.
- **walk**: standing on a surface, move into any linked neighbour perpendicular to gravity. Free.
- **climb against gravity**: impossible (a jump reaches about 1.3 units; a cell is 8).
- **shift**: any of the other five gravities, standing or falling. Costs 1 Move.

`tests/test_wallwalk.gd` drives a real `PlayerController` through generated geometry to confirm
the two physical claims: under sideways gravity a racer walks up a wall into the shaft above, and
under normal gravity it drops through an open floor.

The validator, not the spine plan, is the guarantee: a loop can open a shaft under the planned
route and change what it costs, so `tests/test_cave.gd` checks every seed's real requirement
against the five starting Moves.

## Degrees of freedom

`degrees_of_freedom(cell)` counts axes with at least one open face: a tunnel is 1, a crossroads 2,
a junction with a shaft 3. The HUD shows it live.

## Debug

- `godot --headless res://tests/test_cave.tscn` prints per-seed failures and statistics.
- **F3 in a debug run** (editor or source, never an exported build) toggles `CaveDebugView`:
  every edge, the spine, shafts, spawn, the exit, boxes, hazards, and one bot's discovered graph and
  current plan (F4 cycles bots) with a readout of what it knows. `tests/debug_view_shot.tscn` renders it.
- `tests/cave_shot.tscn` and `tests/theme_shot.tscn` render the cave from a racer's view.
- `M` in a race shows the discovered-only map: cells you stood in, never the exit.
