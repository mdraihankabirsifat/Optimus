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
godot --headless res://tests/test_themes.tscn     # environments never change the race
godot res://tests/theme_shot.tscn                 # (window) one screenshot per environment
godot --headless res://tests/test_net_lobby.tscn  # lobby rules, no sockets
godot --headless res://tests/test_net_sim.tscn    # server authority and client mirror, no sockets
godot --headless res://tests/test_net.tscn        # real WebSocket race: server + 2 clients, ~60 s
godot --headless --fixed-fps 60 res://tests/bot_physical.tscn -- seeds=20   # physical bot races
godot --headless --fixed-fps 60 res://tests/bot_physical.tscn -- seeds=10 rush=180   # Rush caves
godot --headless --fixed-fps 60 res://tests/test_prompt3.tscn   # Prompt 3 physics, trades, hints, compass, pits
godot --headless res://tests/cave_metrics.tscn -- seeds=60 size=1 rush=180   # cave shape numbers
godot --headless --fixed-fps 60 res://tests/test_prompt4.tscn   # Prompt 4: Sprint Gifts, Battle Mode, cave floors
godot --headless --fixed-fps 60 res://tests/bot_physical.tscn -- seeds=8 size=2 limit=300   # per-size completion times
```

## Results after Master Prompt 4 (18 September 2026, Windows 11, Godot 4.7.2)

Run with `--headless --fixed-fps 60` except `test_net` (real sockets, wall clock). Every row below
was produced by an actual run of this code.

| Suite | Checks | Result |
|---|---|---|
| **test_prompt4** (new) | 38: Sprint Gift gating, the exact 5 s window, refresh without stacking, expiry mid-hold, pickup and regrowth; Battle spawns 16+ units apart, one point per kill, no double kill, respawn delay and placement away from the killer, spawn protection, cave deaths credit nobody, no heart trade, no exit, a kill as the clock stops, tie-breaks and a draw, two Battle worlds kept apart; per-size cave floors and long cuts | pass |
| test_gravity | 338 | pass |
| test_cave | 134 (new generator: long cuts, route floors, Rush still easier) | pass |
| test_match | 45 | pass |
| test_bot | 30 | pass |
| test_duel | 92 | pass |
| test_flow | 46 | pass |
| test_themes | 50 | pass |
| test_wallwalk | 3 | pass |
| test_net_lobby | 41 | pass |
| test_net_sim | 88 (adds Battle Mode: the server scores, the client mirrors and never resolves its own shot) | pass |
| test_net | 43, real WebSocket server + 2 clients | pass |
| test_prompt3 | 71 (two bot-pit waits lengthened: bots walk now that Shift needs a gift) | pass |

Battle Mode over real sockets with 3-4 clients at once has **not** been run: `test_net` drives two
clients, and `test_net_sim` covers the Battle server/client split in-process. Concurrent Battle
arenas are covered in-process only.

## Results after Master Prompt 3 (17 September 2026, Windows 11, Godot 4.7.2)

Run with `--headless --fixed-fps 60` except `test_net` (real sockets, wall clock). Every count
below was produced by an actual run of the committed code.

| Suite | Checks | Result |
|---|---|---|
| test_gravity | 338 | pass (one vacuum-test racer moved off the origin: racers now collide) |
| test_cave | 134 (adds Rush profiles for every size and length vs Normal) | pass |
| test_match | 45 (Normal has no limit; Rush expires) | pass |
| test_bot | 30 | pass |
| test_duel | 92 (adds Rush expiry with 0/1/2 qualifiers; Normal waits with no limit) | pass |
| test_flow | 46 | pass |
| test_themes | 30 | pass |
| test_wallwalk | 3 | pass |
| test_net_lobby | 41 (adds name rules: blank refused, Unicode, markup, 20 characters) | pass |
| test_net_sim | 80 | pass |
| test_net | 43: server + host + guest + a second arena; codes, double create, bad codes, synced Rush 8 min, heart trade through the server, Freedom Duel | pass |
| **test_prompt3** (new) | 71: fire ceiling/wall bypass and floor burn; racers collide on six surfaces and separate; non-solid racers pass; spikes block and sting once; crystals block; heart trade rules and last-heart deadline; remapped hints; world compass; bots escape a ledge by ceiling and by wall; zero-Move regen wait, heart trade, last-heart refusal | pass |

Physical bot races (`tests/bot_physical.tscn`, 10 caves x 4 Hard bots, duel off, 150 s cap):

| Run | Finished | Average time | DNFs |
|---|---|---|---|
| Normal (Standard) | 33 / 40 (83%) | 1:15 | 3 eliminated by hazards, 4 still moving with no Moves at the cap; no unexplained stalls |
| Rush 3 min (Standard) | 40 / 40 (100%) | 0:33 | none |

These are simulated bots, not human play. Human checks still needed: Rush navigability and
collision feel at a keyboard, the Freedom Duel's feel, fullscreen -> windowed -> minimise ->
restore on a standalone Windows build, the web build in a browser, and online play against a
deployed public server.

### Results after Master Prompt 2 (17 September 2026, Windows 11, Godot 4.7.2)

Run with `--headless --fixed-fps 60` except `test_net` (real sockets, wall clock).

| Suite | Checks | Result |
|---|---|---|
| test_gravity | 338 (adds current-frame axes on six gravities, chained shifts, real walking on six faces) | pass |
| test_cave | 59 plus per-seed assertions (adds cave shape per preset, long loops) | pass |
| test_match | 43 | pass |
| test_bot | 30, 60 caves | pass |
| test_duel | 86 (qualification, DOF, health, weapons, lock immunity, core, shifts, sudden death, results, fallbacks, bot-vs-bot duel) | pass |
| bot_physical | 10 caves x 4 Hard bots, duel off | 30/40 finish (75%); every cave has 2+ finishers |
| test_flow | 46 | pass |
| test_wallwalk | 3 (5 wall climbs, 5 drops) | pass |
| test_themes | 30 | pass |
| test_net_lobby | 37 | pass |
| test_net_sim | 80 (adds server-owned duel: finalists, hits once, cooldown, garbage aim, lock, core owner, forfeit, client mirror) | pass |
| test_net | 36: real server + 2 clients; host Qualified 1st, guest Qualified 2nd, FIGHT on both, DOF synced, 8/8 guest shots hit via the server, guest drops and forfeits, results lead with the Champion | pass |

`godot --headless --fixed-fps 60 res://tests/test_duel.tscn` and
`godot --headless res://tests/cave_metrics.tscn -- seeds=100 size=1` are new.

