# CAVE GENERATION

## Model

A cave is a `CaveGraph`: a dictionary of `Vector3i` lattice cells, each an 8 x 8 x 8 pocket of
air with a 6-bit mask of open faces (+X, -X, +Y, -Y, +Z, -Z). Pure data, no nodes, no randomness.
`CaveBuilder` turns it into geometry. `CaveGenerator` makes it from one integer seed.

## Steps (`scripts/cave/cave_generator.gd`)

1. **Spine.** From a random floor-level spawn, wander 3-6 horizontal steps, climb one cell, repeat.
   2-3 climbs, chosen up front. The last cell is the hidden finish.
2. **Branches.** Horizontal side passages and dead ends. Always horizontal: a branch that climbed
   would create a dead end whose only exit is vertical, which softlocks a racer out of Moves.
3. **Loops.** Links between already-adjacent cells, biased 85% horizontal. Every one adds a cycle.
4. **Hazards and boxes.** Fire (never within 3 hops of spawn, never in a shaft cell, one edge always
   clear), boxes (favouring dead ends). No two in one cell, none in spawn or finish.
5. **Decor.** Stalagmites, crystals, moss, torches; ember stones within two hops of the exit.
6. **Features.** Boost pads, wind, pistons, spiders, crumbling shaft covers (never on the spine),
   shortcut markers, landmark chambers.
7. **Validate** (below). On failure, retry with seed `seed * 7919 + attempt`, up to 24 times, so a
   repaired cave is still reproducible. `last_failure` says why an attempt failed.

All randomness comes from the one seeded `RandomNumberGenerator`. `CaveGenerator.VERSION` is
checked in the online handshake.

## Validation

| Invariant | Check |
|---|---|
| Spine climbs within budget | `spine_climb_cost() <= 3` |
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

Measured over 200 Standard seeds: every cave needs exactly 1 Move under the full rules (one
inversion climbs every aligned shaft). The spine promises at most 3.

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
