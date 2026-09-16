# ARCHITECTURE

Godot 4.7, GDScript, GL Compatibility renderer. Optimised for four people working in parallel
with minimal merge conflicts, not for elegance.

---

## Folder layout

```
res://
  project.godot
  autoload/
    app_config.gd        # GAME_TITLE_TBD, tunables, build flags. No logic.
    game_state.gd        # match state, placements, seed. Single source of truth.
    settings_manager.gd  # volume, sensitivity; saves to user://settings.cfg
    audio_manager.gd     # bus routing, one-shot SFX helper
    scene_router.gd      # scene transitions; nobody else calls change_scene
    net_manager.gd       # Tier 3. Stubbed no-op until networking starts.
  scenes/
    ui/        splash, main_menu, mode_select, lobby, settings,
               how_to_play, about, credits, hud, pause_menu, results
    game/      game_world.tscn, match_controller.tscn,
               finish_area.tscn, spawn_area.tscn
    player/    player.tscn
    bots/      bot_player.tscn
    cave/      modules/ (corridor, junction, shaft, chamber, cap)
    hazards/   fire_hazard.tscn
    pickups/   mystery_box.tscn
  scripts/
    player/    player_controller.gd, gravity_controller.gd,
               player_health.gd, player_interaction.gd, camera_controller.gd
    bots/      bot_controller.gd, bot_knowledge.gd, bot_planner.gd
    cave/      cave_generator.gd, cave_graph.gd, cave_builder.gd, cave_theme.gd
    gameplay/  match_controller.gd, mystery_box.gd, fire_hazard.gd
    ui/        hud.gd, menu scripts
  assets/
    models/ materials/ textures/ audio/ fonts/
  docs/
```

---

## Autoloads

Six, and no more. Every autoload added after this is a coupling problem for someone else.

| Autoload | Owns | Must NOT |
|---|---|---|
| `AppConfig` | Constants, tunables, title, feature flags | Contain any behaviour |
| `GameState` | Racer roster, seed, placements, match phase, timer | Touch nodes or UI |
| `SettingsManager` | User prefs, persistence | Know about gameplay |
| `AudioManager` | Bus volumes, `play_sfx(name, position)` | Decide when sounds happen |
| `SceneRouter` | All scene changes | Hold gameplay state |
| `NetManager` | Tier 3 networking. **No-op stub until Phase 5.** | Be required by offline play |

**`NetManager` must remain a stub that offline mode never calls.** The offline Bot Race is the
judging fallback; if it can break when networking breaks, the fallback is worthless.

---

## The cave: graph first, geometry second

Two separate things, and keeping them separate is what makes this affordable:

**`cave_graph.gd`** — pure data, no nodes. A dictionary of `Vector3i` cell → connection bitmask
over the six cardinal directions, plus spawn cell, finish cell, and the spine route. Fully
testable without running the game. Serialisable, hashable, and cheap to send over the network.

**`cave_builder.gd`** — reads the graph and instantiates modular meshes. Picks a module scene per
cell based on its connection mask. Knows nothing about generation rules.

**`cave_generator.gd`** — seeded. Builds the spine from spawn to finish first (guaranteeing
solvability by construction, see `MVP_SCOPE.md`), then braids in loops, branches and dead ends,
then places hazards and boxes deterministically from the same `RandomNumberGenerator`.

Everything derives from one integer seed. Same seed plus same generator version means the same
cave on every machine, which is what makes networked play cheap: send 4 bytes, not a level.

The bot's discovered graph is a **separate `CaveGraph` instance** that starts empty and only
gains cells the bot has actually observed. That separation is the entire anti-cheat design —
`bot_planner.gd` must never be handed a reference to the real graph.

---

## Scripts, and what each must not do

| Script | Responsibility | Must NOT |
|---|---|---|
| `player_controller.gd` | Input, walk/sprint, `move_and_slide` | Own gravity direction, own health |
| `gravity_controller.gd` | `gravity_dir`, basis slerp, charges, safe-transform history | Read input directly, apply movement |
| `player_health.gd` | Hearts, damage cooldown, invulnerability, elimination | Decide what deals damage |
| `player_interaction.gd` | Interact raycast, `E` prompt | Decide box contents |
| `camera_controller.gd` | Yaw on body, pitch on head, FOV, shift effect | Rotate for gravity — that's `gravity_controller` |
| `match_controller.gd` | Countdown, timer, finish order, elimination order, results | Own player state |
| `cave_generator.gd` | Seeded graph generation + validation | Instantiate nodes |
| `cave_builder.gd` | Graph → scene instantiation | Make generation decisions |
| `bot_knowledge.gd` | Discovered graph, observation, memory | Access the real cave graph |
| `bot_planner.gd` | Frontier search over discovered graph | Access the real cave graph |
| `bot_controller.gd` | Drive a player body from planner output | Bypass normal movement rules |
| `hud.gd` | Display state | Mutate state |

`gravity_controller.gd` and `player_controller.gd` being separate is the most important split
here. The gravity frame is the thing every other system reads, and it needs to be one small
file that one person owns and everyone else treats as read-only.

---

## Signals

Decouple across systems; direct calls within a system. The set worth defining up front:

```
GravityController:  shift_started(new_dir)  shift_completed(new_dir)
                    charges_changed(n)      shift_denied()
PlayerHealth:       damaged(amount, source) hearts_changed(n)  eliminated()
MatchController:    countdown_tick(n)  match_started()
                    racer_finished(id, place, time)  match_ended(results)
MysteryBox:         opened(player_id, reward)
```

HUD listens. HUD never polls, and never writes.

---

## Authority (Tier 3, when networking exists)

Server owns: seed, countdown, timer, **charge deduction**, damage, health, box contents and
contention, clue grants, finish detection, placements, elimination, bot decisions.

Client owns: local input, movement prediction, interpolation of remotes, all rendering and UI.

Clients never award themselves a charge, a heart, loot, or a placement. Player transforms sync
frequently and unreliably; everything in the server-owned list uses reliable RPC.

---

## Conventions

- `snake_case` files and variables, `PascalCase` nodes and classes
- Typed GDScript where it costs nothing: `var speed: float = 6.0`
- Tunables go in `AppConfig` or `@export`, never inline magic numbers
- No plugins
- No file over ~300 lines without a good reason

---

## The rule that matters most

**Never write `Vector3.UP` in gameplay code.** Use the player's `local_up`. This will be the
cause of most bugs in this project. Grep for it before every commit.
