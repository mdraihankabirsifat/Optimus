# AGENTS.md — Rules for AI Agents Working on This Repository

For Claude, Codex, ChatGPT, or any other agent asked to modify this project.

## Before coding

1. Read `AI_CONTEXT.md`. Then `docs/CORE_MECHANICS.md`, `docs/ARCHITECTURE.md`, and
   `docs/NETWORKING.md` if you touch anything a race runs. `docs/MVP_SCOPE.md` is history.
2. Read `docs/TASK_BOARD.md` to find out what actually exists. Do not assume a system is
   built because a document describes it.
3. Work against a Task ID. If the request has no Task ID, find the matching one or add a row.
4. Search before creating. Duplicate systems are the most common failure mode in AI-assisted
   development on this project — check whether a controller, generator or manager already
   exists before writing a new one.

## While coding

5. **Never write `Vector3.UP` in gameplay code.** Use the player's `local_up`. This is the
   rule that breaks most often and it silently produces a game where wall-walking is subtly
   wrong. Grep for it before you finish.
6. Never use Euler angles for body orientation. Quaternion or basis slerp only.
7. Keep gravity private per racer. A Move never rotates the world and never touches another
   racer's frame.
8. Preserve determinism. All generation comes from the seeded `RandomNumberGenerator`. Never
   call `randi()` or `randf()` inside the generator.
9. Keep bot knowledge separate. `bot_planner.gd` and `bot_knowledge.gd` must never hold a
   reference to the real cave graph. If you find yourself passing one in, stop — that is the
   fairness of the whole race.
10. Keep the server authoritative over charges, health, loot and placements. Clients never
    award themselves anything. New state that decides a race goes through `NetMatch` on the
    server and is mirrored to clients; see `docs/NETWORKING.md`.
11. **Offline Bot Race must work with networking entirely absent.** It is the judging
    fallback. Race code checks `GameWorld.net_role`; it never calls `NetManager` offline.
    If your change makes offline play depend on `NetManager`, the change is wrong.
11a. Never use tree-wide groups to find race objects. The dedicated server runs several rooms
    in one process; use `WorldScope.nodes(self, group)` so a room only sees itself.
11b. Anything a race needs must work in all three `GameWorld` roles: offline, client, server.
    The server has no local player and no HUD.
12. Respect the ownership table in `docs/ARCHITECTURE.md`. Each script has a "must not" column.
13. Tunables go in `AppConfig` or `@export`. No inline magic numbers.
14. Prefer the simple version. A working simple system beats an elegant unfinished one.
15. No plugins. No new dependencies. Docker's base image and the Godot binary it downloads are
    recorded in `CREDITS.md`.

## After coding

16. Run the project and read the output. Fix every error and every warning you introduced.
17. Test the changed system in isolation, then in a real match. The suites are listed in
    `docs/TESTING.md`. If you touched networking, run `test_net_sim` and `test_net`; if you
    touched generation, `test_cave` and `test_wallwalk`.
18. If you touched gravity, re-run AXIS-007: all six orientations, 20+ chained shifts, verify
    the basis is still orthonormal and the camera has not rolled.
19. Update `docs/TASK_BOARD.md` status.
20. Update the docs if you changed architecture or a rule. A stale document is worse than none.
21. Record any external asset in `CREDITS.md` the moment you add it — licence, author, source
    URL, modifications. Record substantial AI assistance in `AI_DISCLOSURE.md`.
22. **Never claim something works if you did not run it.** If Godot was not available in your
    environment, say so plainly. A false "tested and working" has cost this project real time.

## Things you must not do without an explicit human decision

- Change any of the twelve non-negotiable rules in `AI_CONTEXT.md`
- Change the number of Move charges (5) or hearts (5)
- Make a Gravity Move require a nearby surface
- Make the protected vacuum-180 case eliminate rather than damage
- Reveal the exit on the HUD or any map
- Switch the renderer away from GL Compatibility
- Rewrite the architecture because you would have designed it differently
- Delete or overwrite work you did not write
- Rewrite git history — the jam rules require an honest commit record inside the official
  development window

## Commit discipline

- Reference the Task ID: `AXIS-003: 90-degree gravity shift with basis slerp`
- Commit only when the human has asked you to
- Never commit secrets, builds, `.godot/` caches or imported artefacts
- The jam requires all commits to fall inside 10–17 September 2026

## If you are running low on context

Re-read `AI_CONTEXT.md`. It is written to be the minimum sufficient briefing. Do not try to
reconstruct the design by reading code — read the document, then the code.
