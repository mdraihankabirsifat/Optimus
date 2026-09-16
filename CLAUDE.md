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
# Play
godot res://scenes/game/test_chamber.tscn

# Gravity verification — 150 assertions, exits non-zero on failure
godot --headless res://tests/test_gravity.tscn
```

Run the gravity test after any change to the player or gravity code.

## Working style

- Reference a Task ID from `docs/TASK_BOARD.md` in commits
- Do not commit unless asked
- Prefer the simple version — there is under two days left
- Never claim something works without running it
