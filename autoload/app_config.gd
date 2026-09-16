extends Node
## Central tunables and build configuration.
## This file holds values only. It must never contain behaviour.
## See docs/ARCHITECTURE.md.

# --- Identity -----------------------------------------------------------------
## Change the public title here and nowhere else.
const GAME_TITLE := "SIX WAYS DOWN"
const TEAM_NAME := "Team Optimus"

# --- Gravity Move (see docs/CORE_MECHANICS.md) --------------------------------
## Non-negotiable: every racer starts with exactly 5 charges.
const MOVE_CHARGES_START := 5
const MOVE_CHARGES_MAX := 8
## Below ~0.25 s reads as a jarring snap, above ~0.5 s players feel loss of control.
const GRAVITY_TRANSITION_TIME := 0.35
const GRAVITY_STRENGTH := 24.0
const TERMINAL_VELOCITY := 45.0

# --- Match flow ---
const MATCH_COUNTDOWN_SECONDS := 3
## Hard cap so a lost racer cannot stall the whole lobby. Judges play once, briefly.
const MATCH_TIME_LIMIT := 300.0

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

## Grace after leaving the floor during which a jump still counts. Makes ledges forgiving.
const COYOTE_TIME := 0.12
## Planar distance between footstep sounds.
const FOOTSTEP_DISTANCE := 2.7

# --- Safe transform recovery --------------------------------------------------
const SAFE_TRANSFORM_INTERVAL := 0.4
const SAFE_TRANSFORM_HISTORY := 8
const WORLD_BOUNDS := 250.0

# --- Hazards ------------------------------------------------------------------
## Seconds between fire ticks on one racer. Standing in fire drains at a fair rate.
const FIRE_TICK_COOLDOWN := 1.0
## Fraction of eligible cells that receive a fire patch.
const FIRE_DENSITY := 0.16
## Hop distance from spawn inside which nothing dangerous may be placed.
const HAZARD_MIN_SPAWN_DISTANCE := 3

# --- Mystery boxes ------------------------------------------------------------
const BOX_DENSITY := 0.22
const BOX_MIN_SPAWN_DISTANCE := 1
const INTERACT_RANGE := 3.6
## Relative weights. Clue must stay clearly rare (about 5%).
const LOOT_TABLE := {
	"heart": 24,
	"move": 22,
	"speed": 18,
	"shield": 10,
	"slow": 10,
	"lose_move": 6,
	"clue": 5,
}
const HEART_REFILL_AMOUNT := 1.0
const MOVE_REFILL_AMOUNT := 1
const SPEED_BOOST_MULTIPLIER := 1.4
const SPEED_BOOST_TIME := 8.0
const SLOW_MULTIPLIER := 0.6
const SLOW_TIME := 5.0
## How long the clue arrow stays on screen. Coarse direction only, never the exit itself.
const CLUE_TIME := 9.0

# --- Match pacing -------------------------------------------------------------
## Once the local player has finished or been eliminated, the race ends after this many
## seconds even if bots are still searching. Judges should never wait on a lost bot.
const LOCAL_RESOLVED_GRACE := 20.0

# --- Feature flags ------------------------------------------------------------
## Networking is Tier 3 and gated. Offline play must never depend on it.
const NETWORKING_ENABLED := false
const DEBUG_HUD := true
