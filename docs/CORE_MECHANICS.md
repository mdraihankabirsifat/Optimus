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
| `W A S D` | Gravity-relative walk |
| Mouse | 360° look — yaw on body, pitch on head |
| `Shift` | Sprint |
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
