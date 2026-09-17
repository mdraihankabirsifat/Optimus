# CORE_MECHANICS — The Gravity Move

This is the backbone of the game. If this document and the code disagree, stop and fix one
of them before writing anything else.

---

## 1. The chosen implementation: Approach C

Three approaches were considered for gravity manipulation:

| Approach | Description | Verdict |
|---|---|---|
| A | Rotate the entire world around the player | **Impossible here.** Gravity is private per racer. You cannot rotate one world four different ways at once for four racers. Rejected outright. |
| B | Rotate player + camera, change the global physics gravity | **Rejected.** Godot's global gravity is a project-wide setting. Per-racer gravity would require per-body overrides anyway, which is Approach C with extra steps. |
| C | **World stays static. Each player carries their own gravity vector and orthonormal basis. Gravity is integrated manually in `_physics_process`.** | **CHOSEN.** |

**Why C wins:** the private-gravity rule forces it. It also happens to be the cheapest to build,
trivially network-friendly (one `Vector3i` per player replicates the entire orientation state),
debuggable (you can print a basis), and it keeps level geometry in one fixed world frame so the
cave generator never has to think about orientation.

**Cost of C:** you must never write `Vector3.UP` in gameplay code. Every ground check, every
movement projection, every jump uses `local_up`. This is the single most common way this
codebase will break.

---

## 2. Coordinate frames

Each player maintains:

```
gravity_dir : Vector3   # unit, one of the six cardinals. Points the way you fall.
local_up    = -gravity_dir
local_fwd   = body.basis.z * -1     # walk-plane forward
local_right = body.basis.x
```

The `CharacterBody3D` node's **own basis is the gravity frame**. Its local +Y is always
`local_up`. This is the key simplification: once the body is rotated, ordinary FPS movement
code works unchanged inside the body's local space.

```
Player (CharacterBody3D)      basis.y == local_up, yaw applied here about local_up
├── CollisionShape3D          capsule
├── Head (Node3D)             pitch applied here about local X, clamped ±89°
│   └── Camera3D
└── Visual (Node3D)           mesh; visible to others, hidden for the local first-person player
```

Movement input maps straight through the body basis:

```gdscript
var wish := body.global_basis * Vector3(input.x, 0.0, input.y)
```

Because `basis.y` is `local_up` by construction, that vector is already in the walk plane. No
extra projection needed. `up_direction = local_up` before `move_and_slide()` lets Godot handle
floor detection, snapping and slide correctly in the rotated frame.

---

## 3. Input contract

| Input | Effect |
|---|---|
| `W A S D` | Walk in the **current** gravity frame (see 3a) |
| Mouse | 360° look — yaw on body, pitch on head |
| `Shift` | Sprint, but only while a Sprint Gift window is open (Prompt 4) |
| `E` | Interact / open mystery box |
| `G` (hold) | Arms a Gravity Move. Suppresses WASD movement while held. |
| `G` + `W` | Gravity rotates 90° **toward camera forward** |
| `G` + `S` | Gravity rotates 90° **toward camera back** |
| `G` + `A` | Gravity rotates 90° **toward camera left** |
| `G` + `D` | Gravity rotates 90° **toward camera right** |
| `G` + `Space` | Gravity **inverts 180°** — your ceiling becomes your floor |
| `Escape` | Pause |

While `G` is held the player must stop walking, and an on-screen arrow previews the direction
that would be chosen. This preview is not optional polish — without it players cannot form
intent and the mechanic reads as random.

### 3a. Movement uses the current frame (Master Prompt 2)

WASD is always relative to where the racer is standing **now**, never the spawn frame:

```gdscript
var up := gravity.local_up()                                  # current gravity
var forward := camera_forward - up * camera_forward.dot(up)   # onto the walk plane
var right := forward.cross(up)
wish = right * move_input.x - forward * move_input.y
```

`PlayerController.movement_axes()` does this with fallbacks for looking straight up or down
(head up vector, then body forward). The gravity chord and bots use the same axes, so on a wall
`W` walks where you look along that wall, on the ceiling it walks where you look along the
ceiling, and chained shifts stay intuitive. `tests/test_gravity.gd` checks all six gravities at
four yaws, straight up/down looks, a nine-shift chain, and a real body walking W, D and jumping on
all six faces of a sealed room.

---

## 4. Choosing the new gravity vector

Take the camera-relative direction the player asked for, then **snap it to the nearest cardinal
axis** by maximum dot product:

```gdscript
func snap_to_cardinal(v: Vector3) -> Vector3:
    var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
                 Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
    var best := axes[0]
    var best_dot := -INF
    for a in axes:
        var d := v.dot(a)
        if d > best_dot:
            best_dot = d
            best = a
    return best
```

