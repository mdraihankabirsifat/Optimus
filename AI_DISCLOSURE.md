# AI Disclosure

AI tools were used substantially during development of this project. The AI is a tool, not a
team member; Team Optimus made the design decisions and is responsible for the submission.

| Tool | Used for |
|---|---|
| Claude (Anthropic), via Claude Code | Planning documents in `docs/`; implementation and tests for the gravity controller, cave generator, builder and gravity-aware validator, match rules, health, bots, hazards, mystery boxes, synthesised audio, menus, HUD and pause menu; online multiplayer (WebSocket server, rooms, lobby, authority, synchronisation), the online lobby UI, Docker and Render files; export configuration; README, networking, testing and submission documents |

How it was used:

- The team wrote the game design (rules, theme interpretation, scope decisions) in the master
  implementation prompt. The AI implemented against it and against Task IDs in `docs/TASK_BOARD.md`.
- Every system has automated tests in `tests/` that were run headless in Godot 4.7.2 on the
  development machines, including a real three-process WebSocket race and a Docker server run.
  Results are recorded in `docs/TESTING.md`. Nothing is claimed as working without being run.
- No AI-generated images, music or voice are used. All audio is procedurally synthesised by code
  in `autoload/audio_manager.gd`, and all visuals are built from primitive meshes and noise in code.
- The itch.io page copy and video shot list in `docs/SUBMISSION_CHECKLIST.md` were drafted with AI
  assistance and are edited by the team before publishing.
