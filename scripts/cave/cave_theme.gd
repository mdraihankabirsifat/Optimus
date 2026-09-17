class_name CaveTheme
extends Resource
## ART-012: an environment as data. Everything that makes Stone Age look like Stone Age --
## surface colours, stone texture, decor materials, lights, fog, ambience -- lives here, and
## CaveBuilder and GameWorld read it. Gameplay and generation never look at a theme, so the
## same seed builds the same cave, with the same hazards and the same exit, in every theme.
##
## Readability rules every theme keeps (see docs/CORE_MECHANICS.md):
##   - floors warm, ceilings cool, walls neutral, so a racer on a wall still knows world-up
##   - the finish stays amber and the gravity preview stays sky blue
##   - never so dark that navigation is unpleasant; Dark Cave carries a personal lamp

@export var id: String = "stone_age"
@export var display_name: String = "Stone Age"
@export var blurb: String = ""

@export_group("Surfaces")
@export var floor_colour := Color(0.58, 0.47, 0.36)
@export var ceiling_colour := Color(0.34, 0.39, 0.52)
@export var wall_colour := Color(0.46, 0.45, 0.43)
## Mottle frequency of the albedo noise, and the cellular bump frequency.
@export var stone_frequency: float = 0.02
@export var bump_frequency: float = 0.045
@export var bump_strength: float = 6.0
@export var roughness: float = 0.95

@export_group("Decor")
@export var rock_colour := Color(0.40, 0.34, 0.28)
@export var moss_colour := Color(0.25, 0.42, 0.18)
@export var moss_glow: float = 0.25
@export var crystal_colours: Array[Color] = [
	Color(0.25, 0.6, 0.85), Color(0.55, 0.3, 0.85), Color(0.3, 0.8, 0.45), Color(0.85, 0.35, 0.55)]
@export var flame_colour := Color(1.0, 0.55, 0.15)
@export var torch_light_colour := Color(1.0, 0.6, 0.25)
## Extra props this environment scatters: "" none, "roots", "glowworms", "pipes".
@export var signature_props: String = ""
@export var prop_colour := Color(0.3, 0.22, 0.12)
@export var prop_glow: float = 0.0

@export_group("Lighting")
@export var route_light_colour := Color(1.0, 0.92, 0.78)
@export var route_light_energy: float = 2.4
@export var background_colour := Color(0.04, 0.035, 0.045)
@export var ambient_colour := Color(0.62, 0.58, 0.54)
@export var ambient_energy: float = 1.1
@export var fog_colour := Color(0.12, 0.1, 0.11)
## ART-008: depth fog as a gradient, not a flat haze. Nothing fogs before `fog_begin`, so the
## cell you stand in and the doorway ahead stay crisp; past `fog_end` the fog reaches
## `fog_density`, which stays below 1 so distant geometry fades rather than disappearing.
## Cells are 8 units, so these read as: clear for a cell or two, hazy by three, far by seven.
@export var fog_begin: float = 8.0
@export var fog_end: float = 60.0
@export var fog_curve: float = 1.15
@export var fog_density: float = 0.9


## How much fog sits between the camera and something this far away, 0 to 1. The engine
## computes the same curve; this exists so the readability targets can be tested.
func fog_factor(distance: float) -> float:
	var span: float = maxf(0.001, fog_end - fog_begin)
	var t: float = clampf((distance - fog_begin) / span, 0.0, 1.0)
	return pow(t, fog_curve) * fog_density
## A light carried by the local racer, 0 for none. Moves with the racer onto walls and
## ceilings, so the lamp always lights whatever that racer calls "ahead".
@export var personal_light_energy: float = 0.0
@export var personal_light_colour := Color(1.0, 0.85, 0.6)

@export_group("Audio")
@export var ambience_pitch: float = 1.0
@export var ambience_volume_db: float = 0.0


## In the order the master prompt sets: Stone Age first, then Jungle, Dark Cave, City Drain.
const IDS: Array[String] = ["stone_age", "jungle", "dark_cave", "city_drain"]


static func by_id(theme_id: String) -> CaveTheme:
	match theme_id:
		"jungle": return jungle()
		"dark_cave": return dark_cave()
		"city_drain": return city_drain()
	return stone_age()


static func index_of(theme_id: String) -> int:
	return maxi(0, IDS.find(theme_id))


static func stone_age() -> CaveTheme:
	var t := CaveTheme.new()
	t.blurb = "Ancient rock, torchlight and crystal."
	return t