- `G+W` → `new_gravity = snap_to_cardinal(camera_forward_flattened)`
- `G+A` → `new_gravity = snap_to_cardinal(-local_right)`
- `G+Space` → `new_gravity = -gravity_dir` (exact, no snapping needed)

Snapping is what keeps gravity on the six cardinals even though the camera can point anywhere.
The cave is grid-aligned, so cardinal gravity always lines up with a real surface.

---

## 5. Building the new basis without roll

This is where naive implementations produce a camera that rolls randomly and makes players sick.

```
new_up = -new_gravity

# Try to keep looking roughly where you were looking.
new_fwd = (old_fwd - new_up * old_fwd.dot(new_up))      # project onto new walk plane

if new_fwd.length() < 0.01:                              # degenerate: old_fwd ∥ new_up
    new_fwd = (old_up - new_up * old_up.dot(new_up))     # fall back to old up

new_fwd  = new_fwd.normalized()
new_right = new_fwd.cross(new_up).normalized()
new_basis = Basis(new_right, new_up, -new_fwd)
```

Walking through each case:

| Command | `new_up` | Is `old_fwd` degenerate? | Resulting forward | Player experience |
|---|---|---|---|---|
| `G+W` (90° forward) | `-old_fwd` | **Yes** — `old_fwd` is parallel to `new_up` | falls back to `old_up` | The wall ahead becomes the floor. You were looking at it; now you stand on it looking at what used to be the ceiling. |
| `G+S` (90° back) | `old_fwd` | **Yes** | falls back to `-old_up` | The wall behind becomes the floor. |
| `G+A` (90° left) | `-old_right` | No — `old_fwd ⊥ old_right` | `old_fwd` unchanged | You tip sideways onto the left wall, still facing the same way down the corridor. |
| `G+D` (90° right) | `old_right` | No | `old_fwd` unchanged | Mirror of the above. |
| `G+Space` (180°) | `-old_up` | No — `old_fwd ⊥ old_up` | `old_fwd` unchanged | The world flips. You still face the same direction. |

Only the forward/back cases hit the degenerate branch, and both have a clean fallback. The
camera never rolls arbitrarily in any of the six cases.

---

## 6. The transition

```
1. Validate: charge > 0, not already transitioning, not eliminated, not finished.
   NOTE: do NOT check for a nearby surface. Shifting into empty space is legal.
2. Deduct exactly one charge. Server-authoritative. Exactly once.
3. Enter TRANSITIONING state: lock movement input, zero horizontal velocity.
4. Slerp body basis from old to new over GRAVITY_TRANSITION_TIME (default 0.35 s).
   Use Quaternion.slerp or Basis.slerp. Never lerp Euler angles.
5. On completion: set gravity_dir, set up_direction, unlock movement.
6. Fire the shift SFX, a restrained screen effect, and the HUD charge animation.
```

0.35 s is the tuned default. Below ~0.25 s it reads as a jarring snap; above ~0.5 s players feel
they have lost control mid-race. Expose it with `@export` and leave it alone unless playtesting
says otherwise.

If charges are zero, reject with a distinct "denied" sound and a HUD flash. Never silently ignore
the input — players will think the game is broken.

---

## 7. Falling into vacuum, and the protected 180° case

Shifting toward empty space is a legitimate move. You fall along the new gravity until you hit a
surface. That is the intended risky play.

But one case is explicitly protected by the designers:

> If a player uses a **180° Move while the space above them is vacuous**, this must NOT eliminate
> them. It damages hearts instead, then recovers them to the last safe grounded transform.

Implementation:

```
Maintain a ring buffer of the last ~8 "safe grounded transforms" — sampled every ~0.5 s while
is_on_floor() is true and no hazard is in contact.

On out-of-bounds / kill-volume contact:
    if the triggering action was a 180° Move within the last N seconds:
        deal VACUUM_FALL_DAMAGE (default 1 heart)
        teleport to the most recent safe grounded transform
        grant invulnerability frames
    else:
        apply the normal out-of-bounds rule
```

Keep the "was this a 180° into vacuum" flag on the player, set at shift time and cleared when they
next land safely. This is simpler and more reliable than trying to raycast for vacuum up front.

---

## 8. Worked example

```
        ceiling
    ════════════════
                                Player is in a corridor. A ledge above holds
         [ledge]                the route onward. Normal movement cannot reach it.
    ┌──────────────┐
    │              │            Player presses G + Space.
    │      @       │            Cost: 1 Move. Charges 5 → 4.
    ════════════════            Gravity flips +Y.
        floor
```

```
        floor (was ceiling)
    ════════════════
         @                      0.35 s later the player stands on the old ceiling.
    ┌──────────────┐            Camera still faces down the corridor — no roll.
    │              │            The ledge is now below them and trivially reached.
    │              │
    ════════════════
        ceiling (was floor)     A second racer sprints past down there, upright in
                                their own frame. Neither player's gravity affected
                                the other's.
```