Not yet re-verified after Prompt 2: Windows and Web exports, a clean machine, a browser, and
human playtests of the duel's feel (weapon timing, bot difficulty, arena readability).

### Prompt 1 results (for comparison)

| Suite | Checks | Result |
|---|---|---|
| test_gravity | 157 | pass |
| test_cave | 27 plus per-seed assertions over 200 seeds | pass |
| test_match | 43 | pass |
| test_bot | 30, 60 caves | pass |
| bot_physical | 80 physical 4-bot races | 77/80 bots finish (96%) |
| test_flow | 46 | pass |
| test_wallwalk | 3 (3 wall climbs, 5 drops) | pass |
| test_themes | 30 | pass |
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

**Environments:** each of the four builds seed 4242 with the same graph hash, boxes and hazards; lighting and fog applied; signature props placed; Dark Cave lamp present and only there; no theme too dark to navigate; rooms carry the environment; unknown ids fall back to Stone Age. Screenshots of all four were reviewed.

**Menus at common resolutions:** `tests/lobby_shot.tscn` (window, needs a server on 8940) captures the Play screen, Settings and a live 5-slot Mixed lobby at 1280x720 and 1920x1080. Reviewing them found the host controls clipped at 1280x720 and Start below the fold; both fixed and re-checked.

**Build:** Windows export launched as the game (900 frames, no errors) and as a dedicated server
with two clients racing through it; Docker image built and raced through; web export builds, and
the exported page loads in headless Chrome (WebGL through SwiftShader) and renders the splash screen.

## Not automated

- How the 0.35 s turn and acceleration *feel*: needs a person.
- The Windows exe on a machine without Godot installed.
- Playing a full race in the web build after the networking changes (it loads and renders in
  Chrome; a full race was played in Chrome on 16 September, before networking).
- A deployed Render server (no account in this environment).
