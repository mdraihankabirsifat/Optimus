# TESTING

Every suite runs headless and exits non-zero on failure. After adding any script with a new
`class_name`, run `godot --headless --editor --quit` once first, or headless runs hang silently.

```bash
godot --headless res://tests/test_gravity.tscn    # gravity frame
godot --headless res://tests/test_cave.tscn       # cave generation
godot --headless res://tests/test_match.tscn      # match rules and health
godot --headless res://tests/test_bot.tscn        # bot fairness and exploration
godot --headless res://tests/test_flow.tscn       # every screen, lobby to results
godot --headless res://tests/test_wallwalk.tscn   # physics agrees with the validator
godot --headless res://tests/test_net_lobby.tscn  # lobby rules, no sockets
godot --headless res://tests/test_net_sim.tscn    # server authority and client mirror, no sockets
godot --headless res://tests/test_net.tscn        # real WebSocket race: server + 2 clients, ~60 s
godot --headless --fixed-fps 60 res://tests/bot_physical.tscn -- seeds=20   # physical bot races, ~3 min
```

## Results on 17 September 2026 (Windows 11, Godot 4.7.2)

| Suite | Checks | Result |
|---|---|---|
| test_gravity | 157 | pass |
| test_cave | 27 plus per-seed assertions over 200 seeds | pass |
| test_match | 43 | pass |
| test_bot | 30, 60 caves | pass |
| bot_physical | 80 physical 4-bot races | 77/80 bots finish (96%) |
| test_flow | 46 | pass |
| test_wallwalk | 3 (3 wall climbs, 5 drops) | pass |
| test_net_lobby | 37 | pass |
| test_net_sim | 56 | pass |
| test_net | 26 | pass |

## What each covers, against the master prompt

**Cave:** 200 deterministic seeds; connectivity; spawn-finish distance; loops; verticality; DOF 3
present; structural validity (symmetric links, bounds, masks); no overlapping placements; fire
and pistons/spiders outside the spawn safety radius, no fire in shafts; gravity-aware
reachability within 5 Moves with no loot; spawn explorable without a Move; same seed regenerates
the same graph hash for all 200 seeds; different seeds differ; all three size presets generate;
no crumbling cover on the guaranteed route. Hand-built caves with known answers test the
validator itself (flat 0, shaft 1, impossible with 0, drop free, wall-walk climb, arch 1).

**Gravity:** all six orientations; every 90 from every orientation; every 180; 40 chained
rotations with orthonormal basis and no drift; no camera roll on inversion; exactly one charge per
shift; denial at zero and same-direction with no charge spent; refill clamp; protected vacuum 180
costs one heart, recovers to the last safe ground, never eliminates; unrecoverable fall with no
safe ground eliminates.

**Health:** half heart and full heart; per-source cooldown; invulnerability window; 10 s standing
in fire drains at tick rate, not frame rate; Heart Refill clamps at 5; shield soaks one hit;
Second Chance leaves half a heart and works at most once; nothing resurrects; online client
hazards cannot take hearts and server hearts apply.

**Match:** countdown gates input and damage; arrival-order placements; re-entering the exit does
not re-place; elimination recorded; eliminated cannot finish; results ordering with deterministic
tie-breaks by racer id; time limit; DNF.

**Bots:** knowledge starts empty and grows only by observation; planner blind to the unseen exit;
paths never cross undiscovered cells; backtracks out of a dead end; follows its own clue with every
personality; one bot's clue is not another's; cannot plan up a shaft with 0 Moves; eliminated by
normal damage and then makes no moves; crosses an arch with one 90-degree wall-walk where inversions need two; at least 90% of 60 caves solved, never over 5 charges.

**Match/network:** 2 to 5 racers; Online humans-only; Mixed with bots and fill; 2 humans + 2 bots;
same cave hash on server and clients (and Linux server vs Windows clients); independent gravity
seen correctly by the other client; Moves deducted once and zero rejected on the server; box
contention resolved once with both clients agreeing; fall damage applied once; implausible
movement rejected; placements once in arrival order; disconnect mid-race handled by bot takeover
without crashing the server; rooms isolated from each other; results reach clients; host returns
to the room; offline suites untouched by networking.

**Build:** Windows export launched as the game (900 frames, no errors) and as a dedicated server
with two clients racing through it; Docker image built and raced through; web export builds.

## Not automated

- How the 0.35 s turn and acceleration *feel*: needs a person.
- The Windows exe on a machine without Godot installed.
- The web build in a real browser after the networking changes.
- The online lobby's visual layout at every resolution.
- A deployed Render server (no account in this environment).