That last detail — two racers in the same corridor with different up vectors — is the single
most memorable image the game has. Protect it. It is the theme made visible.

---

## 9. Replication

Per player, per state update:

| Field | Type | Notes |
|---|---|---|
| `gravity_dir` | `Vector3i` | one of six cardinals; fits in 3 bytes of intent |
| `body_basis` | `Quaternion` | or derive from gravity_dir + yaw to save bandwidth |
| `is_transitioning` | `bool` | remote players must show the same 0.35 s rotation |
| `move_charges` | `int` | server-authoritative, never client-set |

Remote players interpolate. Never snap a remote transform every frame — it destroys the
"someone is running on the wall over there" moment, which is the thing worth protecting most.

---

## 10. Things that will break this system

- Writing `Vector3.UP` anywhere in gameplay code. Grep for it before every commit.
- Using `look_at()` on the player body — it assumes a world up and will introduce roll.
- Euler angles for body orientation. Gimbal lock after chained rotations.
- Applying gravity before `up_direction` is set in the same frame.
- Letting the client deduct its own charge. Double-deduction and cheating both follow.
- Running the ground check against world −Y instead of `gravity_dir`.

---

## 11. The Freedom Duel (Master Prompt 2)

The cave no longer names a winner. The first **two** racers through the exit fight for Champion.
Code: `scripts/duel/freedom_duel.gd` (rules), `duel_arena.gd` (the arena), `freedom_core_visual.gd`,
`scripts/ui/duel_hud.gd`, and the duel brain at the end of `scripts/bots/bot_controller.gd`.
Every number is in `autoload/app_config.gd` under "Freedom Duel".

**Qualification.** `MatchController` records the finish as always, then tells `FreedomDuel`.
The first finisher is **Qualified 1st**: moved to the arena under the cave, free to move, cannot
be damaged, cannot reach anyone still racing. The second is **Qualified 2nd** and starts the duel.
Everyone still in the cave stops where they are; hops left to the exit order them in the results.
Once anyone qualifies, only the duel ends the race.

Fallbacks, so nothing waits forever: nobody else can still qualify (all eliminated or gone) ->
Qualified 1st is Champion by default; 90 s with no second qualifier -> the same; the 300 s race
limit while waiting -> the same; a finalist disconnects mid-duel -> the other is Champion;
the duel reaches 90 s -> most hearts wins, then most damage dealt, then Qualified 1st.

**Freedom in control terms.** `PlayerController.duel_dof`:

| DOF | Can do | When |
|---|---|---|
| 3 | walk the floor plane and jump (higher than the cave jump) | Qualified 1st's start |
| 2 | walk the floor plane, no jump | Qualified 2nd's start; ramps still reach the high ground |
| 1 | walk one arena axis only | only from an Axis Lock, 3 s |

No Gravity Moves exist in the duel: the G chord is ignored while `duel_dof > 0`, and cave charges
are irrelevant (a finalist with zero Moves duels exactly like one with five).

**Health.** Both finalists get 5 fresh hearts. `PlayerHealth.duel_mode`: 0.2 s invulnerability
after a hit, no Second Chance, and zero hearts emits `duel_down`, never `eliminated` -- the loser
is not a cave elimination. Qualified 2nd's one compensation is a single one-hit shield.

**Weapons** (hitscan from the eye, blocked by walls and cover):
- **Pulse Blaster** (LMB, hold to repeat): 0.5 hearts, 0.45 s cooldown.
- **Axis Lock** (RMB or Q): 0.25 hearts and removes one degree of freedom for 3 s
  (3DOF loses Y, the jump; 2DOF is pinned to the X or Z axis it was facing). 6 s cooldown. After a
  lock ends the target is immune to another for 3 s, so nobody can be chain-locked.

**Freedom Core.** Appears 6 s in, then 12 s after each capture, cycling five pedestals (centre,
both platforms, two floor ends). Walk into it: +1 DOF for 8 s; already at 3DOF, a shield (or a
speed burst if already shielded). It never permanently erases Qualified 1st's advantage.

**Arena DOF shifts.** First at 15 s, then every 18 s, for 5 s, in a fixed order:
FULL FREEDOM (everyone at least 3DOF), Y AXIS LOCKED (nobody jumps), FREEDOM SURGE (everyone faster).

**Sudden death** at 60 s: both finalists 3DOF, shields removed, hits deal 1.5x. No more shifts.

**Arena.** 40 x 40 units at `DuelArena.ORIGIN`, far below the cave and inside world bounds. Red X
and blue Z lines cross the floor, green Y beams stand in the corners. Two high platforms (2.2 up)
with ramps, four pillars and two waist-high walls for cover.