static func jungle() -> CaveTheme:
	var t := CaveTheme.new()
	t.id = "jungle"
	t.display_name = "Jungle"
	t.blurb = "Damp green stone, roots through the ceiling, warm green light."
	t.floor_colour = Color(0.46, 0.44, 0.28)
	t.ceiling_colour = Color(0.26, 0.4, 0.36)
	t.wall_colour = Color(0.36, 0.43, 0.33)
	t.stone_frequency = 0.03
	t.bump_frequency = 0.06
	t.bump_strength = 4.5
	t.roughness = 0.8
	t.rock_colour = Color(0.3, 0.33, 0.22)
	t.moss_colour = Color(0.28, 0.6, 0.2)
	t.moss_glow = 0.45
	t.crystal_colours = [Color(0.45, 0.85, 0.35), Color(0.9, 0.8, 0.3), Color(0.35, 0.8, 0.65), Color(0.85, 0.45, 0.3)]
	t.flame_colour = Color(1.0, 0.7, 0.25)
	t.torch_light_colour = Color(1.0, 0.8, 0.4)
	t.signature_props = "roots"
	t.prop_colour = Color(0.28, 0.2, 0.1)
	t.route_light_colour = Color(0.85, 1.0, 0.7)
	t.route_light_energy = 2.2
	t.background_colour = Color(0.03, 0.05, 0.03)
	t.ambient_colour = Color(0.55, 0.66, 0.5)
	t.ambient_energy = 1.05
	t.fog_colour = Color(0.08, 0.13, 0.08)
	t.fog_begin = 8.0
	t.fog_end = 56.0
	t.fog_curve = 1.2
	t.fog_density = 0.95
	t.ambience_pitch = 1.15
	return t


static func dark_cave() -> CaveTheme:
	var t := CaveTheme.new()
	t.id = "dark_cave"
	t.display_name = "Dark Cave"
	t.blurb = "Low light, glow-worm ceilings, and the lamp you carry."
	t.floor_colour = Color(0.4, 0.33, 0.27)
	t.ceiling_colour = Color(0.22, 0.26, 0.38)
	t.wall_colour = Color(0.3, 0.29, 0.29)
	t.stone_frequency = 0.025
	t.bump_strength = 7.0
	t.rock_colour = Color(0.26, 0.22, 0.2)
	t.moss_colour = Color(0.15, 0.25, 0.2)
	t.moss_glow = 0.15
	t.crystal_colours = [Color(0.2, 0.5, 1.0), Color(0.35, 0.3, 1.0), Color(0.2, 0.9, 0.8), Color(0.6, 0.3, 1.0)]
	t.flame_colour = Color(1.0, 0.45, 0.12)
	t.torch_light_colour = Color(1.0, 0.5, 0.2)
	t.signature_props = "glowworms"
	t.prop_colour = Color(0.45, 0.9, 1.0)
	t.prop_glow = 2.2
	t.route_light_colour = Color(0.7, 0.75, 1.0)
	t.route_light_energy = 1.2
	t.background_colour = Color(0.01, 0.01, 0.02)
	t.ambient_colour = Color(0.36, 0.38, 0.48)
	t.ambient_energy = 0.55
	t.fog_colour = Color(0.02, 0.02, 0.04)
	# The dark cave closes in: clear for one cell, gone by four.
	t.fog_begin = 5.0
	t.fog_end = 34.0
	t.fog_curve = 1.0
	t.fog_density = 1.0
	t.personal_light_energy = 2.2
	t.personal_light_colour = Color(1.0, 0.86, 0.62)
	t.ambience_pitch = 0.8
	t.ambience_volume_db = 2.0
	return t


static func city_drain() -> CaveTheme:
	var t := CaveTheme.new()
	t.id = "city_drain"
	t.display_name = "City Drain"
	t.blurb = "Grey concrete tunnels, green pipes along the walls, sodium light."
	# Concrete greys. The floor keeps a slight warmth and the ceiling a slight chill, so the
	# floor/ceiling reading rule still holds.
	t.floor_colour = Color(0.5, 0.49, 0.46)
	t.ceiling_colour = Color(0.4, 0.44, 0.5)
	t.wall_colour = Color(0.56, 0.57, 0.58)
	t.stone_frequency = 0.09
	t.bump_frequency = 0.2
	t.bump_strength = 1.5
	t.roughness = 0.9
	t.rock_colour = Color(0.42, 0.42, 0.42)
	t.moss_colour = Color(0.32, 0.42, 0.22)
	t.moss_glow = 0.1
	t.crystal_colours = [Color(0.9, 0.55, 0.15), Color(0.3, 0.8, 0.4), Color(0.95, 0.9, 0.4), Color(0.4, 0.7, 0.9)]
	t.flame_colour = Color(1.0, 0.6, 0.2)
	t.torch_light_colour = Color(1.0, 0.62, 0.22)
	t.signature_props = "pipes"
	t.prop_colour = Color(0.18, 0.36, 0.28)
	t.route_light_colour = Color(1.0, 0.72, 0.38)
	t.route_light_energy = 2.0
	t.background_colour = Color(0.03, 0.035, 0.035)
	t.ambient_colour = Color(0.56, 0.6, 0.62)
	t.ambient_energy = 1.0
	t.fog_colour = Color(0.09, 0.11, 0.1)
	t.fog_begin = 9.0
	t.fog_end = 60.0
	t.fog_curve = 1.25
	t.fog_density = 0.92
	t.ambience_pitch = 0.9
	return t


## Push this theme's lighting into a race's Environment.
func apply_environment(env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_colour
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_colour
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = fog_colour
	env.fog_depth_begin = fog_begin
	env.fog_depth_end = fog_end
	env.fog_depth_curve = fog_curve
	env.fog_density = fog_density
	env.fog_sky_affect = 0.0
