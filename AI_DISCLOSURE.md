# AI Disclosure

AI tools were used substantially during development of this project.

| Tool | Used for |
|---|---|
| Claude (Anthropic), via Claude Code | Planning documents in `docs/`; implementation and tests for the gravity controller, cave generator and builder, match rules, health, bots, hazards, mystery boxes, synthesised audio, menus, HUD and pause menu; export configuration; README |

How it was used:

- The team wrote the game design (rules, theme interpretation, scope). The AI implemented
  against those documents and Task IDs in `docs/TASK_BOARD.md`.
- Every system has automated tests (`tests/`) that were run headless in Godot 4.7.2, and
  screenshots were captured and reviewed, rather than trusting generated code by eye.
- No AI-generated images, music or voice are used. All audio is procedurally synthesised by
  code in `autoload/audio_manager.gd`.
