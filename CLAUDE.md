# CLAUDE.md

Claude Code loads this file automatically at the start of every session in this repo.
It is deliberately short — it points at the real documents rather than duplicating them.

## Read these first

1. `AI_CONTEXT.md` — what the game is, the twelve non-negotiable rules, current state
2. `docs/CORE_MECHANICS.md` — the Gravity Move, in full
3. `docs/MVP_SCOPE.md` — what is actually being shipped, and what was cut and why
4. `docs/TASK_BOARD.md` — what exists right now. This is the authority on progress.
5. `AGENTS.md` — the full working rules

## The five rules that break this project

1. **Never write `Vector3.UP` in gameplay code.** Gravity is per racer. Use `local_up`.
2. **Never use Euler angles for body orientation.** Quaternion or basis slerp only.
3. **Never let the generator call `randi()`/`randf()`.** Everything comes from the seeded RNG.
4. **Never give the bot planner a reference to the real cave graph.** It only knows what it discovered.
5. **Never make offline Bot Race depend on networking.** It is the judging fallback.

## Environment

- Godot 4.7.2, GDScript, **GL Compatibility renderer** — do not switch to Forward+
- Deadline: 17 September 2026, 11:59 PM

```bash
# Play — main scene is the procedural cave race
godot

# Tests. Each exits non-zero on failure.
godot --headless res://tests/test_gravity.tscn   # 150 assertions
godot --headless res://tests/test_cave.tscn      # 200 seeds
godot --headless res://tests/test_match.tscn     # 29 assertions
godot --headless res://tests/test_bot.tscn       # 60 caves
godot --headless res://tests/test_flow.tscn      # every screen + a full race
godot --headless res://tests/test_wallwalk.tscn  # physics agrees with CaveValidator
godot --headless res://tests/test_net_lobby.tscn # lobby rules
godot --headless res://tests/test_net_sim.tscn   # server authority, client mirror
godot --headless res://tests/test_net.tscn       # real server + 2 clients over WebSocket (~60 s)

# Dedicated server (source or exported exe)
godot --headless --path . -- --server --port=8910
```

Online play is built: see `docs/NETWORKING.md`. Race code must work in all three
`GameWorld` roles (offline, client, server), and must find race objects with `WorldScope`,
never tree-wide groups.

Run the relevant test after any change. Gravity and cave code especially — both have
failure modes that are invisible by eye.

**After adding any script with a new `class_name`, run this once or headless tests will
hang with no output at all:**

```bash
godot --headless --editor --quit
```

Headless scene runs resolve global classes through the editor's cache. A stale cache means
the script never loads, `_ready` never fires, and the process idles forever.

Two more traps worth knowing:
- `get_tree().quit()` is ignored if called before the tree reaches its main loop. Start
  test scripts with `await get_tree().process_frame`.
- Do not measure time by counting `process_frame`. This machine has a 120 Hz display, so
  frame counts mean half the wall time you expect. Use `get_tree().create_timer()`.

## Working style

- Reference a Task ID from `docs/TASK_BOARD.md` in commits
- Do not commit unless asked
- Prefer the simple version — there is under two days left
- Never claim something works without running it