**Spectating.** Non-finalists' camera follows the two finalists (Tab switches). The duel HUD shows
both names, hearts, shield, [X][Y][Z] boxes and DOF, lock timer and immunity, core state, timer,
active shift and sudden death; finalists also get a crosshair and weapon cooldown bars.

**Results.** Champion, duel runner-up, then everyone else in cave order (finishers, eliminated,
stopped racers by distance to the exit). The first finisher is labelled "Q1", never "Winner".
Duel stats per finalist: duration, damage dealt, Axis Locks landed, cores captured.

**Online.** The server's `FreedomDuel` decides everything and `NetMatch` sends `s_duel_state`
(on every change and at 10 Hz) and `s_duel_event` (shots, locks, cores, the end), each from the one
place it happened. Clients send `c_duel_fire(kind, origin, dir)`; the server checks the phase,
the cooldown and that the muzzle is at the shooter, then resolves the hit. A client's
`FreedomDuel` is a mirror that never resolves anything. See `docs/NETWORKING.md`.

---

## 12. Master Prompt 3: timers, the last-heart state, contact and bots

**Four separate clocks, never mixed.**

| Clock | Where | Runs | Ends |
|---|---|---|---|
| Elapsed | `MatchController.elapsed` | from GO | never ends the race in Normal |
| Rush cave deadline | `MatchController.cave_time_limit` | from GO, Rush only (180/300/480 s) | `_expire_cave()` once |
| Last-heart grace | `PlayerHealth.grace_left` | 20 s from the trade that spent the last heart | eliminates once; cleared on qualifying |
| Duel | `FreedomDuel.duel_time` | from FIGHT | sudden death 60 s, decision 90 s |

Rush expiry, exactly once, cave phase only: two qualifiers -> the duel keeps running and anyone
still in the cave is DNF; one qualifier -> Champion by default ("Rush time up"); none -> race over,
"Time up -- no qualifiers", no Champion. A finish at or before the deadline counts; later ones do
not. Normal has no cave deadline and no waiting limit: Qualified 1st waits while anyone can still
qualify, and the race resolves through elimination, disconnection or everyone resolving. Grace
never extends a Rush deadline.

**Heart for a Move.** `GameWorld.request_heart_exchange(body)` is the only transaction, used by
the local player offline, by the server for `c_exchange`, and by bots. It checks: racing in the
cave (not countdown, not finished, not eliminated, not a finalist, cave not expired), Move regen
off, Moves below the cap, and at least one full heart. Then it takes exactly one heart
(`PlayerHealth.exchange_heart()`, not the damage path: shields, invulnerability and Second Chance
play no part) and adds exactly one Move. If that took the last heart, `grace_left` starts at 20 s.
Health states: active (hearts > 0) -> last-heart grace (0 hearts from a trade, still playable) ->
eliminated; or qualified (grace cleared) -> duel health. Nothing resets or extends the deadline;
a Heart Refill restores hearts but the deadline still fires. A real hit at zero hearts during grace
eliminates as usual. The player must press twice to spend the last heart; the server debounces
repeated requests (0.25 s). Online, `s_racer_state` carries `grace_left` with hearts and Moves.

**Contact.** Racers are on layer 2 and now mask layer 2 as well, so they collide with each other
on every surface (`tests/test_prompt3.gd` walks one into another under all six gravities and pulls
overlapping racers apart). `PlayerController.set_solid(false)` takes a finished or eliminated
racer off layer 2: it stops blocking and stops triggering hazards but still stands on the world.
Freedom Duel finalists are made solid again in the arena. Fire's damaging box is the flame you see
and at most about a third of the cell's height (1.4 units in a tunnel), leaving a ceiling walker
2.4 units of clearance. Spikes (`SpikeHazard`) have a solid core and a slightly larger damaging
shell, half a heart per touch with a 1 s cooldown; crystal clusters have a box collider and do not
hurt. Both are only placed in landmark chambers, so they can never close a route in a 4-unit tunnel.

**Bots that stop.** `BotController._watchdog` tracks real progress (moving 1.2 units). An explained
wait (countdown, easy-bot pause, gravity turn, waiting for a regenerated Move) never escalates.
An unexplained stall escalates: 2.5 s replan; 5 s mark that passage blocked for 20 s
(`BotKnowledge.block_edge`, which the planner skips) and hop; 8 s gravity escape -- flip onto the
ceiling if the cell has one, else turn onto a solid wall and climb toward the old ceiling past the
lip -- paid for with a Move (or waiting for regen, or trading a heart if legal and not the last
one), at most two escapes per cell; 14 s cycle again. Two racers nose to nose: the higher instance
id steps right for 0.7 s. `debug_state()` reports stage, note, wait reason and recovery count for
tests and logs only.
