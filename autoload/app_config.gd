extends Node
## Central tunables and build configuration.
## This file holds values only. It must never contain behaviour.
## See docs/ARCHITECTURE.md.

# --- Identity -----------------------------------------------------------------
## Change the public title here and nowhere else.
const GAME_TITLE := "GAME_TITLE_TBD"
const TEAM_NAME := "Team Optimus"

# --- Gravity Move (see docs/CORE_MECHANICS.md) --------------------------------
## Non-negotiable: every racer starts with exactly 5 charges.
const MOVE_CHARGES_START := 5
const MOVE_CHARGES_MAX := 8
## Below ~0.25 s reads as a jarring snap, above ~0.5 s players feel loss of control.
const GRAVITY_TRANSITION_TIME := 0.35
const GRAVITY_STRENGTH := 24.0
const TERMINAL_VELOCITY := 45.0

# --- Health -------------------------------------------------------------------
const HEARTS_MAX := 5.0
const INVULNERABILITY_TIME := 1.5
const DAMAGE_FIRE := 0.5
const DAMAGE_SPIDER := 1.0
const DAMAGE_VACUUM_FALL := 1.0

# --- Movement -----------------------------------------------------------------
const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.5
const ACCELERATION := 12.0
const FRICTION := 14.0
const JUMP_VELOCITY := 8.0
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := 1.55  # radians, just under 89 degrees

# --- Safe transform recovery --------------------------------------------------
const SAFE_TRANSFORM_INTERVAL := 0.4
const SAFE_TRANSFORM_HISTORY := 8
const WORLD_BOUNDS := 250.0

# --- Feature flags ------------------------------------------------------------
## Networking is Tier 3 and gated. Offline play must never depend on it.
const NETWORKING_ENABLED := false
const DEBUG_HUD := true
